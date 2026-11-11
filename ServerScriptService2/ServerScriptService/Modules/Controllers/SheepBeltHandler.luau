--!strict

--[[
	New sheep ride each plot's belts (Conveyor, plus RobuxConveyor once unlocked) from Feed to PenDrop, up to QUEUE_SIZE per belt, then hop into the pen while it has room.
	A belt's Paused attribute is true while the pen is full and nothing rides it, or while it is locked (ConveyorHandler and ConveyorClient follow it).

	Location: ServerScriptService.Modules.Controllers.SheepBeltHandler
]]--

--// Services
local runService = game:GetService("RunService")

--// Modules
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// Configs
local MAIN_LINE = "Conveyor"
local EXTRA_LINES = { "RobuxConveyor" } -- locked (Studio look, paused) until setLineEnabled
local BELT_NAME = "Belt"
local FEED_NAME = "Feed"
local DROP_NAME = "PenDrop"
local PAUSED_ATTRIBUTE = "Paused"
local UNLOCKED_ATTRIBUTE = "Unlocked" -- on an extra belt's model, for RobuxConveyorClient
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

type PartLook = { part: BasePart, color: Color3, transparency: number, material: Enum.Material }
type TextureLook = { texture: Texture, color: Color3, transparency: number }

type Line = {
	model: Instance,
	belt: BasePart,
	feed: Attachment,
	drop: Attachment,
	enabled: boolean,
	queue: { Rider },
	hops: { Hop },
	lockedLook: { PartLook }, -- the Studio look, put back when the belt locks again
	lockedTextures: { TextureLook },
	outlines: { SelectionBox },
}

type Farm = {
	plot: Instance,
	roll: (at: CFrame, lineName: string) -> Model?,
	lines: { [string]: Line },
	freeSlots: number,
}

--// State
local farms: { [Player]: Farm } = {}
local heartbeat: RBXScriptConnection? = nil

local SheepBeltHandler = {}

--// Belt geometry ------------------------------------------------------------------------

local function getEnds(line: Line): (Vector3, Vector3, number)
	local feed, drop = line.feed.WorldPosition, line.drop.WorldPosition
	local offset = drop - feed
	return feed, offset.Unit, offset.Magnitude
end

local function getBaseSpeed(line: Line): number
	local speed = line.belt:GetAttribute(SPEED_ATTRIBUTE)
	return if type(speed) == "number" and speed > 0 then speed else DEFAULT_SPEED
end

local function getSpeed(line: Line): number
	local speed = line.belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	return if type(speed) == "number" and speed > 0 then speed else getBaseSpeed(line)
end

-- Short refill intervals (Faster Respawn, Rain, podiums) speed the belt up so it still delivers one sheep per interval.
local function updateRideSpeed(line: Line, interval: number)
	local speed = math.max(getBaseSpeed(line), FEED_SPACING / math.max(interval, 0.05))
	local current = line.belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	if type(current) ~= "number" or math.abs(current - speed) > 0.05 then
		line.belt:SetAttribute(RIDE_SPEED_ATTRIBUTE, speed)
	end
end

local function isLineMoving(line: Line): boolean
	if #line.hops > 0 then
		return true
	end
	for _, rider in line.queue do
		if rider.distance < rider.target then
			return true
		end
	end
	return false
end

local function isMoving(farm: Farm): boolean
	for _, line in farm.lines do
		if isLineMoving(line) then
			return true
		end
	end
	return false
end

-- Pen slots not already promised to a sheep mid-hop from any belt.
local function getOpenSlots(farm: Farm): number
	local open = farm.freeSlots
	for _, line in farm.lines do
		open -= #line.hops
	end
	return open
end

-- A belt only stops while the pen is full and no sheep is moving on it; a locked belt never runs.
local function updatePaused(farm: Farm)
	local full = getOpenSlots(farm) <= 0
	for _, line in farm.lines do
		local paused = not line.enabled or (full and not isLineMoving(line))
		if line.belt:GetAttribute(PAUSED_ATTRIBUTE) ~= paused then
			line.belt:SetAttribute(PAUSED_ATTRIBUTE, paused)
		end
	end
end

local function poseRider(line: Line, rider: Rider)
	local feed, heading = getEnds(line)
	local point = feed + heading * rider.distance + Vector3.new(0, rider.lift, 0)
	rider.sheep:PivotTo(CFrame.lookAt(point, point + heading) * rider.rootToPivot)
end

-- Front rider waits with its nose at PenDrop; each one behind keeps QUEUE_GAP to the one ahead.
local function retarget(line: Line)
	local _, _, length = getEnds(line)
	local front = length
	for _, rider in line.queue do
		rider.target = math.max(front - rider.halfLength, rider.distance)
		front = rider.target - rider.halfLength - QUEUE_GAP
	end
end

--// Locked look -----------------------------------------------------------------------------

