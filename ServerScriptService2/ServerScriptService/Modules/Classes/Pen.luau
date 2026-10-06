--!strict

--[[
	One pen on a plot: its sheep, its walking route and its own data

	Location: ServerScriptService.Modules.Classes.Pen
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local pathfindingService = game:GetService("PathfindingService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local InventoryHandler = require(script.Parent.Parent.Controllers.InventoryHandler)
local EconomyData = require(script.Parent.Parent.Constants.EconomyData)

--// Animations
local sheepWalkingAnimation = replicatedStorage.Assets.Animations.SheepWalking
local shearRigAnimation = replicatedStorage.Assets.Animations.ShearRig
local shearToolAnimation = replicatedStorage.Assets.Animations.ShearTool

--// Configurations
local RESPAWN_DELAY_SECONDS = 3
local SHEEP_WALK_SPEED = 8
local SHEEP_Y_OFFSET = 1.45 -- how far above the pen's SheepPos the sheep's root sits while waiting to be sheared (puts its hooves on the grass)
local REACH_DISTANCE = 3
local AGENT_PARAMS = { AgentRadius = 3, AgentHeight = 4, AgentCanJump = false, WaypointSpacing = math.huge }
local WORKER_SHEAR_INTERVAL_SECONDS = 1.5
local WORKER_FORWARD_OFFSET = 2 -- studs the worker stands in front of PlayerPos, towards the sheep
local DEFAULT_SHEAR_ID = "DefaultShear" -- the worker's shears when the owner's own can't be found
local WORKER_FLOOR_RAY_HEIGHT = 6 -- ray starts this far above PlayerPos when looking for the ground under the worker
local WORKER_FLOOR_RAY_LENGTH = 40
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
	penModel: Model, -- the pen's model in the plot; swapped out by replaceModel
	penType: string, -- template name (ReplicatedStorage.Assets.Models.Pens) that penModel was built from
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
	baseLuck: number, -- from rebirths (1 = none); boosts rare sheep on top of the upgrade level
	workerModel: Model?,
	workerRigTrack: AnimationTrack?, -- the worker's swing; loaded once and replayed on every hit
	workerToolTrack: AnimationTrack?,
	workerToken: number, -- bumped on every hire and removal, so a stale shear loop or avatar load can tell it is out of date
	data: PenData,
}

local Pen = {}
Pen.__index = Pen

Pen.DEFAULT_PEN_TYPE = "Base_Pen"

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

	for _, point in ipairs(route) do
		if not sheepModel.Parent or pen.destroyed then
			if walkAnimationTrack then
				walkAnimationTrack:Stop(0.5)
			end
			return false
		end

		-- The animation must start BEFORE the sheep starts moving toward a point; starting it after
		-- MoveToFinished only kicks in from the second waypoint on.
		if walkAnimationTrack and not walkAnimationTrack.IsPlaying then
			walkAnimationTrack:Play()
		end

		humanoid:MoveTo(point)
		humanoid.MoveToFinished:Wait()
	end

	if walkAnimationTrack then
		walkAnimationTrack:Stop(0.5)
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
	billboard.Parent = pen.penModel

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

	-- No sheep in the pen (just released, or not arrived yet): nothing to show.
	if not sheep then
		if self.healthBillboard then
			self.healthBillboard.Enabled = false
		end
		return
	end

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

-- The sheep's spot facing the player, or turned flank-on (head to the camera's right) like when a player shears it.
local function getSheepSeatCFrame(pen: Pen, sideOn: boolean): CFrame
	local flat = Vector3.new(pen.playerPosition.X - pen.sheepPosition.X, 0, pen.playerPosition.Z - pen.sheepPosition.Z)
	local towardPlayer = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
	local facing = if sideOn then towardPlayer:Cross(Vector3.yAxis) else towardPlayer
	return CFrame.lookAt(pen.sheepPosition, pen.sheepPosition + facing)
end

-- Snaps the pen's seated sheep (no tween) to face the player or flank-on.
local function turnSeatedSheep(pen: Pen, sideOn: boolean)
	local id = pen.occupiedSheepId
	local sheep = if id and pen.seated then SheepHandler.getSheep(id) else nil
	local rootPart = if sheep then sheep:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if rootPart then
		rootPart.CFrame = getSheepSeatCFrame(pen, sideOn) * CFrame.new(0, SHEEP_Y_OFFSET, 0)
	end
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
		rootPart.CFrame = getSheepSeatCFrame(pen, pen.data.automated) * CFrame.new(0, SHEEP_Y_OFFSET, 0)
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

-- Builds a pen from its model; returns nil if the model has no SheepPos/PlayerPos. penType defaults to the base pen.
function Pen.new(owner: Player, id: number, model: Model, waypoints: { BasePart }, extras: { Instance }, penType: string?): Pen?
	local sheepPos = model:FindFirstChild("SheepPos") :: BasePart?
	local playerPos = model:FindFirstChild("PlayerPos") :: BasePart?
	if not sheepPos or not playerPos then
		warn(`Pen '{model.Name}' is missing SheepPos/PlayerPos.`)
		return nil
	end

	return setmetatable({
		id = id,
		owner = owner,
		penModel = model,
		penType = penType or Pen.DEFAULT_PEN_TYPE,
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
		baseLuck = 1,
		workerModel = nil,
		workerRigTrack = nil,
		workerToolTrack = nil,
		workerToken = 0,
		data = { money = 0, automated = false },
	}, Pen)
end

--[[
	Swaps the pen's model for a clone of `template` (an entry of ReplicatedStorage.Assets.Models.Pens).
	The new model takes the old one's name and place, and whatever the pen attached to the old model
	(worker, health bar) moves across before the old one is destroyed. Returns false, leaving the pen
	untouched, if the template can't be used.
]]--
function Pen.replaceModel(self: Pen, template: Model, penType: string): boolean
	if self.destroyed then
		return false
	end

	local oldModel = self.penModel
	local newModel = template:Clone()
	local newSheepPos = newModel:FindFirstChild("SheepPos")
	local newPlayerPos = newModel:FindFirstChild("PlayerPos")
	if not newSheepPos or not newSheepPos:IsA("BasePart") or not newPlayerPos or not newPlayerPos:IsA("BasePart") then
		warn(`Pen: template '{template.Name}' is missing SheepPos/PlayerPos.`)
		newModel:Destroy()
		return false
	end

	newModel.Name = oldModel.Name
	newModel:PivotTo(oldModel:GetPivot())

	-- Templates share one layout, so these are normally zero; they keep the sheep and worker on their spots if not.
	local sheepShift = newSheepPos.Position - self.sheepPosition
	local playerShift = newPlayerPos.Position - self.playerPosition

	for _, instance in self.extras do
		if instance ~= oldModel and instance:IsDescendantOf(oldModel) then
			instance.Parent = newModel
		end
	end

	-- Pens bought later own their model (it is destroyed with them); the base pen's model is not in extras.
	local extraIndex = table.find(self.extras, oldModel)
	if extraIndex then
		self.extras[extraIndex] = newModel
	end

	newModel.Parent = oldModel.Parent
	oldModel:Destroy()

	self.penModel = newModel
	self.penType = penType
	self.sheepPosition = newSheepPos.Position
	self.playerPosition = newPlayerPos.Position

	if sheepShift.Magnitude > 0.01 and self.seated and self.occupiedSheepId then
		local sheep = SheepHandler.getSheep(self.occupiedSheepId)
		local root = if sheep then sheep:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			root.CFrame += sheepShift
		end
	end

	local worker = self.workerModel
	if worker and playerShift.Magnitude > 0.01 then
		worker:PivotTo(worker:GetPivot() + playerShift)
	end

	return true
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
	self.data.chances = SheepData.buildChancesForLevel(self.level, self.baseLuck)
	self:_refreshWorkerLabel()
	return true
end

-- Sets the rebirth luck and reworks the sheep odds with it (the next sheep to spawn uses them).
function Pen.setBaseLuck(self: Pen, luck: number)
	self.baseLuck = luck
	self.data.chances = SheepData.buildChancesForLevel(self.level, luck)
	self:_refreshWorkerLabel()
end

--[[
	Places the pen's worker: a clone of ReplicatedStorage.Assets.Npcs.PlayerWorker dressed in the owner's avatar
	(their HumanoidDescription), standing on the ground at PlayerPos and facing the sheep. `token` is the hire
	this worker belongs to; if the worker was removed (or removed and hired again) while the avatar loaded,
	nothing is placed.
]]--
function Pen._spawnWorker(self: Pen, token: number)
	local npcs = replicatedStorage.Assets:FindFirstChild("Npcs")
	local template = npcs and npcs:FindFirstChild("PlayerWorker")
	if not template then
		warn("Pen: ReplicatedStorage.Assets.Npcs.PlayerWorker is missing, no worker was placed.")
		return
	end

	local worker = template:Clone() :: Model
	worker.Name = `Worker_{self.id}`

	for _, descendant in worker:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end

	local workerRoot = worker:FindFirstChild("HumanoidRootPart") :: BasePart?
	if workerRoot then
		workerRoot.Anchored = true
	end

	local humanoid = worker:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- A description can only be applied to a rig that is in the world, so it goes in (anchored) first.
	worker.Parent = self.penModel

	if humanoid then
		local success, err = pcall(function()
			local description = players:GetHumanoidDescriptionFromUserId(self.owner.UserId)
			humanoid:ApplyDescription(description)
		end)
		if not success then
			warn(`Pen: could not dress the worker as {self.owner.Name}: {err}`)
		end
	end

	-- The pen may have been sold / the worker removed while the avatar was loading.
	if self.destroyed or self.workerToken ~= token or not self.penModel.Parent then
		worker:Destroy()
		return
	end

	-- Stand on the ground under PlayerPos rather than at PlayerPos itself (that part floats above the grass).
	local ignore: { Instance } = collectionService:GetTagged("Sheep")
	table.insert(ignore, worker)
	for _, name in { "SheepPos", "PlayerPos" } do
		local marker = self.penModel:FindFirstChild(name)
		if marker then
			table.insert(ignore, marker)
		end
	end
	for _, otherPlayer in players:GetPlayers() do
		if otherPlayer.Character then
			table.insert(ignore, otherPlayer.Character)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	rayParams.RespectCanCollide = true

	-- The worker stands a little in front of PlayerPos (towards the sheep), never more than halfway there.
	local toSheep = Vector3.new(self.sheepPosition.X - self.playerPosition.X, 0, self.sheepPosition.Z - self.playerPosition.Z)
	local forward = if toSheep.Magnitude > 0.01 then toSheep.Unit * math.min(WORKER_FORWARD_OFFSET, toSheep.Magnitude * 0.5) else Vector3.zero
	local standPosition = self.playerPosition + forward

	local hit = workspace:Raycast(standPosition + Vector3.new(0, WORKER_FLOOR_RAY_HEIGHT, 0), Vector3.new(0, -WORKER_FLOOR_RAY_LENGTH, 0), rayParams)
	local floorY = if hit then hit.Position.Y else self.playerPosition.Y

	local lookTarget = Vector3.new(self.sheepPosition.X, floorY, self.sheepPosition.Z)
	worker:PivotTo(CFrame.lookAt(Vector3.new(standPosition.X, floorY, standPosition.Z), lookTarget))

	-- The pivot is the root part's centre (chest height), so lift the whole rig until its lowest point rests on the floor.
	local boundsCFrame, boundsSize = worker:GetBoundingBox()
	local lift = floorY - (boundsCFrame.Position.Y - boundsSize.Y / 2)
	worker:PivotTo(worker:GetPivot() + Vector3.new(0, lift, 0))

	table.insert(self.extras, worker)
	self.workerModel = worker
	self:_createWorkerLabel(worker)
	self:_equipWorkerShears(worker)
end

-- Puts a copy of the owner's shears in the worker's hand (their Tool animation is what the swing plays on).
function Pen._equipWorkerShears(self: Pen, worker: Model)
	local humanoid = worker:FindFirstChildOfClass("Humanoid")
	local shears = replicatedStorage.Assets:FindFirstChild("Shears")
	if not humanoid or not shears or worker:FindFirstChildOfClass("Tool") then
		return
	end

	local shearId = self.owner:GetAttribute("ShearId")
	local template = (if type(shearId) == "string" then shears:FindFirstChild(shearId) else nil) or shears:FindFirstChild(DEFAULT_SHEAR_ID)
	if template and template:IsA("Tool") then
		humanoid:EquipTool(template:Clone())
	end
end

-- Plays the shearing swing on the worker (and on their shears), like the player's own.
function Pen._playWorkerSwing(self: Pen)
	local worker = self.workerModel
	local humanoid = if worker then worker:FindFirstChildOfClass("Humanoid") else nil
	if not worker or not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local rigTrack = self.workerRigTrack
	if not rigTrack then
		rigTrack = animator:LoadAnimation(shearRigAnimation)
		rigTrack.Priority = Enum.AnimationPriority.Action
		rigTrack.Looped = false
		self.workerRigTrack = rigTrack
	end
	if not rigTrack.IsPlaying then
		rigTrack:Play()
	end

	local tool = worker:FindFirstChildOfClass("Tool")
	local toolController = if tool then tool:FindFirstChild("AnimationController") else nil
	local toolAnimator = if toolController then toolController:FindFirstChildOfClass("Animator") else nil
	if toolAnimator then
		local toolTrack = self.workerToolTrack
		if not toolTrack then
			toolTrack = toolAnimator:LoadAnimation(shearToolAnimation)
			toolTrack.Priority = Enum.AnimationPriority.Action
			toolTrack.Looped = false
			self.workerToolTrack = toolTrack
		end
		if not toolTrack.IsPlaying then
			toolTrack:Play()
		end
	end
end

-- Hires an auto-shearing worker for this pen; false if one is already hired.
function Pen.hireWorker(self: Pen): boolean
	if self.destroyed or self.data.automated then
		return false
	end

	self.data.automated = true
	self.workerToken += 1
	local token = self.workerToken

	turnSeatedSheep(self, true)

	-- Loading the avatar yields, so it happens off to the side while the pen starts automating.
	task.spawn(function()
		self:_spawnWorker(token)
	end)

	self:_updateHealthBillboard()

	task.spawn(function()
		while self.workerToken == token and self.data.automated and not self.destroyed do
			task.wait(WORKER_SHEAR_INTERVAL_SECONDS)
			if self.workerToken == token and self.data.automated and not self.destroyed then
				self:_workerShearTick()
			end
		end
	end)

	return true
end

-- Takes the worker off this pen: its shear loop ends, its model and income label go, the sheep health bar hides.
function Pen.removeWorker(self: Pen)
	local hadWorker = self.data.automated
	self.data.automated = false
	self.workerToken += 1

	if hadWorker and not self.shearingPlayer then
		turnSeatedSheep(self, false)
	end

	local worker = self.workerModel
	if worker then
		local index = table.find(self.extras, worker)
		if index then
			table.remove(self.extras, index)
		end
		worker:Destroy() -- takes the income label with it
		self.workerModel = nil
	end
	self.workerRigTrack = nil
	self.workerToolTrack = nil
	self.workerLabel = nil

	if self.healthBillboard then
		self.healthBillboard.Enabled = false
	end
end

--[[
	Puts the pen back to a fresh level-1 pen with no worker (used by rebirth). The model, route and any
	sheep already in the pen are kept; the next sheep simply spawns with the level-1 odds.
]]--
function Pen.resetProgress(self: Pen)
	if self.destroyed then
		return
	end

	self.level = 1
	self.data.chances = SheepData.buildChancesForLevel(1, self.baseLuck)
	self:removeWorker()
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

	self:_playWorkerSwing()

	local newHealth = math.max(current - ShearData.Default.damage, 0)
	sheep:SetAttribute("ShearHealth", newHealth)

	if newHealth <= 0 then
		local woolAmount = sheep:GetAttribute("WoolAmount") :: number
		if self.owner and self.owner.Parent then
			InventoryHandler.addItem(self.owner, "Wool", woolAmount)
			-- The owner's screen shows "+N" rising from where the sheep stood.
			network.fireClient(network.RemoteEvents.WorkerWoolGained, self.owner, self.sheepPosition + Vector3.new(0, 2.5, 0), woolAmount)
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
	local sheepModel, id = SheepHandler.spawnSheep(self.owner, startPosition, self.data.chances)
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
