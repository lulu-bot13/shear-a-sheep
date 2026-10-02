--!strict

--[[
	Assigns each joining player to an open plot and marks them as its owner

	Location: ServerScriptService.Modules.Controllers.PlotHandler
]]--

--// Services
local players = game:GetService("Players")

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local NO_OWNER = 0

local PlotHandler = {}

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute("Owner")
	return if typeof(owner) == "number" then owner else 0
end

local function isBasePlot(plot: Instance): boolean
	return plot:IsA("Folder") and not plot:GetAttribute("Purchased")
end

-- A plot is open when it is a base plot with no owner yet.
local function findOpenPlot(): Folder?
	for _, plot in plotsFolder:GetChildren() do
		if isBasePlot(plot) and getOwnerId(plot) == NO_OWNER then
			return plot :: Folder
		end
	end
	return nil
end

local function getOwnedPlot(player: Player): Folder?
	for _, plot in plotsFolder:GetChildren() do
		if isBasePlot(plot) and getOwnerId(plot) == player.UserId then
			return plot :: Folder
		end
	end
	return nil
end

local function assignPlot(player: Player)
	if getOwnedPlot(player) then
		return
	end

	local plot = findOpenPlot()
	if not plot then
		warn(`PlotHandler: no open plot for {player.Name}.`)
		return
	end

	plot:SetAttribute("Owner", player.UserId)
	player:SetAttribute("PlotName", plot.Name)
end

-- Frees the player's base plot and every pen they bought.
local function releasePlots(player: Player)
	for _, plot in plotsFolder:GetChildren() do
		if getOwnerId(plot) == player.UserId then
			plot:SetAttribute("Owner", NO_OWNER)
		end
	end
end

--[[
	Returns the plot Folder the player owns, or nil if they haven't been given one (yet).
	Every plot-bound system (sheep, pens, buttons) should look the plot up through this.
]]--
function PlotHandler.getPlayerPlot(player: Player): Folder?
	return getOwnedPlot(player)
end

function PlotHandler.Setup()
	players.PlayerAdded:Connect(assignPlot)
	players.PlayerRemoving:Connect(releasePlots)

	-- Players who joined before Setup ran.
	for _, player in players:GetPlayers() do
		assignPlot(player)
	end
end

return PlotHandler
