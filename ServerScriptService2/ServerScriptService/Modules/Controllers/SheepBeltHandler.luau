--!strict

--[[
	New sheep ride each plot's Conveyor.Belt from Feed to PenDrop, up to QUEUE_SIZE at a time, then hop into the pen while it has room and walk straight off.
	The belt's Paused attribute is true while the pen is full and nothing is riding (ConveyorHandler and ConveyorClient follow it).

	Location: ServerScriptService.Modules.Controllers.SheepBeltHandler
]]--

--// Services
local runService = game:GetService("RunService")

--// Modules
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// Configs
local CONVEYOR_NAME = "Conveyor"
local BELT_NAME = "Belt"
local FEED_NAME = "Feed"
local DROP_NAME = "PenDrop"
local PAUSED_ATTRIBUTE = "Paused"
local SPEED_ATTRIBUTE = "Speed" -- set in Studio
local RIDE_SPEED_ATTRIBUTE = "RideSpeed" -- the speed actually used (never below Speed); ConveyorHandler and ConveyorClient follow it
local DEFAULT_SPEED = 10 -- studs/s when the belt has no Speed attribute
local FEED_SPACING = FarmData.Belt.FeedSpacing -- so RideSpeed >= FEED_SPACING / refill interval
local QUEUE_SIZE = FarmData.Belt.QueueSize
local QUEUE_GAP = FarmData.Belt.QueueGap
local HOP_DISTANCE = FarmData.Belt.HopDistance
local HOP_HEIGHT = FarmData.Belt.HopHeight
local HOP_SECONDS = FarmData.Belt.HopSeconds

type Rider = {
	sheep: Model,
	rootToPivot: CFrame,
	lift: number, -- root height above the belt
	halfLength: number, -- along the belt
	distance: number, -- from Feed
	target: number,
}

type Hop = {
	sheep: Model,
	rootToPivot: CFrame,
	lift: number,
	from: Vector3,
	to: Vector3, -- ground the feet land on
	heading: Vector3,
	elapsed: number,
}

type Farm = {
	plot: Instance,
	belt: BasePart,
	feed: Attachment,
	drop: Attachment,
	roll: (at: CFrame) -> Model?,
	queue: { Rider },
	hops: { Hop },
	freeSlots: number,
}

--// State
local farms: { [Player]: Farm } = {}
local heartbeat: RBXScriptConnection? = nil

local SheepBeltHandler = {}

--// Belt geometry ------------------------------------------------------------------------

local function getEnds(farm: Farm): (Vector3, Vector3, number)
	local feed, drop = farm.feed.WorldPosition, farm.drop.WorldPosition
	local offset = drop - feed
	return feed, offset.Unit, offset.Magnitude
end

local function getBaseSpeed(farm: Farm): number
	local speed = farm.belt:GetAttribute(SPEED_ATTRIBUTE)
	return if type(speed) == "number" and speed > 0 then speed else DEFAULT_SPEED
end

local function getSpeed(farm: Farm): number
	local speed = farm.belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	return if type(speed) == "number" and speed > 0 then speed else getBaseSpeed(farm)
end

-- Short refill intervals (Faster Respawn, Rain, podiums) speed the belt up so it still delivers one sheep per interval.
local function updateRideSpeed(farm: Farm, interval: number)
	local speed = math.max(getBaseSpeed(farm), FEED_SPACING / math.max(interval, 0.05))
	local current = farm.belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	if type(current) ~= "number" or math.abs(current - speed) > 0.05 then
		farm.belt:SetAttribute(RIDE_SPEED_ATTRIBUTE, speed)
	end
end

local function isMoving(farm: Farm): boolean
	if #farm.hops > 0 then
		return true
	end
	for _, rider in farm.queue do
		if rider.distance < rider.target then
			return true
		end
	end
	return false
end

-- The belt only stops while the pen is full and no sheep is moving on it.
local function updatePaused(farm: Farm)
	local paused = farm.freeSlots - #farm.hops <= 0 and not isMoving(farm)
	if farm.belt:GetAttribute(PAUSED_ATTRIBUTE) ~= paused then
		farm.belt:SetAttribute(PAUSED_ATTRIBUTE, paused)
	end
