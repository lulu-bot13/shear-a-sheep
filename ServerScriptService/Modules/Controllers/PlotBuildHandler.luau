--!strict

--[[
	Shows each plot's unlockable builds according to its owner's rebirths.
	Builds are the models named in PenSlotUnlocks; they can sit anywhere inside the plot.

	Location: ServerScriptService.Modules.Controllers.PlotBuildHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local PenSlotUnlocks = require(script.Parent.Parent.Constants.PenSlotUnlocks)
local PlotHandler = require(script.Parent.PlotHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local OWNER_ATTRIBUTE = "Owner"
local REBIRTHS_ATTRIBUTE = "Rebirths"

type Build = {
	instance: Instance,
	parent: Instance,
}

--// State
local plotBuilds: { [Folder]: { [string]: Build } } = {}

local PlotBuildHandler = {}

local function collectBuilds(plot: Folder): { [string]: Build }
	local builds = {}
	for name in PenSlotUnlocks.getBuildStates(0) do
		local instance = plot:FindFirstChild(name, true)
		if instance and instance.Parent then
			builds[name] = { instance = instance, parent = instance.Parent }
		else
			warn(`PlotBuildHandler: {plot.Name} has no build named {name}.`)
		end
	end
	return builds
end

local function refreshPlot(plot: Folder)
	local ownerId = plot:GetAttribute(OWNER_ATTRIBUTE)
	local owner = if typeof(ownerId) == "number" then players:GetPlayerByUserId(ownerId) else nil
	local rebirths = if owner then RebirthHandler.getRebirths(owner) else 0
	local states = PenSlotUnlocks.getBuildStates(rebirths)

	for name, build in plotBuilds[plot] do
		build.instance.Parent = if states[name] then build.parent else nil
	end
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(function()
		local plot = PlotHandler.getPlayerPlot(player)
		if plot and plotBuilds[plot] then
			refreshPlot(plot)
		end
	end)
end

function PlotBuildHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Folder") then
			plotBuilds[plot] = collectBuilds(plot)
			plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(function()
				refreshPlot(plot)
			end)
			refreshPlot(plot)
		end
	end

	players.PlayerAdded:Connect(watchPlayer)
	for _, player in players:GetPlayers() do
		watchPlayer(player)
	end
end

return PlotBuildHandler
