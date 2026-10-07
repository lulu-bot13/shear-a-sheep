--!strict

--[[
	Builds each player's pens on their plot's PenSlots and tracks them per player.
	Pen N goes on the PenSlots part named N: centred on it, resting on the floor and facing the way the slot faces.

	Location: ServerScriptService.Modules.Controllers.PenHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Pen = require(script.Parent.Parent.Classes.Pen)
local PlotHandler = require(script.Parent.PlotHandler)
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)

--// Instances
local penTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Pens")

--// Configurations
local INITIAL_SPAWN_DELAY_SECONDS = 5
local PENS_FOLDER_NAME = "Pens"
local BASE_PEN_NAME = "Base_Pen"
local WAYPOINTS_FOLDER_NAME = "Waypoints"
local PLACEHOLDERS_FOLDER_NAME = "Placeholders"
local SLOTS_FOLDER_NAME = "PenSlots"
local SHEEPS_FOLDER_NAME = "Sheeps"
local SLOT_OCCUPIED_ATTRIBUTE = "HasPen"
local PLOT_NAME_ATTRIBUTE = "PlotName"
local ENTRANCE_DISTANCE = 12 -- studs from a slot's centre to where its sheep stop, just outside the fence
local FLOOR_RAY_HEIGHT = 20
local FLOOR_RAY_LENGTH = 80

type PlotParts = {
	plot: Folder,
	pens: Folder,
	basePen: Model,
	waypoints: Folder?,
}

--// Variables
local playerPens: { [Player]: { Pen.Pen } } = {}
local penSlots: { [Pen.Pen]: BasePart } = {}
local started = false

local pristineBasePens: { [Folder]: Model } = {}
local basePenOffsetFromSlot: { [Folder]: CFrame } = {}

local PenHandler = {}
PenHandler.PenAdded = Signal.new() :: Signal.Signal<Player, Pen.Pen>
PenHandler.PenRemoved = Signal.new() :: Signal.Signal<Player, Pen.Pen>

-- Returns the parts named "1", "2", "3", ... in a folder, stopping at the first gap.
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

local function getPlot(player: Player): Folder?
	return PlotHandler.getPlayerPlot(player)
end

local function getSlot(plot: Folder, penNumber: number): BasePart?
	local slots = plot:FindFirstChild(SLOTS_FOLDER_NAME)
	local slot = if slots then slots:FindFirstChild(tostring(penNumber)) else nil
	return if slot and slot:IsA("BasePart") then slot else nil
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

-- The slot's spot on the floor, turned the way the slot faces.
local function getFloorFrame(plot: Folder, slot: BasePart): CFrame?
	local floorY = getFloorY(plot, slot.Position)
	if not floorY then
		return nil
	end

	local _, yaw = slot.CFrame:ToOrientation()
	return CFrame.new(slot.Position.X, floorY, slot.Position.Z) * CFrame.Angles(0, yaw, 0)
end

-- Finds the folders a plot needs to hold pens; returns nil if the plot has no Pens/Base_Pen.
local function findPlotParts(plot: Folder): PlotParts?
	local pens = plot:FindFirstChild(PENS_FOLDER_NAME)
	local basePen = if pens then pens:FindFirstChild(BASE_PEN_NAME) else nil
	if not pens or not pens:IsA("Folder") or not basePen or not basePen:IsA("Model") then
		return nil
	end

	if not pristineBasePens[pens] then
		pristineBasePens[pens] = basePen:Clone()

		local firstSlot = getSlot(plot, 1)
		local firstFrame = if firstSlot then getFloorFrame(plot, firstSlot) else nil
		if firstFrame then
			basePenOffsetFromSlot[pens] = firstFrame:ToObjectSpace(basePen:GetPivot())
		end
	end

	local waypoints = plot:FindFirstChild(WAYPOINTS_FOLDER_NAME)

	return {
		plot = plot,
		pens = pens,
		basePen = basePen,
		waypoints = if waypoints and waypoints:IsA("Folder") then waypoints else nil,
	}
end

-- Where a new pen's pivot goes so it sits on the slot exactly like Base_Pen sits on slot 1.
local function getPenPivot(parts: PlotParts, slot: BasePart): CFrame?
	local offset = basePenOffsetFromSlot[parts.pens]
	local frame = getFloorFrame(parts.plot, slot)
	return if offset and frame then frame * offset else nil
end

-- Marks the spot just outside a pen's entrance, on the floor, where its sheep finish their walk.
local function createEntranceWaypoint(parts: PlotParts, slot: BasePart, penNumber: number): BasePart?
	local template = getWaypointParts(parts.waypoints)[1]
	if not parts.waypoints or not template then
		return nil
	end

	local target = slot.Position + slot.CFrame.LookVector * ENTRANCE_DISTANCE
	local floorY = getFloorY(parts.plot, target)
	if not floorY then
		return nil
	end

	local entrance = template:Clone()
	entrance.Name = `Entrance{penNumber}`
	entrance.Position = Vector3.new(target.X, floorY + template.Size.Y / 2, target.Z)
	entrance.Parent = parts.waypoints
	return entrance
end

-- The plot's shared waypoints followed by this pen's entrance; the entrance is added to extras so it is cleaned up with the pen.
local function buildRoute(parts: PlotParts, slot: BasePart?, penNumber: number, extras: { Instance }): { BasePart }
	local route = getWaypointParts(parts.waypoints)
	local entrance = if slot then createEntranceWaypoint(parts, slot, penNumber) else nil
	if entrance then
		table.insert(route, entrance)
		table.insert(extras, entrance)
	end

	return route
end

local function registerPen(player: Player, pen: Pen.Pen, slot: BasePart?)
	table.insert(playerPens[player], pen)

	if slot then
		slot:SetAttribute(SLOT_OCCUPIED_ATTRIBUTE, true)
		penSlots[pen] = slot
	end

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

-- Gives a player their first pen, which is the Base_Pen already sitting on slot 1 in their plot.
local function setupPlayer(player: Player)
	local plot = getPlot(player)
	local parts = if plot then findPlotParts(plot) else nil
	if not parts then
		warn(`PenHandler: {player.Name}'s plot has no {PENS_FOLDER_NAME}/{BASE_PEN_NAME}.`)
		return
	end

	local slot = getSlot(parts.plot, 1)
	local extras: { Instance } = {}
	local route = buildRoute(parts, slot, 1, extras)

	local basePen = Pen.new(player, 1, parts.basePen, route, extras)
	if not basePen then
		for _, instance in extras do
			instance:Destroy()
		end
		return
	end

	playerPens[player] = {}
	registerPen(player, basePen, slot)
end

-- Plots are assigned by PlotHandler, which may run after the player joins.
local function onPlayerAdded(player: Player)
	if getPlot(player) then
		setupPlayer(player)
		return
	end

	player:GetAttributeChangedSignal(PLOT_NAME_ATTRIBUTE):Once(function()
		setupPlayer(player)
	end)
end

-- The base pen's model is part of the plot itself, so it is swapped back to an untouched copy for the plot's next owner.
local function restoreBasePen(pen: Pen.Pen)
	local model = pen.penModel
	local pens = model.Parent
	local pristine = if pens then pristineBasePens[pens :: Folder] else nil
	if not pens or not pristine then
		return
	end

	model:Destroy()
	pristine:Clone().Parent = pens
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

	local basePen = ownedPens[1]
	if basePen then
		restoreBasePen(basePen)
	end
end

--[[
	Creates the player's next pen on the next slot: a fresh Base_Pen set on the floor of slot N,
	facing the way the slot faces, with its own stop just outside the entrance for the sheep.
	Returns the new pen, or nil if the player has no valid plot or that slot is missing.
]]
function PenHandler.createPen(player: Player): Pen.Pen?
	local ownedPens = playerPens[player]
	local plot = getPlot(player)
	local plotParts = if plot then findPlotParts(plot) else nil
	if not ownedPens or not plotParts then
		warn(`PenHandler: cannot create a pen for {player.Name}.`)
		return nil
	end

	local penNumber = #ownedPens + 1
	local slot = getSlot(plotParts.plot, penNumber)
	local pivot = if slot then getPenPivot(plotParts, slot) else nil
	if not slot or not pivot then
		warn(`PenHandler: {player.Name} has no usable slot {penNumber}.`)
		return nil
	end

	local extras: { Instance } = {}

	local template = pristineBasePens[plotParts.pens] or plotParts.basePen
	local model = template:Clone()
	model.Name = `Pen_{penNumber}`
	model:PivotTo(pivot)
	model.Parent = plotParts.pens
	table.insert(extras, model)

	local route = buildRoute(plotParts, slot, penNumber, extras)

	local pen = Pen.new(player, penNumber, model, route, extras)
	if not pen then
		for _, instance in extras do
			instance:Destroy()
		end
		return nil
	end

	registerPen(player, pen, slot)
	return pen
end

-- Where a pen model authored like Base_Pen would be pivoted on this plot's slot; nil if the slot or plot is unusable.
function PenHandler.getSlotPivot(plot: Folder, slotNumber: number): CFrame?
	local parts = findPlotParts(plot)
	local slot = getSlot(plot, slotNumber)
	return if parts and slot then getPenPivot(parts, slot) else nil
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
	Removes a player's pen. Only the most-recently-bought pen (the highest
	id, and never the base pen #1) can be sold -- pen numbering and slots
	assume a contiguous, append-only list, so removing from the middle
	would require re-flowing every pen after it. Returns false if the pen
	isn't sellable or isn't the player's.
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

-- Gives a pen the look of one of the pen templates (e.g. "Stone_Pen"). Returns false if there is no such template.
function PenHandler.setPenType(pen: Pen.Pen, penType: string): boolean
	if pen.destroyed then
		return false
	end
	if pen.penType == penType then
		return true
	end

	local template = penTemplates:FindFirstChild(penType)
	if not template or not template:IsA("Model") then
		warn(`PenHandler: no pen template named {penType}.`)
		return false
	end

	return pen:replaceModel(template, penType)
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