end

local function poseRider(farm: Farm, rider: Rider)
	local feed, heading = getEnds(farm)
	local point = feed + heading * rider.distance + Vector3.new(0, rider.lift, 0)
	rider.sheep:PivotTo(CFrame.lookAt(point, point + heading) * rider.rootToPivot)
end

-- Front rider waits with its nose at PenDrop; each one behind keeps QUEUE_GAP to the one ahead.
local function retarget(farm: Farm)
	local _, _, length = getEnds(farm)
	local front = length
	for _, rider in farm.queue do
		rider.target = math.max(front - rider.halfLength, rider.distance)
		front = rider.target - rider.halfLength - QUEUE_GAP
	end
end

--// Movement --------------------------------------------------------------------------------

local function stepHop(hop: Hop, dt: number): boolean
	hop.elapsed += dt
	local alpha = math.min(hop.elapsed / HOP_SECONDS, 1)
	local point = hop.from:Lerp(hop.to, alpha) + Vector3.new(0, hop.lift + HOP_HEIGHT * math.sin(math.pi * alpha), 0)
	hop.sheep:PivotTo(CFrame.lookAt(point, point + hop.heading) * hop.rootToPivot)
	return alpha >= 1
end

local function stepFarm(farm: Farm, dt: number)
	local speed = getSpeed(farm)
	local wasMoving = isMoving(farm)

	for _, rider in farm.queue do
		if rider.distance < rider.target then
			rider.distance = math.min(rider.distance + speed * dt, rider.target)
			poseRider(farm, rider)
		end
	end

	for index = #farm.hops, 1, -1 do
		local hop = farm.hops[index]
		if stepHop(hop, dt) then
			table.remove(farm.hops, index)
			if SheepHandler.admitBeltSheep(hop.sheep, hop.to) then -- CountChanged then updates freeSlots
				SheepWanderHandler.walkAwayFrom(hop.sheep, hop.to)
			end
		end
	end

	if wasMoving and not isMoving(farm) then
		updatePaused(farm)
	end
end

local function onHeartbeat(dt: number)
	local anyMoving = false
	for _, farm in farms do
		stepFarm(farm, dt)
		anyMoving = anyMoving or isMoving(farm)
	end
	if not anyMoving and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function wake()
	if not heartbeat then
		heartbeat = runService.Heartbeat:Connect(onHeartbeat)
	end
end

--// Queue -----------------------------------------------------------------------------------

-- Ground HOP_DISTANCE to whichever side of PenDrop lies inside the SheepArea (the side the area had to move less).
local function getLanding(farm: Farm): Vector3?
	local drop = farm.drop.WorldPosition
	local side = farm.belt.CFrame.RightVector * HOP_DISTANCE
	local best: Vector3?, bestShift = nil, math.huge
	for _, wanted in { drop + side, drop - side } do
		local ground = SheepWanderHandler.getGroundNear(farm.plot, wanted)
		local shift = if ground then Vector3.new(ground.X - wanted.X, 0, ground.Z - wanted.Z).Magnitude else math.huge
		if ground and shift < bestShift then
			best, bestShift = ground, shift
		end
	end
	return best
end

-- The front sheep, once it waits at PenDrop and the pen has room, hops sideways into the pen.
local function tryDrop(farm: Farm): boolean
	local rider = farm.queue[1]
	if not rider or rider.distance < rider.target or farm.freeSlots - #farm.hops <= 0 then
		return false
	end

	local root = rider.sheep:FindFirstChild("HumanoidRootPart")
	local _, heading = getEnds(farm)
	local landing = getLanding(farm)
	if not landing or not root or not root:IsA("BasePart") then
		return false
	end

	table.remove(farm.queue, 1)
	table.insert(farm.hops, {
		sheep = rider.sheep,
		rootToPivot = rider.rootToPivot,
		lift = rider.lift,
		from = root.Position - Vector3.new(0, rider.lift, 0),
		to = landing,
		heading = heading,
		elapsed = 0,
	})
	retarget(farm)
	return true
end

