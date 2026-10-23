--!strict

--[[
	Walks every sheep to random spots inside its plot's SheepArea, pausing between walks (tuned in FarmData.Wander).
	Some pauses are spent grazing: the sheep's "Grazing" attribute is true while it should have its head down,
	and SheepGrazeClient animates it. Sheep being sheared stand still (head up) until ShearHoldSeconds pass without a snip.

	Location: ServerScriptService.Modules.Controllers.SheepWanderHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local SheepHandler = require(script.Parent.SheepHandler)

--// Configs
local WANDER = FarmData.Wander
local RAYCAST_HEIGHT = 50 -- how far above/below the area the ground is searched for
local GRAZING_ATTRIBUTE = "Grazing"
local GRAZE_MAX_SPEED = 0.5 -- studs/s; a sheep still sliding to a stop waits before grazing

--// State
local nextMoveAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local grazeStart: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local grazeEnd: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local random = Random.new()

local SheepWanderHandler = {}

--// SheepArea --------------------------------------------------------------------------

-- The SheepArea's box (a part, or the bounding box of a model), or nil if the plot has none.
local function getAreaBox(plot: Instance): (CFrame?, Vector3?)
	local area = plot:FindFirstChild(FarmData.SheepAreaName)
	if area and area:IsA("BasePart") then
		return area.CFrame, area.Size
	elseif area and area:IsA("Model") then
		return area:GetBoundingBox()
	end
	return nil, nil
end

-- Keeps a point (in the area's local space) inside the box, EdgePadding away from its sides.
local function clampToArea(localPoint: Vector3, size: Vector3): Vector3
	local halfX = math.max(size.X / 2 - WANDER.EdgePadding, 0)
	local halfZ = math.max(size.Z / 2 - WANDER.EdgePadding, 0)
	return Vector3.new(math.clamp(localPoint.X, -halfX, halfX), localPoint.Y, math.clamp(localPoint.Z, -halfZ, halfZ))
end

-- The ground under a point, ignoring sheep, players and non-collidable zone parts.
local function findGround(plot: Instance, point: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local ignore: { Instance } = {}
	local sheepFolder = plot:FindFirstChild("Sheeps")
	if sheepFolder then
		table.insert(ignore, sheepFolder)
	end
	for _, player in players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore

	local origin = point + Vector3.new(0, RAYCAST_HEIGHT, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_HEIGHT * 2, 0), params)
	return if result then result.Position else nil
end

-- A random spot on the ground of the plot's SheepArea to drop a new sheep at.
function SheepWanderHandler.getSpawnPosition(plot: Instance): Vector3?
	local boxCFrame, size = getAreaBox(plot)
	if not boxCFrame or not size then
		warn(`SheepWanderHandler: {plot.Name} has no {FarmData.SheepAreaName} part or model.`)
		return nil
	end

	local localPoint = clampToArea(Vector3.new(random:NextNumber(-size.X, size.X) / 2, 0, random:NextNumber(-size.Z, size.Z) / 2), size)
	local point = boxCFrame:PointToWorldSpace(localPoint)
	local ground = findGround(plot, point) or point
	return ground + Vector3.new(0, FarmData.SpawnDropHeight, 0)
end

--// Grazing ---------------------------------------------------------------------------

-- Only writes on a change, so the attribute replicates once per graze rather than every tick.
local function setGrazing(sheep: Model, grazing: boolean)
	if (sheep:GetAttribute(GRAZING_ATTRIBUTE) == true) ~= grazing then
		sheep:SetAttribute(GRAZING_ATTRIBUTE, grazing)
	end
end

local function cancelGraze(sheep: Model)
	grazeStart[sheep] = nil
	grazeEnd[sheep] = nil
	setGrazing(sheep, false)
end

--// Walking ---------------------------------------------------------------------------

-- The plot a sheep belongs to (sheep live in Plot.Sheeps).
local function getPlot(sheep: Model): Instance?
	local folder = sheep.Parent
	return if folder then folder.Parent else nil
end

local function startWalk(sheep: Model, humanoid: Humanoid, root: BasePart, now: number)
	local plot = getPlot(sheep)
	local boxCFrame, size
	if plot then
		boxCFrame, size = getAreaBox(plot)
	end
	if not boxCFrame or not size then
		nextMoveAt[sheep] = now + WANDER.MaxIdleSeconds
		return
	end

	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(WANDER.MinDistance, WANDER.MaxDistance)
	local localStart = boxCFrame:PointToObjectSpace(root.Position)
	local localTarget = clampToArea(localStart + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance, size)
	local target = boxCFrame:PointToWorldSpace(localTarget)

	local speed = random:NextNumber(WANDER.MinWalkSpeed, WANDER.MaxWalkSpeed)
	cancelGraze(sheep)
	humanoid.WalkSpeed = speed
	humanoid:MoveTo(target)

	local travelSeconds = (target - root.Position).Magnitude / math.max(speed, 0.1)
	local arriveAt = now + travelSeconds
	local idleSeconds = random:NextNumber(WANDER.MinIdleSeconds, WANDER.MaxIdleSeconds)

	-- Some walks end with a graze; the head comes back up a moment before the next walk.
	if random:NextNumber() < WANDER.GrazeChance then
		local start = arriveAt + WANDER.GrazeSettleSeconds
		local finish = start + random:NextNumber(WANDER.MinGrazeSeconds, WANDER.MaxGrazeSeconds)
		grazeStart[sheep] = start
		grazeEnd[sheep] = finish
		nextMoveAt[sheep] = finish + idleSeconds
	else
		nextMoveAt[sheep] = arriveAt + idleSeconds
	end
end

-- True while the sheep is inside its graze window and has actually stopped walking.
local function shouldGraze(sheep: Model, root: BasePart, now: number): boolean
	local start, finish = grazeStart[sheep], grazeEnd[sheep]
	if not start or not finish or now < start or now >= finish then
		return false
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude < GRAZE_MAX_SPEED
end

local function updateSheep(sheep: Model, now: number)
	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	local root = sheep:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or root.Anchored then
		return
	end

	-- A new sheep waits a moment before its first walk.
	local due = nextMoveAt[sheep]
	if not due then
		cancelGraze(sheep) -- a pooled model may still carry an old graze window
		nextMoveAt[sheep] = now + random:NextNumber(0, WANDER.MaxIdleSeconds)
	elseif now >= due then
		startWalk(sheep, humanoid, root, now)
	else
		setGrazing(sheep, shouldGraze(sheep, root, now))
	end
end

-- Stops the sheep where it stands; each call pushes its next walk back by ShearHoldSeconds.
function SheepWanderHandler.holdSheep(sheep: Model)
	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	local root = sheep:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	humanoid:MoveTo(root.Position)
	cancelGraze(sheep) -- head up while being sheared
	nextMoveAt[sheep] = os.clock() + WANDER.ShearHoldSeconds
end

function SheepWanderHandler.Start()
	task.spawn(function()
		while true do
			task.wait(WANDER.TickSeconds)
			local now = os.clock()
			for _, sheep in SheepHandler.getAllSheep() do
				updateSheep(sheep, now)
			end
		end
	end)
end

return SheepWanderHandler
