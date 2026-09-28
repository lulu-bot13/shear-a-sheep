--!strict

--[[
	Builds each player's pens from their plot and tracks them per player

	Location: ServerScriptService.Modules.Controllers.PenHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Pen = require(script.Parent.Parent.Classes.Pen)
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configurations
local INITIAL_SPAWN_DELAY_SECONDS = 5
local PENS_FOLDER_NAME = "Pens"
local BASE_PEN_NAME = "Base_Pen"
local WAYPOINTS_FOLDER_NAME = "Waypoints"
local PATHS_FOLDER_NAME = "Paths"
local PLOT_NAME_ATTRIBUTE = "PlotName"
local SPACING_ATTRIBUTE = "PenSpacing"
local DIRECTION_ATTRIBUTE = "PenDirection"
local DEFAULT_PEN_SPACING = 15.8
local DEFAULT_PEN_DIRECTION = Vector3.new(0, 0, -1)
local PATH_SEAM_GAP = 0.02

type PlotParts = {
	plot: Folder,
	pens: Folder,
	basePen: Model,
	waypoints: Folder?,
	paths: Folder?,
}

--// Variables
local playerPens: { [Player]: { Pen.Pen } } = {}
local started = false

-- New pens are cloned from a pristine snapshot of Base_Pen taken the first time each
-- plot is resolved (at PlayerAdded, before anything can spawn a sheep, seat a worker,
-- or otherwise mutate it) -- never from the live Base_Pen itself, which accumulates
-- runtime state (hired workers, in-progress sheep, prompts) that a freshly-bought pen
-- must NOT inherit.
local pristineBasePens: { [Folder]: Model } = {}

local PenHandler = {}
PenHandler.PenAdded = Signal.new() :: Signal.Signal<Player, Pen.Pen>

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
	local plotName = player:GetAttribute(PLOT_NAME_ATTRIBUTE)
	local plot = if typeof(plotName) == "string" then plotsFolder:FindFirstChild(plotName) else nil
	return if plot and plot:IsA("Folder") then plot else nil
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
	end

	local waypoints = plot:FindFirstChild(WAYPOINTS_FOLDER_NAME)
	local paths = plot:FindFirstChild(PATHS_FOLDER_NAME)

	return {
		plot = plot,
		pens = pens,
		basePen = basePen,
		waypoints = if waypoints and waypoints:IsA("Folder") then waypoints else nil,
		paths = if paths and paths:IsA("Folder") then paths else nil,
	}
end

-- A plot can override how far apart its pens are and which way they grow.
local function getLayout(plot: Folder): (number, Vector3)
	local spacing = plot:GetAttribute(SPACING_ATTRIBUTE)
	local direction = plot:GetAttribute(DIRECTION_ATTRIBUTE)

	local penSpacing = if typeof(spacing) == "number" then spacing else DEFAULT_PEN_SPACING
	local penDirection = if typeof(direction) == "Vector3" and direction.Magnitude > 0
		then direction.Unit
		else DEFAULT_PEN_DIRECTION.Unit

	return penSpacing, penDirection
end

-- Extends the route by cloning its last waypoint one pen further along.
local function createWaypoint(folder: Folder?, waypoints: { BasePart }, step: Vector3): BasePart?
	local last = waypoints[#waypoints]
	if not folder or not last then
		return nil
	end

	local waypoint = last:Clone()
	waypoint.Name = tostring(#waypoints + 1)
	waypoint.Position = last.Position + step
	waypoint.Parent = folder
	return waypoint
end

-- Clones the first path piece into the new pen's slot, trimmed slightly so neighbours don't z-fight.
local function createPathPiece(paths: Folder?, penNumber: number, direction: Vector3, offset: Vector3): BasePart?
	local template = if paths then paths:FindFirstChildWhichIsA("BasePart") else nil
	if not paths or not template then
		return nil
	end

	local piece = template:Clone()
	piece.Name = `Part{penNumber}`
	piece.CFrame = template.CFrame + offset

	local size = piece.Size
	local cframe = piece.CFrame
	if math.abs(cframe.RightVector:Dot(direction)) >= math.abs(cframe.LookVector:Dot(direction)) then
		piece.Size = Vector3.new(size.X - PATH_SEAM_GAP, size.Y, size.Z)
	else
		piece.Size = Vector3.new(size.X, size.Y, size.Z - PATH_SEAM_GAP)
	end

	piece.Parent = paths
	return piece
end

local function registerPen(player: Player, pen: Pen.Pen)
	table.insert(playerPens[player], pen)

	if started then
		pen:start()
	end

	PenHandler.PenAdded:Fire(player, pen)
end

-- Gives a player their first pen, which is the Base_Pen already sitting in their plot.
local function setupPlayer(player: Player)
	local plot = getPlot(player)
	local parts = if plot then findPlotParts(plot) else nil
	if not parts then
		warn(`PenHandler: {player.Name}'s plot has no {PENS_FOLDER_NAME}/{BASE_PEN_NAME}.`)
		return
	end

	local basePen = Pen.new(player, 1, parts.basePen, getWaypointParts(parts.waypoints), {})
	if not basePen then
		return
	end

	playerPens[player] = {}
	registerPen(player, basePen)
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

local function onPlayerRemoving(player: Player)
	local ownedPens = playerPens[player]
	if not ownedPens then
		return
	end

	playerPens[player] = nil
	for _, pen in ownedPens do
		pen:destroy()
	end
end

--[[
	Creates the player's next pen: clones Base_Pen one slot further along the plot,
	extends the waypoint route to it and adds a matching piece of path.
	Returns the new pen, or nil if the player has no valid plot.
]]
function PenHandler.createPen(player: Player): Pen.Pen?
	local ownedPens = playerPens[player]
	local plot = getPlot(player)
	local parts = if plot then findPlotParts(plot) else nil
	if not ownedPens or not parts then
		warn(`PenHandler: cannot create a pen for {player.Name}.`)
		return nil
	end

	local penNumber = #ownedPens + 1
	local spacing, direction = getLayout(parts.plot)
	local step = direction * spacing
	local offset = step * (penNumber - 1)
	local extras: { Instance } = {}

	local template = pristineBasePens[parts.pens] or parts.basePen
	local model = template:Clone()
	model.Name = `Pen_{penNumber}`
	model:PivotTo(model:GetPivot() + offset)
	model.Parent = parts.pens
	table.insert(extras, model)

	local waypoints = getWaypointParts(parts.waypoints)
	local waypoint = createWaypoint(parts.waypoints, waypoints, step)
	if waypoint then
		table.insert(waypoints, waypoint)
		table.insert(extras, waypoint)
	end

	local pathPiece = createPathPiece(parts.paths, penNumber, direction, offset)
	if pathPiece then
		table.insert(extras, pathPiece)
	end

	local pen = Pen.new(player, penNumber, model, waypoints, extras)
	if not pen then
		for _, instance in extras do
			instance:Destroy()
		end
		return nil
	end

	registerPen(player, pen)
	return pen
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
	id, and never the base pen #1) can be sold -- pen numbering and spacing
	assumes a contiguous, append-only list, so removing from the middle
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

	pen:destroy()
	table.remove(ownedPens, lastIndex)
	return true
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
