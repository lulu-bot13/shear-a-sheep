--!strict

--[[
	Unlocks each plot's rebirth builds, and the expansions in Upgrades/Rebirth<owner's rebirths> as the owner upgrades pens.
	An expansion is a child of that folder named Pen<N> (or with a Pen attribute; default 1), shown once pen N reaches its Level attribute (default 2).

	Location: ServerScriptService.Modules.Controllers.PlotBuildHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")

--// Modules
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local PenHandler = require(script.Parent.PenHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local OWNER_ATTRIBUTE = "Owner"
local REBIRTHS_ATTRIBUTE = "Rebirths"
local UNLOCKED_ATTRIBUTE = "Unlocked"
local BUILD_TAG = "RebirthBuild"
local UPGRADE_TAG = "RebirthUpgrade"
local MARKER_FOLDERS = { "Waypoints", "PenSlots" }
local UPGRADES_FOLDER = "Upgrades"
local UPGRADE_PATTERN = "^Rebirth(%d+)$"
local EXPANSION_PATTERN = "^Pen(%d+)$"
local PEN_ATTRIBUTE = "Pen"
local LEVEL_ATTRIBUTE = "Level"
local DEFAULT_PEN = 1
local DEFAULT_LEVEL = 2

type Build = {
	instance: Instance,
	collide: { [BasePart]: boolean },
	prompts: { [ProximityPrompt]: boolean },
	unlocked: boolean?,
}

type Expansion = {
	build: Build,
	rebirth: number,
	pen: number,
	level: number,
}

--// State
local plotBuilds: { [Folder]: { [string]: Build } } = {}
local plotUpgrades: { [Folder]: { Expansion } } = {}
local pendingRefresh: { [Folder]: boolean } = {}

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

local function createBuild(instance: Instance, tag: string): Build
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

	collectionService:AddTag(instance, tag)
	return build
end

local function collectBuilds(plot: Folder): { [string]: Build }
	local builds = {}
	for name in RebirthData.getBuildStates(0) do
		local instance = plot:FindFirstChild(name, true)
		if instance then
			builds[name] = createBuild(instance, BUILD_TAG)
		else
			warn(`PlotBuildHandler: {plot.Name} has no build named {name}.`)
		end
	end
	return builds
end

local function getNumberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

local function collectUpgrades(plot: Folder): { Expansion }
	local folder = plot:FindFirstChild(UPGRADES_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = UPGRADES_FOLDER
		folder.Parent = plot
	end

	local expansions: { Expansion } = {}
	for _, rebirthFolder in folder:GetChildren() do
		local rebirth = tonumber(string.match(rebirthFolder.Name, UPGRADE_PATTERN))
		if not rebirth then
			continue
		end

		for _, child in rebirthFolder:GetChildren() do
			table.insert(expansions, {
				build = createBuild(child, UPGRADE_TAG),
				rebirth = rebirth,
				pen = getNumberAttribute(child, PEN_ATTRIBUTE) or tonumber(string.match(child.Name, EXPANSION_PATTERN)) or DEFAULT_PEN,
				level = getNumberAttribute(child, LEVEL_ATTRIBUTE) or DEFAULT_LEVEL,
			})
		end
	end
	return expansions
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
	local states = RebirthData.getBuildStates(rebirths)

	for name, build in plotBuilds[plot] do
		setUnlocked(build, states[name] == true)
	end

	local penLevels: { [number]: number } = {}
	if owner then
		for _, pen in PenHandler.getPens(owner) do
			penLevels[pen.id] = pen:getLevel()
		end
	end
	for _, expansion in plotUpgrades[plot] do
		setUnlocked(expansion.build, owner ~= nil and expansion.rebirth == rebirths and (penLevels[expansion.pen] or 0) >= expansion.level)
	end
end

-- Batches every change in the same frame (a rebirth bumps the count, removes pens and resets levels at once) into one refresh.
local function scheduleRefresh(plot: Folder?)
	if not plot or pendingRefresh[plot] or not plotBuilds[plot] then
		return
	end

	pendingRefresh[plot] = true
	task.defer(function()
		pendingRefresh[plot] = nil
		refreshPlot(plot)
	end)
end

local function scheduleRefreshFor(player: Player)
	scheduleRefresh(PlotHandler.getPlayerPlot(player))
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(function()
		scheduleRefreshFor(player)
	end)
end

function PlotBuildHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Folder") then
			hideMarkers(plot)
			plotBuilds[plot] = collectBuilds(plot)
			plotUpgrades[plot] = collectUpgrades(plot)
			plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(function()
				scheduleRefresh(plot)
			end)
			refreshPlot(plot)
		end
	end

	PenHandler.PenLevelChanged:Connect(function(pen)
		scheduleRefreshFor(pen.owner)
	end)
	PenHandler.PenRemoved:Connect(scheduleRefreshFor)

	players.PlayerAdded:Connect(watchPlayer)
	for _, player in players:GetPlayers() do
		watchPlayer(player)
	end
end

return PlotBuildHandler
