--!strict

--[[
	One pen on a plot: its sheep, its walking route and its own data

	Location: ServerScriptService.Modules.Classes.Pen
]]--

--// Services
local pathfindingService = game:GetService("PathfindingService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local InventoryHandler = require(script.Parent.Parent.Controllers.InventoryHandler)
local EconomyData = require(script.Parent.Parent.Constants.EconomyData)

--// Animations
local sheepWalkingAnimation = replicatedStorage.Assets.Animations.SheepWalking

--// Configurations
local RESPAWN_DELAY_SECONDS = 3
local SHEEP_WALK_SPEED = 8
local SHEEP_Y_OFFSET = 2.2 -- how far above the pen's SheepPos the sheep's root sits while waiting to be sheared
local REACH_DISTANCE = 3
local LOOKAHEAD_DISTANCE = 4
local STEP_TIMEOUT_SECONDS = 6
local AGENT_PARAMS = { AgentRadius = 3, AgentHeight = 4, AgentCanJump = false, WaypointSpacing = math.huge }
local WORKER_SHEAR_INTERVAL_SECONDS = 1.5
local ASSUMED_ARRIVAL_SECONDS = 6 -- starting guess for how long a sheep takes to walk into the pen
local LOW_HEALTH_COLOR = Color3.fromRGB(230, 70, 70)
local FULL_HEALTH_COLOR = Color3.fromRGB(90, 210, 100)
local INCOME_TEXT_COLOR = Color3.fromRGB(110, 255, 130)

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
	shearingPlayer: Player?,
	spawnedAt: number,
	arrivalSeconds: number,
	healthBillboard: BillboardGui?,
	healthConnection: RBXScriptConnection?,
	workerLabel: TextLabel?,
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

--[[
	Moves the sheep to it's target pen

	@param pen Data for the pen that sheep is going to
	@param sheepModel The sheep that will be getting moved

	@return Sheep has arrived properly
]]
local function walkSheep(pen: Pen, sheepModel: Model): boolean
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid") :: Humanoid
	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart then
		return true
	end
	local animator = humanoid:FindFirstChild("Animator") :: Animator

	local walkAnimationTrack = animator and animator:LoadAnimation(sheepWalkingAnimation)

	humanoid.WalkSpeed = SHEEP_WALK_SPEED

	local route = computeRoute(rootPart.Position, pen.waypoints)

	for index, point in ipairs(route) do
		if not sheepModel.Parent or pen.destroyed then
			return false
		end

		humanoid:MoveTo(point)
		humanoid.MoveToFinished:Wait()

		if index == #route then
			walkAnimationTrack:Stop(0.5)
			break
		else
			if not walkAnimationTrack.IsPlaying then
				walkAnimationTrack:Play()
			end
		end
	end

	return sheepModel.Parent ~= nil and not pen.destroyed
end

-- 1500 -> "$1.5K", 30 -> "$30".
local function formatMoney(amount: number): string
	if amount >= 1e6 then
		return string.format("$%.1fM", amount / 1e6)
	elseif amount >= 1e3 then
		return string.format("$%.1fK", amount / 1e3)
	end
	return "$" .. tostring(math.floor(amount + 0.5))
end

--[[
	Estimated money per minute this pen's worker earns, from the sheep odds at the pen's
	current level: expected wool per sheep divided by the expected time one sheep takes
	(worker shearing time + respawn delay + the pen's measured walk-in time), times the sell price.
]]--
function Pen.getEstimatedMoneyPerMinute(self: Pen): number
	local chances = self.data.chances
	local expectedWool = 0
	local expectedCycleSeconds = 0

	for sheepName, data in SheepData do
		if type(data) == "table" and type(data.chance) == "number" then
			local weight = (chances and chances[sheepName]) or data.chance
			local shearSeconds = math.ceil(data.ShearHealth / ShearData.Default.damage) * WORKER_SHEAR_INTERVAL_SECONDS

			expectedWool += weight * data.WoolAmount
			expectedCycleSeconds += weight * (shearSeconds + RESPAWN_DELAY_SECONDS + self.arrivalSeconds)
		end
	end

	if expectedCycleSeconds <= 0 then
		return 0
	end

	return (expectedWool / expectedCycleSeconds) * 60 * EconomyData.WOOL_SELL_PRICE
end

-- Adds the "Est. $X/min" label above a freshly hired worker.
function Pen._createWorkerLabel(self: Pen, worker: Model)
	local anchor = worker:FindFirstChild("Head") or worker:FindFirstChild("HumanoidRootPart")
	if not anchor or not anchor:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WorkerIncome"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(170, 34)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 70
	billboard.Parent = worker

	local label = Instance.new("TextLabel")
	label.Name = "IncomeLabel"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 26
	label.TextColor3 = INCOME_TEXT_COLOR
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	self.workerLabel = label
	self:_refreshWorkerLabel()
end

-- Rewrites the worker's income label (odds change on upgrade; walk-in time changes as sheep arrive).
function Pen._refreshWorkerLabel(self: Pen)
	local label = self.workerLabel
	if label and label.Parent then
		label.Text = `Est. {formatMoney(self:getEstimatedMoneyPerMinute())}/min`
	end
end

-- Builds the small health bar that floats above the sheep in a pen with a worker.
local function createHealthBillboard(pen: Pen): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SheepHealthBar"
	billboard.Size = UDim2.fromOffset(130, 20)
	billboard.StudsOffset = Vector3.new(0, 4.6, 0)
	billboard.MaxDistance = 60
	billboard.Enabled = false
	billboard.Parent = pen.model

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
	track.BorderSizePixel = 0
	track.Parent = billboard

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local trackStroke = Instance.new("UIStroke")
	trackStroke.Thickness = 2
	trackStroke.Color = Color3.new(0, 0, 0)
	trackStroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = FULL_HEALTH_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.SourceSansBold
	text.TextSize = 15
	text.TextColor3 = Color3.new(1, 1, 1)
	text.ZIndex = 2
	text.Parent = track

	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Color = Color3.new(0, 0, 0)
	textStroke.Parent = text

	pen.healthBillboard = billboard
	table.insert(pen.extras, billboard)
	return billboard
end

-- Shows/updates the sheep health bar while the pen has a worker and a sheep waiting; hides it otherwise.
function Pen._updateHealthBillboard(self: Pen)
	local sheep = if self.occupiedSheepId then SheepHandler.getSheep(self.occupiedSheepId) else nil
	local root = if sheep then sheep:FindFirstChild("HumanoidRootPart") else nil
	local shouldShow = self.data.automated and self.seated and not self.destroyed and root ~= nil and root:IsA("BasePart")

	if not shouldShow then
		if self.healthBillboard then
			self.healthBillboard.Enabled = false
		end
		return
	end

	local billboard = self.healthBillboard or createHealthBillboard(self)
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		billboard.Enabled = false
		return
	end

	local ratio = math.clamp(health / maxHealth, 0, 1)
	local track = billboard:FindFirstChild("Track") :: Frame
	local fill = track:FindFirstChild("Fill") :: Frame
	local text = track:FindFirstChild("Text") :: TextLabel
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = LOW_HEALTH_COLOR:Lerp(FULL_HEALTH_COLOR, ratio)
	text.Text = `{math.ceil(health)} / {maxHealth}`

	billboard.Adornee = root
	billboard.Enabled = true
end

-- Freezes the sheep on the pen's SheepPos facing the player, ready to be sheared from the pen menu.
local function seatSheep(pen: Pen, sheepModel: Model, id: number)
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.PlatformStand = true
	end

	local rootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local lookTarget = Vector3.new(pen.playerPosition.X, pen.sheepPosition.Y, pen.playerPosition.Z)
		rootPart.CFrame = CFrame.lookAt(pen.sheepPosition, lookTarget) * CFrame.new(0, SHEEP_Y_OFFSET, 0)
		rootPart.Anchored = true
	end

	pen.seated = true

	-- Smoothed measure of how long sheep take to walk in (feeds the worker's income estimate).
	pen.arrivalSeconds = pen.arrivalSeconds * 0.7 + (os.clock() - pen.spawnedAt) * 0.3

	if pen.healthConnection then
		pen.healthConnection:Disconnect()
	end
	pen.healthConnection = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		pen:_updateHealthBillboard()
	end)
	pen:_updateHealthBillboard()
	pen:_refreshWorkerLabel()
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
		shearingPlayer = nil,
		spawnedAt = 0,
		arrivalSeconds = ASSUMED_ARRIVAL_SECONDS,
		healthBillboard = nil,
		healthConnection = nil,
		workerLabel = nil,
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
	self:_refreshWorkerLabel()
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
		self:_createWorkerLabel(worker)
	end

	self:_updateHealthBillboard()

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

	-- The worker steps aside while the owner is shearing by hand.
	if self.shearingPlayer then
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
	self.spawnedAt = os.clock()
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

	if self.healthConnection then
		self.healthConnection:Disconnect()
		self.healthConnection = nil
	end
	self:_updateHealthBillboard()

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

	if self.healthConnection then
		self.healthConnection:Disconnect()
		self.healthConnection = nil
	end
	self.healthBillboard = nil
	self.workerLabel = nil

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
