--!strict

--[[
	Unlocks each plot's builds according to its owner's rebirths and keeps the plot's Waypoints and PenSlots invisible.
	Builds are the models named in PenSlotUnlocks; they can sit anywhere inside the plot.

	A locked build stays in the world but is non-collidable with its prompts off. Its Unlocked attribute is
	what PlotBuildsClient animates (fade in and plop), so the server never touches transparency or position.

	Location: ServerScriptService.Modules.Controllers.PlotBuildHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
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
local UNLOCKED_ATTRIBUTE = "Unlocked"
local BUILD_TAG = "RebirthBuild"
local MARKER_FOLDERS = { "Waypoints", "PenSlots" }

type Build = {
	instance: Instance,
	collide: { [BasePart]: boolean },
	prompts: { [ProximityPrompt]: boolean },
	unlocked: boolean?,
}

--// State
local plotBuilds: { [Folder]: { [string]: Build } } = {}

local PlotBuildHandler = {}

local function hideMarker(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Transparency = 1
		instance.CastShadow = false
	elseif instance:IsA("Decal") then
		instance.Transparency = 1
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = false
	end
end

local function hideMarkers(plot: Folder)
	for _, name in MARKER_FOLDERS do
		local folder = plot:FindFirstChild(name)
		if folder then
			for _, descendant in folder:GetDescendants() do
				hideMarker(descendant)
			end
			folder.DescendantAdded:Connect(hideMarker)
		end
	end
end

local function createBuild(instance: Instance): Build
	local build: Build = { instance = instance, collide = {}, prompts = {}, unlocked = nil }
	for _, item in instance:GetDescendants() do
		if item:IsA("BasePart") then
			build.collide[item] = item.CanCollide
		elseif item:IsA("ProximityPrompt") then
			build.prompts[item] = item.Enabled
		end
	end
	if instance:IsA("BasePart") then
		build.collide[instance] = instance.CanCollide
	end

	collectionService:AddTag(instance, BUILD_TAG)
	return build
end

local function collectBuilds(plot: Folder): { [string]: Build }
	local builds = {}
	for name in PenSlotUnlocks.getBuildStates(0) do
		local instance = plot:FindFirstChild(name, true)
		if instance then
			builds[name] = createBuild(instance)
		else
			warn(`PlotBuildHandler: {plot.Name} has no build named {name}.`)
		end
	end
	return builds
end

local function setUnlocked(build: Build, unlocked: boolean)
	if build.unlocked == unlocked then
		return
	end
	build.unlocked = unlocked

	for part, canCollide in build.collide do
		part.CanCollide = unlocked and canCollide
	end
	for prompt, enabled in build.prompts do
		prompt.Enabled = unlocked and enabled
	end
	build.instance:SetAttribute(UNLOCKED_ATTRIBUTE, unlocked)
end

local function refreshPlot(plot: Folder)
	local ownerId = plot:GetAttribute(OWNER_ATTRIBUTE)
	local owner = if typeof(ownerId) == "number" then players:GetPlayerByUserId(ownerId) else nil
	local rebirths = if owner then RebirthHandler.getRebirths(owner) else 0
	local states = PenSlotUnlocks.getBuildStates(rebirths)

	for name, build in plotBuilds[plot] do
		setUnlocked(build, states[name] == true)
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
			hideMarkers(plot)
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