local function captureLook(model: Instance): ({ PartLook }, { TextureLook }, { SelectionBox })
	local looks, textures, outlines = {}, {}, {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(looks, { part = descendant, color = descendant.Color, transparency = descendant.Transparency, material = descendant.Material })
		elseif descendant:IsA("Texture") then
			table.insert(textures, { texture = descendant, color = descendant.Color3, transparency = descendant.Transparency })
		elseif descendant:IsA("SelectionBox") then
			table.insert(outlines, descendant)
		end
	end
	return looks, textures, outlines
end

--[[
	Unlocked, each part copies the main Conveyor's part of the same name (Frame, Belt, Rail, EndBumper), and each texture the same-named
	texture on that part (the Belt's Chevrons); locked, they go back to their Studio look.
]]
local function applyLook(farm: Farm, line: Line)
	local main = farm.lines[MAIN_LINE]
	for _, look in line.lockedLook do
		local source = if line.enabled and main then main.model:FindFirstChild(look.part.Name) else nil
		if source and source:IsA("BasePart") then
			look.part.Color, look.part.Transparency, look.part.Material = source.Color, source.Transparency, source.Material
		else
			look.part.Color, look.part.Transparency, look.part.Material = look.color, look.transparency, look.material
		end
	end
	for _, look in line.lockedTextures do
		local texture = look.texture
		local sourcePart = if line.enabled and main and texture.Parent then main.model:FindFirstChild(texture.Parent.Name) else nil
		local source = sourcePart and sourcePart:FindFirstChild(texture.Name)
		if source and source:IsA("Texture") then
			texture.Color3, texture.Transparency = source.Color3, source.Transparency
		else
			texture.Color3, texture.Transparency = look.color, look.transparency
		end
	end
	for _, outline in line.outlines do
		outline.Visible = not line.enabled
	end
	line.model:SetAttribute(UNLOCKED_ATTRIBUTE, line.enabled)
end

--// Movement --------------------------------------------------------------------------------

local function stepHop(hop: Hop, dt: number): boolean
	hop.elapsed += dt
	local alpha = math.min(hop.elapsed / HOP_SECONDS, 1)
	local point = hop.from:Lerp(hop.to, alpha) + Vector3.new(0, hop.lift + HOP_HEIGHT * math.sin(math.pi * alpha), 0)
	hop.sheep:PivotTo(CFrame.lookAt(point, point + hop.heading) * hop.rootToPivot)
	return alpha >= 1
end

local function stepLine(line: Line, dt: number)
	local speed = getSpeed(line)
	for _, rider in line.queue do
		if rider.distance < rider.target then
			rider.distance = math.min(rider.distance + speed * dt, rider.target)
			poseRider(line, rider)
		end
	end

	for index = #line.hops, 1, -1 do
		local hop = line.hops[index]
		if stepHop(hop, dt) then
			table.remove(line.hops, index)
			if SheepHandler.admitBeltSheep(hop.sheep, hop.to) then -- CountChanged then updates freeSlots
				SheepWanderHandler.boltFrom(hop.sheep, hop.to)
			end
		end
	end
end

local function stepFarm(farm: Farm, dt: number)
	local wasMoving = isMoving(farm)
	for _, line in farm.lines do
		stepLine(line, dt)
	end
	if wasMoving then
		updatePaused(farm) -- a belt that just went still stops while the pen is full
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
local function getLanding(farm: Farm, line: Line): Vector3?
	local drop = line.drop.WorldPosition
	local side = line.belt.CFrame.RightVector * HOP_DISTANCE
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
local function tryDrop(farm: Farm, line: Line): boolean
	local rider = line.queue[1]
	if not rider or rider.distance < rider.target or getOpenSlots(farm) <= 0 then
		return false
	end

	local root = rider.sheep:FindFirstChild("HumanoidRootPart")
	local _, heading = getEnds(line)
	local landing = getLanding(farm, line)
	if not landing or not root or not root:IsA("BasePart") then
		return false
	end

	table.remove(line.queue, 1)
	table.insert(line.hops, {
		sheep = rider.sheep,
		rootToPivot = rider.rootToPivot,
		lift = rider.lift,
		from = root.Position - Vector3.new(0, rider.lift, 0),
		to = landing,
		heading = heading,
		elapsed = 0,
	})
	retarget(line)
	return true
end

-- Rolls the next sheep at Feed if the belt has room for it behind the last one.
local function tryAdd(farm: Farm, line: Line, lineName: string): boolean
	if #line.queue >= QUEUE_SIZE then
		return false
	end
	local last = line.queue[#line.queue]
	if last and last.distance < math.min(last.halfLength * 2 + QUEUE_GAP, FEED_SPACING) then
		return false -- no room behind the last one yet (assumes the next sheep is about its size)
	end

	local feed, heading = getEnds(line)
	local sheep = farm.roll(CFrame.lookAt(feed, feed + heading), lineName)
	local root = sheep and sheep:FindFirstChild("HumanoidRootPart")
	if not sheep or not root or not root:IsA("BasePart") then
		return false
	end

	local boxCFrame, boxSize = sheep:GetBoundingBox()
	local along = boxCFrame:VectorToObjectSpace(heading)
	local halfLength = (math.abs(along.X) * boxSize.X + math.abs(along.Y) * boxSize.Y + math.abs(along.Z) * boxSize.Z) / 2
	table.insert(line.queue, {
		sheep = sheep,
		rootToPivot = root.CFrame:ToObjectSpace(sheep:GetPivot()),
		lift = root.Position.Y - feed.Y,
		halfLength = halfLength,
		distance = 0,
		target = 0,
	})
	retarget(line)
	return true
end

local function clearLine(line: Line)
	for _, rider in line.queue do
		SheepHandler.discardBeltSheep(rider.sheep)
	end
	for _, hop in line.hops do
		SheepHandler.discardBeltSheep(hop.sheep)
	end
	table.clear(line.queue)
	table.clear(line.hops)
end

-- The plot's belt model by that name, or nil (with a warning when it exists but is built wrong, or is the main Conveyor).
local function findLine(plot: Instance, name: string): Line?
	local model = plot:FindFirstChild(name)
	local belt = model and model:FindFirstChild(BELT_NAME)
	local feed = belt and belt:FindFirstChild(FEED_NAME)
	local drop = belt and belt:FindFirstChild(DROP_NAME)
	if not model or not belt or not belt:IsA("BasePart") or not feed or not feed:IsA("Attachment") or not drop or not drop:IsA("Attachment") then
		if model or name == MAIN_LINE then
			warn(`SheepBeltHandler: {plot.Name} has no {name}.{BELT_NAME} with {FEED_NAME} and {DROP_NAME} attachments; build it in Studio.`)
		end
		return nil
	end

	local lockedLook, lockedTextures, outlines = captureLook(model)
	return {
		model = model,
		belt = belt,
		feed = feed,
		drop = drop,
		enabled = name == MAIN_LINE,
		queue = {},
		hops = {},
		lockedLook = lockedLook,
		lockedTextures = lockedTextures,
		outlines = outlines,
	}
end

--// Public API ------------------------------------------------------------------------------

--[[
	Starts the player's belts. `roll(at, lineName)` builds a belt sheep with its feet at `at` (SheepHandler.spawnBeltSheep).
	Returns false when the plot has no Conveyor.Belt with Feed and PenDrop, so the caller spawns straight into the pen instead.
	Extra belts (RobuxConveyor) start locked and paused until setLineEnabled.
]]
function SheepBeltHandler.start(player: Player, plot: Instance, roll: (at: CFrame, lineName: string) -> Model?): boolean
	if not FarmData.Belt.Enabled then
		for _, name in { MAIN_LINE, table.unpack(EXTRA_LINES) } do
			local model = plot:FindFirstChild(name)
			if model then
				model:Destroy()
			end
		end
		return false
	end
	local main = findLine(plot, MAIN_LINE)
	if not main then
		warn(`SheepBeltHandler: sheep spawn straight into {plot.Name}'s pen instead.`)
		return false
	end

	local farm: Farm = { plot = plot, roll = roll, lines = { [MAIN_LINE] = main }, freeSlots = 0 }
	for _, name in EXTRA_LINES do
		local line = findLine(plot, name)
		if line then
			farm.lines[name] = line
			applyLook(farm, line)
		end
	end
	farms[player] = farm
	updatePaused(farm)
	return true
end

-- Unlocks or locks an extra belt (its look and whether it runs). Returns false if the player's farm or that belt doesn't exist.
function SheepBeltHandler.setLineEnabled(player: Player, lineName: string, enabled: boolean): boolean
	local farm = farms[player]
	local line = farm and farm.lines[lineName]
	if not farm or not line or lineName == MAIN_LINE then
		return false
	end
	if line.enabled ~= enabled then
		line.enabled = enabled
		if not enabled then
			clearLine(line)
		end
		applyLook(farm, line)
		updatePaused(farm)
	end
	return true
end

-- One spawn tick of a belt (every `interval` seconds): lets its front sheep into the pen if there's room, then rolls a new one at Feed.
function SheepBeltHandler.step(player: Player, interval: number, lineName: string?)
	local farm = farms[player]
	local name = lineName or MAIN_LINE
	local line = farm and farm.lines[name]
	if not farm or not line or not line.enabled then
		return
	end
	updateRideSpeed(line, interval)
	local changed = tryDrop(farm, line)
	changed = tryAdd(farm, line, name) or changed
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

-- Pools every sheep on the player's belts (used when their farm is reset).
function SheepBeltHandler.clear(player: Player)
	local farm = farms[player]
	if farm then
		for _, line in farm.lines do
			clearLine(line)
		end
		updatePaused(farm)
	end
end

-- Clears and stops the belts and locks the extra ones again; the plot's next owner starts them again.
function SheepBeltHandler.stop(player: Player)
	local farm = farms[player]
	if not farm then
		return
	end
	farms[player] = nil
	for name, line in farm.lines do
		clearLine(line)
		if name ~= MAIN_LINE then
			line.enabled = false
			applyLook(farm, line)
		end
		line.belt:SetAttribute(PAUSED_ATTRIBUTE, true)
	end
end

return SheepBeltHandler
