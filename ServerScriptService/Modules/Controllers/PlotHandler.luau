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
local OWNER_ATTRIBUTE = "Owner"
local PURCHASED_ATTRIBUTE = "Purchased" -- Set by PenPurchase on pens bought later; those are never handed out as a base.
local NO_OWNER = 0

local PlotHandler = {}

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute(OWNER_ATTRIBUTE)
	return if typeof(owner) == "number" then owner else NO_OWNER
end

local function isBasePlot(plot: Instance): boolean
	return plot:IsA("Folder") and not plot:GetAttribute(PURCHASED_ATTRIBUTE)
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

	plot:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	player:SetAttribute("PlotName", plot.Name)
end

-- Frees the player's base plot and every pen they bought.
local function releasePlots(player: Player)
	for _, plot in plotsFolder:GetChildren() do
		if getOwnerId(plot) == player.UserId then
			plot:SetAttribute(OWNER_ATTRIBUTE, NO_OWNER)
		end
	end
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