-- Rolls the next sheep at Feed if the belt has room for it behind the last one.
local function tryAdd(farm: Farm): boolean
	if #farm.queue >= QUEUE_SIZE then
		return false
	end
	local last = farm.queue[#farm.queue]
	if last and last.distance < math.min(last.halfLength * 2 + QUEUE_GAP, FEED_SPACING) then
		return false -- no room behind the last one yet (assumes the next sheep is about its size)
	end

	local feed, heading = getEnds(farm)
	local sheep = farm.roll(CFrame.lookAt(feed, feed + heading))
	local root = sheep and sheep:FindFirstChild("HumanoidRootPart")
	if not sheep or not root or not root:IsA("BasePart") then
		return false
	end

	local boxCFrame, boxSize = sheep:GetBoundingBox()
	local along = boxCFrame:VectorToObjectSpace(heading)
	local halfLength = (math.abs(along.X) * boxSize.X + math.abs(along.Y) * boxSize.Y + math.abs(along.Z) * boxSize.Z) / 2
	table.insert(farm.queue, {
		sheep = sheep,
		rootToPivot = root.CFrame:ToObjectSpace(sheep:GetPivot()),
		lift = root.Position.Y - feed.Y,
		halfLength = halfLength,
		distance = 0,
		target = 0,
	})
	retarget(farm)
	return true
end

local function clearQueue(farm: Farm)
	for _, rider in farm.queue do
		SheepHandler.discardBeltSheep(rider.sheep)
	end
	for _, hop in farm.hops do
		SheepHandler.discardBeltSheep(hop.sheep)
	end
	table.clear(farm.queue)
	table.clear(farm.hops)
end

--// Public API ------------------------------------------------------------------------------

--[[
	Starts the player's belt. `roll` builds a belt sheep with its feet at the given CFrame (SheepHandler.spawnBeltSheep).
	Returns false when the plot has no Conveyor.Belt with Feed and PenDrop, so the caller spawns straight into the pen instead.
]]
function SheepBeltHandler.start(player: Player, plot: Instance, roll: (at: CFrame) -> Model?): boolean
	local conveyor = plot:FindFirstChild(CONVEYOR_NAME)
	local belt = conveyor and conveyor:FindFirstChild(BELT_NAME)
	local feed = belt and belt:FindFirstChild(FEED_NAME)
	local drop = belt and belt:FindFirstChild(DROP_NAME)
	if not belt or not belt:IsA("BasePart") or not feed or not feed:IsA("Attachment") or not drop or not drop:IsA("Attachment") then
		warn(`SheepBeltHandler: {plot.Name} has no {CONVEYOR_NAME}.{BELT_NAME} with {FEED_NAME} and {DROP_NAME} attachments; build it in Studio. Sheep spawn straight into the pen.`)
		return false
	end

	farms[player] = {
		plot = plot,
		belt = belt,
		feed = feed,
		drop = drop,
		roll = roll,
		queue = {},
		hops = {},
		freeSlots = 0,
	}
	return true
end

-- One spawn tick (every `interval` seconds): lets the front sheep into the pen if there's room, then rolls a new one at Feed.
function SheepBeltHandler.step(player: Player, interval: number)
	local farm = farms[player]
	if not farm then
		return
	end
	updateRideSpeed(farm, interval)
	local changed = tryDrop(farm)
	changed = tryAdd(farm) or changed
	if changed then
		wake()
	end
	updatePaused(farm)
end

-- How many more sheep the pen holds right now (max minus count); called whenever either changes.
function SheepBeltHandler.setFreeSlots(player: Player, freeSlots: number)
	local farm = farms[player]
	if farm then
		farm.freeSlots = freeSlots
		updatePaused(farm)
	end
end

-- Pools every sheep on the player's belt (used when their farm is reset).
function SheepBeltHandler.clear(player: Player)
	local farm = farms[player]
	if farm then
		clearQueue(farm)
		updatePaused(farm)
	end
end

-- Clears the belt and stops it; the plot's next owner starts it again.
function SheepBeltHandler.stop(player: Player)
	local farm = farms[player]
	if not farm then
		return
	end
	clearQueue(farm)
	farms[player] = nil
	farm.belt:SetAttribute(PAUSED_ATTRIBUTE, true)
end

return SheepBeltHandler
