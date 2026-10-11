--!strict

--[[
	Spawns each player's pens from ReplicatedStorage.Assets.Models.Pens onto their plot's PenSlots and tracks them.
	Pen N sits centred on the PenSlots part named N, resting on the floor and facing the way the slot faces.

	Location: ServerScriptService.Modules.Controllers.PenHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Pen = require(script.Parent.Parent.Classes.Pen)
local PlotHandler = require(script.Parent.PlotHandler)
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)

--// Instances
local penTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Pens")

--// Configurations
local INITIAL_SPAWN_DELAY_SECONDS = 5
local PENS_FOLDER_NAME = "Pens"
local WAYPOINTS_FOLDER_NAME = "Waypoints"
local SPAWN_WAYPOINT_PREFIX = "SpawnWaypoint"
local PLACEHOLDERS_FOLDER_NAME = "Placeholders"
local SLOTS_FOLDER_NAME = "PenSlots"
local SHEEPS_FOLDER_NAME = "Sheeps"
local SLOT_OCCUPIED_ATTRIBUTE = "HasPen"
local PLOT_NAME_ATTRIBUTE = "PlotName"
local REBIRTHS_ATTRIBUTE = "Rebirths"
local FLOOR_RAY_HEIGHT = 20
local FLOOR_RAY_LENGTH = 80
local PEN_YAW_DEGREES = 180
local PLACEHOLDER_YAW_DEGREES = 0

--// Variables
local playerPens: { [Player]: { Pen.Pen } } = {}
local penSlots: { [Pen.Pen]: BasePart } = {}
local baseOffsets: { [Model]: CFrame } = {}
local started = false

local PenHandler = {}
PenHandler.PenAdded = Signal.new() :: Signal.Signal<Player, Pen.Pen>
PenHandler.PenRemoved = Signal.new() :: Signal.Signal<Player, Pen.Pen>
PenHandler.PenLevelChanged = Pen.LevelChanged

-- Returns the parts named "1", "2", "3", ... in a folder, in numeric order (the spawn waypoints are not part of this route).
local function getWaypointParts(folder: Instance?): { BasePart }
	local numbered: { [number]: BasePart } = {}
	local numbers: { number } = {}
	if folder then
		for _, child in folder:GetChildren() do
			local number = tonumber(child.Name)
			if number and child:IsA("BasePart") then
				numbered[number] = child
				table.insert(numbers, number)
			end
		end
	end

	table.sort(numbers)
	local parts: { BasePart } = {}
	for _, number in numbers do
		table.insert(parts, numbered[number])
	end

	return parts
end

-- Returns SpawnWaypoint1, SpawnWaypoint2, ... in a folder, stopping at the first gap.
local function getSpawnParts(folder: Instance?): { BasePart }
	local parts: { BasePart } = {}
	if not folder then
		return parts
	end

	local index = 1
	while true do
		local part = folder:FindFirstChild(`{SPAWN_WAYPOINT_PREFIX}{index}`)
		if not part or not part:IsA("BasePart") then
			break
		end
		table.insert(parts, part)
		index += 1
	end

	return parts
end

local function getRebirths(player: Player): number
	local value = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	return if type(value) == "number" then value else 0
end

local function getSlot(plot: Folder, penNumber: number): BasePart?
	local slots = plot:FindFirstChild(SLOTS_FOLDER_NAME)
	local slot = if slots then slots:FindFirstChild(tostring(penNumber)) else nil
	return if slot and slot:IsA("BasePart") then slot else nil
end

local function getPensFolder(plot: Folder): Folder
	local folder = plot:FindFirstChild(PENS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = PENS_FOLDER_NAME
	created.Parent = plot
	return created
end

local function getTemplate(penType: string): Model?
	local template = penTemplates:FindFirstChild(penType)
	if template and template:IsA("Model") then
		return template
	end
	warn(`PenHandler: no pen model named {penType} in ReplicatedStorage.Assets.Models.Pens.`)
	return nil
end

-- Height of the walkable ground under a position, ignoring pens, slots, waypoints, sheep and characters.
local function getFloorY(plot: Folder, position: Vector3): number?
	local ignored: { Instance } = {}
	for _, name in { PENS_FOLDER_NAME, SLOTS_FOLDER_NAME, WAYPOINTS_FOLDER_NAME, SHEEPS_FOLDER_NAME, PLACEHOLDERS_FOLDER_NAME } do
		local folder = plot:FindFirstChild(name)
		if folder then
			table.insert(ignored, folder)
		end
	end
	for _, player in players:GetPlayers() do
		if player.Character then
			table.insert(ignored, player.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true

	local origin = position + Vector3.new(0, FLOOR_RAY_HEIGHT, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -FLOOR_RAY_LENGTH, 0), params)
	return if result then result.Position.Y else nil
end

-- The model's pivot measured from the bottom centre of its world-space bounds, keeping any tilt the model was built with.
local function getBaseOffset(model: Model): CFrame
	local cached = baseOffsets[model]
	if cached then
		return cached
	end

	local pivot = model:GetPivot()
	local box, size = model:GetBoundingBox()
	local halfHeight = (math.abs(box.RightVector.Y) * size.X + math.abs(box.UpVector.Y) * size.Y + math.abs(box.LookVector.Y) * size.Z) / 2
	local _, pivotYaw = pivot:ToOrientation()
	local bottom = CFrame.new(box.Position.X, box.Position.Y - halfHeight, box.Position.Z) * CFrame.Angles(0, pivotYaw, 0)
	local offset = bottom:ToObjectSpace(pivot)
	baseOffsets[model] = offset
	return offset
end

-- Where `model`'s pivot goes so it stands centred on the slot's floor, turned the way the slot faces plus `extraYaw` degrees.
local function getPivotOnSlot(plot: Folder, slot: BasePart, model: Model, extraYaw: number): CFrame?
	local floorY = getFloorY(plot, slot.Position)
	if not floorY then
		return nil
	end

	local _, yaw = slot.CFrame:ToOrientation()
	return CFrame.new(slot.Position.X, floorY, slot.Position.Z) * CFrame.Angles(0, yaw + math.rad(extraYaw), 0) * getBaseOffset(model)
end

local function registerPen(player: Player, pen: Pen.Pen, slot: BasePart)
	table.insert(playerPens[player], pen)
	slot:SetAttribute(SLOT_OCCUPIED_ATTRIBUTE, true)
	penSlots[pen] = slot

	if started then
		pen:start()
	end

	PenHandler.PenAdded:Fire(player, pen)
end

local function disposePen(pen: Pen.Pen)
	local slot = penSlots[pen]
	if slot then
		slot:SetAttribute(SLOT_OCCUPIED_ATTRIBUTE, false)
		penSlots[pen] = nil
	end

	pen:destroy()
end

-- Gives a player their first pen: the pen their rebirths have earned, spawned on slot 1.
local function setupPlayer(player: Player)
	local plot = PlotHandler.getPlayerPlot(player)
	if not plot then
		return
	end

	getPensFolder(plot):ClearAllChildren()
	playerPens[player] = {}
	PenHandler.createPen(player)
end

-- Plots are assigned by PlotHandler, which may run after the player joins.
local function onPlayerAdded(player: Player)
	if PlotHandler.getPlayerPlot(player) then
		setupPlayer(player)
		return
	end

	player:GetAttributeChangedSignal(PLOT_NAME_ATTRIBUTE):Once(function()
		setupPlayer(player)
	end)
end

local function onPlayerRemoving(player: Player)
	local ownedPens = playerPens[player]
	if not ownedPens then
		return
	end

	playerPens[player] = nil
	for _, pen in ownedPens do
		disposePen(pen)
	end
end

-- Warns about any pen named in RebirthData that has no model, listing the models that do exist.
local function validateTemplates()
	local missing: { string } = {}
	for _, penType in RebirthData.getPenNames() do
		if not penTemplates:FindFirstChild(penType) then
			table.insert(missing, penType)
		end
	end

	if #missing > 0 then
		local available: { string } = {}
		for _, child in penTemplates:GetChildren() do
			table.insert(available, child.Name)
		end
		warn(`PenHandler: RebirthData uses missing pen models {table.concat(missing, ", ")}. Available: {table.concat(available, ", ")}`)
	end
end

--[[
	Spawns the player's next pen on the next slot, using the pen model and luck their rebirths have earned.
	Returns the new pen, or nil if the player has no plot, the slot is missing or the model is unusable.
]]
function PenHandler.createPen(player: Player): Pen.Pen?
	local ownedPens = playerPens[player]
	local plot = PlotHandler.getPlayerPlot(player)
	if not ownedPens or not plot then
		warn(`PenHandler: cannot create a pen for {player.Name}.`)
		return nil
	end

	local tier = RebirthData.getTier(getRebirths(player))
	local template = getTemplate(tier.pen)
	local penNumber = #ownedPens + 1
	local slot = getSlot(plot, penNumber)
	local pivot = if slot and template then getPivotOnSlot(plot, slot, template, PEN_YAW_DEGREES) else nil
	if not slot or not template or not pivot then
		warn(`PenHandler: {player.Name} has no usable slot {penNumber}.`)
		return nil
	end

	local model = template:Clone()
	model.Name = `Pen_{penNumber}`
	model:PivotTo(pivot)
	model.Parent = getPensFolder(plot)

	local extras: { Instance } = { model }
	local waypoints = plot:FindFirstChild(WAYPOINTS_FOLDER_NAME)
	local pen = Pen.new(player, penNumber, model, getWaypointParts(waypoints), getSpawnParts(waypoints), extras, tier.pen)
	if not pen then
		model:Destroy()
		return nil
	end

	pen:setBaseLuck(tier.luck)
	registerPen(player, pen, slot)
	return pen
end

-- Where `model`'s pivot goes on this plot's slot; nil if the slot or its floor can't be found.
function PenHandler.getSlotPivot(plot: Folder, slotNumber: number, model: Model): CFrame?
	local slot = getSlot(plot, slotNumber)
	return if slot then getPivotOnSlot(plot, slot, model, PLACEHOLDER_YAW_DEGREES) else nil
end

-- Returns a copy of the player's pens, in the order they were created.
function PenHandler.getPens(player: Player): { Pen.Pen }
	local ownedPens = playerPens[player]
	return if ownedPens then table.clone(ownedPens) else {}
end

-- Returns the player's pen with the given id, or nil.
function PenHandler.getPen(player: Player, penId: number): Pen.Pen?
	local ownedPens = playerPens[player]
	if not ownedPens then
		return nil
	end

	for _, pen in ownedPens do
		if pen.id == penId then
			return pen
		end
	end

	return nil
end

--[[
	Removes a player's pen. Only the newest pen (never pen 1) can be removed, since pen numbering and
	slots assume an append-only list. Returns false if the pen isn't removable or isn't the player's.
]]
function PenHandler.removePen(player: Player, pen: Pen.Pen): boolean
	local ownedPens = playerPens[player]
	if not ownedPens then
		return false
	end

	local lastIndex = #ownedPens
	if pen.id ~= lastIndex or pen.id <= 1 then
		return false
	end

	disposePen(pen)
	table.remove(ownedPens, lastIndex)
	PenHandler.PenRemoved:Fire(player, pen)
	return true
end

-- Swaps a pen to another model from Assets.Models.Pens (e.g. "StonePen"). Returns false if that model is unusable.
function PenHandler.setPenType(pen: Pen.Pen, penType: string): boolean
	if pen.destroyed then
		return false
	end
	if pen.penType == penType then
		return true
	end

	local template = getTemplate(penType)
	local slot = penSlots[pen]
	local plot = PlotHandler.getPlayerPlot(pen.owner)
	local pivot = if template and slot and plot then getPivotOnSlot(plot, slot, template, PEN_YAW_DEGREES) else nil
	if not template or not pivot then
		return false
	end

	return pen:replaceModel(template, penType, pivot)
end

-- Gives a pen the model and luck of the player's current rebirth tier.
function PenHandler.applyRebirthTier(pen: Pen.Pen)
	local tier = RebirthData.getTier(getRebirths(pen.owner))
	pen:setBaseLuck(tier.luck)
	PenHandler.setPenType(pen, tier.pen)
end

-- Returns the pen a currently active sheep belongs to, or nil.
function PenHandler.getPenForSheep(id: number): Pen.Pen?
	return Pen.getBySheepId(id)
end

-- Called by ShearHandler once a sheep has been sheared and removed.
function PenHandler.onSheepRemoved(id: number)
	local pen = Pen.getBySheepId(id)
	if pen then
		pen:releaseSheep()
	end
end

function PenHandler.Setup()
	validateTemplates()

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function PenHandler.Start()
	-- Give the map time to load before the first sheep spawns and walks.
	task.delay(INITIAL_SPAWN_DELAY_SECONDS, function()
		started = true
		for _, ownedPens in playerPens do
			for _, pen in ownedPens do
				pen:start()
			end
		end
	end)
end

return PenHandler
