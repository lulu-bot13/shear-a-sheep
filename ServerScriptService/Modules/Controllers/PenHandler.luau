--!strict

--// Services
local pathfindingService = game:GetService("PathfindingService")
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Modules
local SheepHandler = require(script.Parent.SheepHandler)

--// Configurations
local INITIAL_SPAWN_DELAY_SECONDS = 5
local RESPAWN_DELAY_SECONDS = 3
local SHEEP_WALK_SPEED = 8
local SHEEP_Y_OFFSET = 3
-- WaypointSpacing = math.huge returns only the points where the route turns,
-- instead of one every 4 studs along straight sections.
local AGENT_PARAMS = { AgentRadius = 3, AgentHeight = 4, AgentCanJump = false, WaypointSpacing = math.huge }
local REACH_DISTANCE = 3 -- Studs from a path point at which the sheep heads for the next one.

type Pen = {
	plotName: string,
	waypointsFolder: Folder?, -- Parts named "1", "2", "3", ... walked in numeric order.
	groundPosition: Vector3, -- SheepPos at ground level; the last stop of the walk.
	sheepPosition: Vector3, -- SheepPos with the Y offset applied (final anchored pose).
	playerPosition: Vector3,
	occupiedSheepId: number?,
}

local pens: { Pen } = {}
local penBySheepId: { [number]: Pen } = {}
local started = false -- Set by Start once the initial spawn pass is queued; pens added later spawn themselves.

local PenHandler = {}

-- Looks up the part named "1", then "2", then "3", ... until one is missing.
local function getWaypointParts(folder: Folder?): { BasePart }
	local parts: { BasePart } = {}
	if not folder then
		return parts
	end

	local index = 1
	while true do
		local part = folder:FindFirstChild(tostring(index))
		if not part or not part:IsA("BasePart") then
			break
		end
		table.insert(parts, part)
		index += 1
	end

	return parts
end

local function walkSheepToPen(sheepModel: Model, waypointsFolder: Folder?, onArrived: () -> ())
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		onArrived()
		return
	end

	humanoid.WalkSpeed = SHEEP_WALK_SPEED

	-- Parts leading to the pen
	local targets: { Vector3 } = {}
	for _, part in getWaypointParts(waypointsFolder) do
		table.insert(targets, part.Position)
	end

	task.spawn(function()
		local path = pathfindingService:CreatePath(AGENT_PARAMS)
		local route: { Vector3 } = {}
		local legStart = rootPart.Position

		for _, target in targets do
			local offset = legStart - target
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= REACH_DISTANCE then
				continue
			end

			local success, err = pcall(function()
				path:ComputeAsync(legStart, target)
			end)

			if success and path.Status == Enum.PathStatus.Success then
				local points = path:GetWaypoints()
				for pointIndex = 2, #points do
					table.insert(route, points[pointIndex].Position)
				end
			else
				table.insert(route, target)
				warn(err)
			end

			legStart = target
		end

		for index, point in route do
			if not sheepModel.Parent then
				return
			end

			print(`Index: {index}`)

			humanoid:MoveTo(point)
			humanoid.MoveToFinished:Wait()

			if index == #route and sheepModel then
				print(`Sheep has arrived.`)
				onArrived()
				break
			end
		end
	end)
end

local function spawnIntoPen(pen: Pen)
	local firstWaypoint = getWaypointParts(pen.waypointsFolder)[1]
	local startPosition = if firstWaypoint then firstWaypoint.Position else pen.groundPosition
	local sheepModel, id = SheepHandler.spawnSheep(startPosition)
	if not sheepModel or not id then
		-- No valid sheep species could be spawned; try again shortly
		-- rather than leaving the pen empty forever.
		task.delay(RESPAWN_DELAY_SECONDS, function()
			spawnIntoPen(pen)
		end)
		return
	end

	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoidRootPart.Anchored = false

	pen.occupiedSheepId = id
	penBySheepId[id] = pen

	walkSheepToPen(sheepModel, pen.waypointsFolder, function()
		local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.PlatformStand = true
		end

		print(`Got callback positioning sheep`)

		local finalRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
		if finalRootPart then
			local lookTarget = Vector3.new(pen.playerPosition.X, pen.sheepPosition.Y, pen.playerPosition.Z)
			finalRootPart.CFrame = CFrame.lookAt(pen.sheepPosition + Vector3.new(0,SHEEP_Y_OFFSET, 0), lookTarget)
			finalRootPart.Anchored = true
		end

		SheepHandler.makeShearable(sheepModel, id)
	end)
end

--[[
    Called by ShearHandler once a pen's sheep has been fully sheared and
    removed. Frees the pen and queues the next arrival after a short delay.
]]
function PenHandler.onSheepRemoved(id: number)
	local pen = penBySheepId[id]
	if not pen then
		return
	end

	penBySheepId[id] = nil
	pen.occupiedSheepId = nil

	task.delay(RESPAWN_DELAY_SECONDS, function()
		spawnIntoPen(pen)
	end)
end

--[[
    Returns the pen a given (currently active) sheep id belongs to, or nil.
    Used by ShearHandler to know which PlayerPos to snap the shearing
    player to, and which marks to send the client for the camera shot.
]]
function PenHandler.getPenForSheep(id: number): Pen?
	return penBySheepId[id]
end

-- Validates a plot and turns it into a Pen; returns nil (with a warning where useful) if it isn't usable.
local function buildPen(plot: Instance): Pen?
	local baseFence = plot:FindFirstChild("Base_Fence")
	if not baseFence then
		return nil
	end

	local sheepPos = baseFence:FindFirstChild("SheepPos") :: BasePart?
	local playerPos = baseFence:FindFirstChild("PlayerPos") :: BasePart?
	if not sheepPos or not playerPos then
		warn(`Plot '{plot.Name}' is missing SheepPos/PlayerPos in its Base_Fence; skipping.`)
		return nil
	end

	-- A plot with no Waypoints folder just gets a direct walk to SheepPos.
	local waypointsFolder = plot:FindFirstChild("Waypoints")

	return {
		plotName = plot.Name,
		waypointsFolder = if waypointsFolder and waypointsFolder:IsA("Folder") then waypointsFolder else nil,
		groundPosition = sheepPos.Position,
		sheepPosition = sheepPos.Position,
		playerPosition = playerPos.Position,
		occupiedSheepId = nil,
	}
end

--[[
    Discovers every valid pen under Workspace.Base.Plots. Runs in the
    Setup phase (before any sheep spawn) so Start can immediately begin
    filling every discovered pen.
]]
function PenHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		local pen = buildPen(plot)
		if pen then
			table.insert(pens, pen)
		end
	end

	print(`PenHandler discovered {#pens} pen(s).`)
end

--[[
    Registers a plot created at runtime (e.g. a purchased pen) and starts
    filling it with sheep. Returns whether the plot was valid.
]]
function PenHandler.addPen(plot: Folder): boolean
	local pen = buildPen(plot)
	if not pen then
		return false
	end

	table.insert(pens, pen)
	print(`PenHandler added pen '{pen.plotName}' ({#pens} total).`)

	-- Before Start runs, its initial pass will spawn this pen with the rest.
	if started then
		spawnIntoPen(pen)
	end
	return true
end

function PenHandler.Start()
	-- Give the map time to load before the first sheep spawns and walks.
	task.delay(INITIAL_SPAWN_DELAY_SECONDS, function()
		started = true
		for _, pen in pens do
			if not pen.occupiedSheepId then
				spawnIntoPen(pen)
			end
		end
	end)
end

return PenHandler