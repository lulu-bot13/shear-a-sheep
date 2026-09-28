--!strict

--[[
	One pen on a plot: its sheep, its walking route and its own data

	Location: ServerScriptService.Modules.Classes.Pen
]]--

--// Services
local pathfindingService = game:GetService("PathfindingService")
local runService = game:GetService("RunService")

--// Modules
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)
local SheepAnimator = require(script.Parent.Parent.Utils.SheepAnimator)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local InventoryHandler = require(script.Parent.Parent.Controllers.InventoryHandler)

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Configurations
local RESPAWN_DELAY_SECONDS = 3
local SHEEP_WALK_SPEED = 8
local SHEEP_Y_OFFSET = 1
local REACH_DISTANCE = 3
local LOOKAHEAD_DISTANCE = 4
local STEP_TIMEOUT_SECONDS = 6
local AGENT_PARAMS = { AgentRadius = 3, AgentHeight = 4, AgentCanJump = false, WaypointSpacing = math.huge }
local WORKER_SHEAR_INTERVAL_SECONDS = 1.5

export type PenData = {
	chances: { [string]: number }?,
	money: number,
	automated: boolean,
}

type PenFields = {
	id: number,
	owner: Player,
	model: Model,
	waypoints: { BasePart },
	extras: { Instance },
	sheepPosition: Vector3,
	playerPosition: Vector3,
	occupiedSheepId: number?,
	active: boolean,
	destroyed: boolean,
	seated: boolean,
	level: number,
	workerModel: Model?,
	data: PenData,
}

local Pen = {}
Pen.__index = Pen

export type Pen = typeof(setmetatable({} :: PenFields, Pen))

local penBySheepId: { [number]: Pen } = {}

-- Pathfinds between each waypoint in order and returns the turning points of the whole route.
local function computeRoute(startPosition: Vector3, waypoints: { BasePart }): { Vector3 }
	local path = pathfindingService:CreatePath(AGENT_PARAMS)
	local route: { Vector3 } = {}
	local legStart = startPosition

	for _, waypoint in waypoints do
		local target = waypoint.Position
		local offset = legStart - target
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= REACH_DISTANCE then
			continue
		end

		local success = pcall(function()
			path:ComputeAsync(legStart, target)
		end)

		if success and path.Status == Enum.PathStatus.Success then
			local points = path:GetWaypoints()
			for index = 2, #points do
				table.insert(route, points[index].Position)
			end
		else
			-- Fall back to a straight walk so the sheep never gets stuck without a route.
			table.insert(route, target)
			warn(`Pen: pathfinding to waypoint '{waypoint.Name}' failed.`)
		end

		legStart = target
	end

	return route
end

-- Returns once the sheep is close to a point, so the next MoveTo can start before it has to brake.
local function waitUntilNear(rootPart: BasePart, point: Vector3)
	local startTime = os.clock()

	while rootPart.Parent and os.clock() - startTime < STEP_TIMEOUT_SECONDS do
		local offset = rootPart.Position - point
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= LOOKAHEAD_DISTANCE then
			return
		end

		runService.Heartbeat:Wait()
	end
end

-- Walks the sheep along the pen's route; returns false if the sheep or pen disappeared on the way.
local function walkSheep(pen: Pen, sheepModel: Model): boolean
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		return true
	end

	humanoid.WalkSpeed = SHEEP_WALK_SPEED
	SheepAnimator.setWalking(sheepModel, true)

	local route = computeRoute(rootPart.Position, pen.waypoints)

	for index, point in ipairs(route) do
		if not sheepModel.Parent or pen.destroyed then
			return false
		end

		humanoid:MoveTo(point)

		if index == #route then
			humanoid.MoveToFinished:Wait()
		else
			waitUntilNear(rootPart, point)
		end
	end

	return sheepModel.Parent ~= nil and not pen.destroyed
end

-- Freezes the sheep on the pen's SheepPos facing the player, then lets players shear it.
local function seatSheep(pen: Pen, sheepModel: Model, id: number)
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.PlatformStand = true
	end

	SheepAnimator.setWalking(sheepModel, false)

	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local lookTarget = Vector3.new(pen.playerPosition.X, pen.sheepPosition.Y, pen.playerPosition.Z)
		rootPart.CFrame = CFrame.lookAt(pen.sheepPosition, lookTarget) * CFrame.new(0, SHEEP_Y_OFFSET, 0)
		rootPart.Anchored = true
	end

	SheepHandler.makeShearable(sheepModel, id)
	pen.seated = true
end

-- Returns the pen a currently active sheep belongs to, or nil.
function Pen.getBySheepId(id: number): Pen?
	return penBySheepId[id]
end

