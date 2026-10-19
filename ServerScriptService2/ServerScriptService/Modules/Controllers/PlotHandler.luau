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

local function teleportToPlot(player: Player, plot: Folder)
	local character = player.Character or player.CharacterAdded:Wait()
	local spawnArea = plot:FindFirstChild("SpawnArea")
	if spawnArea and spawnArea:IsA("BasePart") then
		character:PivotTo(spawnArea.CFrame * CFrame.new(0, 2, 0))
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

	teleportToPlot(player, plot)
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
