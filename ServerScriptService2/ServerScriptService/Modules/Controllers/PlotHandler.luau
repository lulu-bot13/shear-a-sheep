--!strict

--[[
	Assigns each joining player to an open plot, marks them as its owner and moves them onto it.

	Location: ServerScriptService.Modules.Controllers.PlotHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local NO_OWNER = 0
local SPAWN_AREA_NAME = "SpawnArea"
local SPAWN_LIFT = 2 -- studs above a plot's SpawnArea a character is placed
local SPAWN_LOCATION_LIFT = 3 -- studs above Workspace.SpawnLocation and the shear shop's ShearSpawn
local SHEAR_SPAWN_PATH = { "Base", "CenterPlaza", "ShearShop", "ShearSpawn" } -- in Workspace, in front of the shop, facing it
local TELEPORT_ON_JOIN = true -- false: joiners start at Workspace.SpawnLocation and PathGuideClient's trail walks them home

local PlotHandler = {}

PlotHandler.PlotAssigned = Signal.new() -- (player, plot)
PlotHandler.PlotReleased = Signal.new() -- (player, plot)

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute("Owner")
	return if typeof(owner) == "number" then owner else NO_OWNER
end

local function findPlot(ownerId: number): Folder?
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Folder") and getOwnerId(plot) == ownerId then
			return plot
		end
	end
	return nil
end

local function getPlotSpawn(plot: Instance): CFrame?
	local spawnArea = plot:FindFirstChild(SPAWN_AREA_NAME)
	return if spawnArea and spawnArea:IsA("BasePart") then spawnArea.CFrame * CFrame.new(0, SPAWN_LIFT, 0) else nil
end

local function teleportToPlot(player: Player, plot: Folder)
	local character = player.Character or player.CharacterAdded:Wait()
	local target = getPlotSpawn(plot)
	if target then
		character:PivotTo(target)
	end
end

local function assignPlot(player: Player)
	if findPlot(player.UserId) then
		return
	end

	local plot = findPlot(NO_OWNER)
	if not plot then
		warn(`PlotHandler: no open plot for {player.Name}.`)
		return
	end

	plot:SetAttribute("Owner", player.UserId)
	player:SetAttribute("PlotName", plot.Name)
	PlotHandler.PlotAssigned:Fire(player, plot)

	if TELEPORT_ON_JOIN then
		teleportToPlot(player, plot)
	end
end

local function releasePlot(player: Player)
	local plot = findPlot(player.UserId)
	if plot then
		plot:SetAttribute("Owner", NO_OWNER)
		PlotHandler.PlotReleased:Fire(player, plot)
	end
end

-- The plot Folder the player owns, or nil if they haven't been given one (yet).
function PlotHandler.getPlayerPlot(player: Player): Folder?
	return findPlot(player.UserId)
end

-- Where a character goes "home": over their plot's SpawnArea, or over Workspace.SpawnLocation without a plot.
function PlotHandler.getRespawnCFrame(player: Player): CFrame?
	local plot = findPlot(player.UserId)
	local target = if plot then getPlotSpawn(plot) else nil
	return target or PlotHandler.getPlazaCFrame()
end

-- Over Workspace.SpawnLocation (the east end of the main avenue), or nil if it is missing.
function PlotHandler.getPlazaCFrame(): CFrame?
	local spawnLocation = workspace:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		return spawnLocation.CFrame * CFrame.new(0, SPAWN_LOCATION_LIFT, 0)
	end
	warn("PlotHandler: Workspace.SpawnLocation is missing; build it in Studio.")
	return nil
end

-- Over the ShearSpawn in front of the shear shop, facing it; Workspace.SpawnLocation if it is missing.
function PlotHandler.getShopCFrame(): CFrame?
	local shearSpawn: Instance? = workspace
	for _, name in SHEAR_SPAWN_PATH do
		shearSpawn = shearSpawn and shearSpawn:FindFirstChild(name)
	end
	if shearSpawn and shearSpawn:IsA("BasePart") then
		return shearSpawn.CFrame * CFrame.new(0, SPAWN_LOCATION_LIFT, 0)
	end
	return PlotHandler.getPlazaCFrame()
end

-- Yields until the player owns a plot; nil if they leave (or none frees up) first.
function PlotHandler.waitForPlot(player: Player): Folder?
	local plot = findPlot(player.UserId)
	while not plot and player.Parent do
		task.wait(0.1)
		plot = findPlot(player.UserId)
	end
	return plot
end

function PlotHandler.Setup()
	players.PlayerAdded:Connect(assignPlot)
	players.PlayerRemoving:Connect(releasePlot)

	-- Players who joined before Setup ran.
	for _, player in players:GetPlayers() do
		task.spawn(assignPlot, player)
	end
end

return PlotHandler