-- Builds a pen from its model; returns nil if the model has no SheepPos/PlayerPos.
function Pen.new(owner: Player, id: number, model: Model, waypoints: { BasePart }, extras: { Instance }): Pen?
	local sheepPos = model:FindFirstChild("SheepPos") :: BasePart?
	local playerPos = model:FindFirstChild("PlayerPos") :: BasePart?
	if not sheepPos or not playerPos then
		warn(`Pen '{model.Name}' is missing SheepPos/PlayerPos.`)
		return nil
	end

	return setmetatable({
		id = id,
		owner = owner,
		model = model,
		waypoints = waypoints,
		extras = extras,
		sheepPosition = sheepPos.Position,
		playerPosition = playerPos.Position,
		occupiedSheepId = nil,
		active = false,
		destroyed = false,
		seated = false,
		level = 1,
		workerModel = nil,
		data = { money = 0, automated = false },
	}, Pen)
end

-- Current upgrade level (1..SheepData.MaxPenLevel). Higher levels bias spawns toward rarer sheep.
function Pen.getLevel(self: Pen): number
	return self.level
end

-- Bumps the pen to the next level and rebiases its spawn chances; false if already maxed.
function Pen.upgrade(self: Pen): boolean
	if self.destroyed or self.level >= SheepData.MaxPenLevel then
		return false
	end

	self.level += 1
	self.data.chances = SheepData.buildChancesForLevel(self.level)
	return true
end

-- Hires an auto-shearing worker for this pen; false if one is already hired.
function Pen.hireWorker(self: Pen): boolean
	if self.destroyed or self.data.automated then
		return false
	end

	self.data.automated = true

	local npcs = replicatedStorage.Assets:FindFirstChild("Npcs")
	local template = npcs and npcs:FindFirstChild("Worker")
	if template and self.model.Parent then
		local worker = template:Clone()
		worker.Name = `Worker_{self.id}`
		local lookTarget = Vector3.new(self.sheepPosition.X, self.playerPosition.Y, self.sheepPosition.Z)
		worker:PivotTo(CFrame.lookAt(self.playerPosition, lookTarget))
		worker.Parent = self.model
		table.insert(self.extras, worker)
		self.workerModel = worker
	end

	task.spawn(function()
		while self.data.automated and not self.destroyed do
			task.wait(WORKER_SHEAR_INTERVAL_SECONDS)
			if self.data.automated and not self.destroyed then
				self:_workerShearTick()
			end
		end
	end)

	return true
end

-- Applies one tick of automatic shearing to whatever sheep is currently seated in the pen.
function Pen._workerShearTick(self: Pen)
	local id = self.occupiedSheepId
	if not id or not self.seated then
		return
	end

	local sheep = SheepHandler.getSheep(id)
	if not sheep then
		return
	end

	local current = sheep:GetAttribute("ShearHealth") :: number
	if type(current) ~= "number" then
		return
	end

	local newHealth = math.max(current - ShearData.Default.damage, 0)
	sheep:SetAttribute("ShearHealth", newHealth)

	if newHealth <= 0 then
		local woolAmount = sheep:GetAttribute("WoolAmount") :: number
		if self.owner and self.owner.Parent then
			InventoryHandler.addItem(self.owner, "Wool", woolAmount)
		end
		SheepHandler.removeSheep(id)
		self:releaseSheep()
	end
end

-- Spawns a sheep at the start of the route and walks it into the pen; does nothing if the pen is busy.
function Pen.spawnSheep(self: Pen)
	if self.destroyed or not self.active or self.occupiedSheepId then
		return
	end

	local firstWaypoint = self.waypoints[1]
	local startPosition = if firstWaypoint then firstWaypoint.Position else self.sheepPosition
	local sheepModel, id = SheepHandler.spawnSheep(startPosition, self.data.chances)
	if not sheepModel or not id then
		task.delay(RESPAWN_DELAY_SECONDS, function()
			self:spawnSheep()
		end)
		return
	end

	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart
	rootPart.Anchored = false

	self.occupiedSheepId = id
	self.seated = false
	penBySheepId[id] = self

	task.spawn(function()
		if walkSheep(self, sheepModel) then
			seatSheep(self, sheepModel, id)
		end
	end)
end

-- Frees the pen once its sheep is gone and queues the next arrival.
function Pen.releaseSheep(self: Pen)
	local id = self.occupiedSheepId
	if not id then
		return
	end

	penBySheepId[id] = nil
	self.occupiedSheepId = nil
	self.seated = false

	task.delay(RESPAWN_DELAY_SECONDS, function()
		self:spawnSheep()
	end)
end

-- Allows the pen to receive sheep and fills it straight away.
function Pen.start(self: Pen)
	self.active = true
	self:spawnSheep()
end

-- Removes the pen's sheep and every instance that was created for it.
function Pen.destroy(self: Pen)
	self.destroyed = true
	self.data.automated = false

	local id = self.occupiedSheepId
	if id then
		penBySheepId[id] = nil
		self.occupiedSheepId = nil
		SheepHandler.removeSheep(id)
	end

	for _, instance in self.extras do
		instance:Destroy()
	end
	table.clear(self.extras)
end

return Pen
