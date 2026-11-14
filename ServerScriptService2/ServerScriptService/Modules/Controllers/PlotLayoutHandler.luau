--!strict

--[[
	Rebuilds every plot from Plots.TemplatePlot on server start (relative to each SpawnArea), then parks the template in ServerStorage.
	Swaps each claimed plot's pen fence for the ServerStorage.PenStyles tier its owner's rebirths / Prestiges reached (PenStyleData).

	Location: ServerScriptService.Modules.Controllers.PlotLayoutHandler
]]--

--// Services
local players = game:GetService("Players")
local serverStorage = game:GetService("ServerStorage")

--// Modules
local PenStyleData = require(script.Parent.Parent.Constants.PenStyleData)
local PlotHandler = require(script.Parent.PlotHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local TEMPLATE_NAME = "TemplatePlot"
local ANCHOR_NAME = "SpawnArea"
local CENTER_NAME = "Center"
local OWNER_GUI_NAMES = { "PlayerBase", "SheepCapacity" } -- hidden until PlotOwnerClient shows them on a claimed plot
local PEN_TIER_ATTRIBUTE = "PenTier" -- on the plot: the style tier its fence shows (PenUnlockClient plays its cutscene when it goes up)
local PEN_NAME_ATTRIBUTE = "PenName" -- on the plot: that tier's name, for the cutscene's title card
local WATCHED_ATTRIBUTES = { "Rebirths", "Prestiges" } -- mirrored onto the player by PlayerDataHandler

--// State
local templateAnchorCFrame: CFrame? = nil
local ownerConnections: { [Player]: { RBXScriptConnection } } = {}
local queuedUpdates: { [Player]: boolean } = {}

local PlotLayoutHandler = {}

local function getAnchor(plot: Instance): BasePart?
	local anchor = plot:FindFirstChild(ANCHOR_NAME)
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

-- Moves a part or model (or everything inside a folder) from the template anchor's space to the plot's.
local function reposition(instance: Instance, sourceAnchor: CFrame, targetAnchor: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = targetAnchor * sourceAnchor:ToObjectSpace(instance.CFrame)
	elseif instance:IsA("Model") then
		instance:PivotTo(targetAnchor * sourceAnchor:ToObjectSpace(instance:GetPivot()))
	else
		for _, child in instance:GetChildren() do
			reposition(child, sourceAnchor, targetAnchor)
		end
	end
end

-- Replaces everything on the plot except its SpawnArea with a fresh copy of the template.
local function buildPlot(template: Folder, templateAnchor: BasePart, plot: Folder)
	local anchor = getAnchor(plot)
	if not anchor then
		warn(`PlotLayoutHandler: {plot.Name} has no {ANCHOR_NAME}.`)
		return
	end

	for _, child in plot:GetChildren() do
		if child ~= anchor then
			child:Destroy()
		end
	end

	for _, child in template:GetChildren() do
		if child ~= templateAnchor then
			local copy = child:Clone()
			reposition(copy, templateAnchor.CFrame, anchor.CFrame)
			copy.Parent = plot
		end
	end
end

local function buildPlots()
	local template = plotsFolder:FindFirstChild(TEMPLATE_NAME)
	local templateAnchor = if template then getAnchor(template) else nil
	if not template or not template:IsA("Folder") or not templateAnchor then
		warn(`PlotLayoutHandler: Plots.{TEMPLATE_NAME} needs to be a Folder with a {ANCHOR_NAME}.`)
		return
	end

	template.Parent = serverStorage
	templateAnchorCFrame = templateAnchor.CFrame

	-- Every plot starts unclaimed, so its owner signs start hidden.
	local center = template:FindFirstChild(CENTER_NAME)
	for _, name in OWNER_GUI_NAMES do
		local gui = center and center:FindFirstChild(name)
		if gui and gui:IsA("LayerCollector") then
			gui.Enabled = false
		end
	end

	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Folder") then
			buildPlot(template, templateAnchor, plot)
		end
	end
end

--// Pen styles --------------------------------------------------------------------------

-- Replaces the plot's fence with a copy of the tier's PenStyles model (built over the template's fence: same posts and rails).
local function applyPenStyle(plot: Instance, tier: number)
	local anchor = getAnchor(plot)
	if plot:GetAttribute(PEN_TIER_ATTRIBUTE) == tier or not anchor or not templateAnchorCFrame then
		return
	end
	local templateName = PenStyleData.Tiers[tier].template
	local styles = serverStorage:FindFirstChild(PenStyleData.FolderName)
	local style = styles and styles:FindFirstChild(templateName)
	if not style or not style:IsA("Model") then
		warn(`PlotLayoutHandler: ServerStorage.{PenStyleData.FolderName}.{templateName} is missing; build it in Studio.`)
		return
	end

	local fence = style:Clone()
	fence.Name = PenStyleData.FenceName
	reposition(fence, templateAnchorCFrame, anchor.CFrame)
	local current = plot:FindFirstChild(PenStyleData.FenceName)
	if current then
		current:Destroy()
	end
	fence.Parent = plot
	plot:SetAttribute(PEN_NAME_ATTRIBUTE, PenStyleData.Tiers[tier].name)
	plot:SetAttribute(PEN_TIER_ATTRIBUTE, tier)
end

local function getCount(player: Player, attribute: string): number
	local value = player:GetAttribute(attribute)
	return if type(value) == "number" then value else 0
end

local function updatePen(player: Player)
	queuedUpdates[player] = nil
	local plot = PlotHandler.getPlayerPlot(player)
	if plot then
		applyPenStyle(plot, PenStyleData.getTier(getCount(player, "Rebirths"), getCount(player, "Prestiges")))
	end
end

-- A Prestige changes Rebirths and Prestiges together, so the swap waits for the end of the frame and runs once.
local function queuePenUpdate(player: Player)
	if not queuedUpdates[player] then
		queuedUpdates[player] = true
		task.defer(updatePen, player)
	end
end

local function disconnectOwner(player: Player)
	local connections = ownerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		ownerConnections[player] = nil
	end
end

local function onPlotAssigned(player: Player)
	disconnectOwner(player)
	local connections = {}
	for _, attribute in WATCHED_ATTRIBUTES do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			queuePenUpdate(player)
		end))
	end
	ownerConnections[player] = connections
	queuePenUpdate(player)
end

local function onPlotReleased(player: Player, plot: Instance)
	disconnectOwner(player)
	applyPenStyle(plot, 1)
end

function PlotLayoutHandler.Start()
	PlotHandler.PlotAssigned:Connect(onPlotAssigned)
	PlotHandler.PlotReleased:Connect(onPlotReleased)

	-- Plots handed out during PlotHandler.Setup, before these connections existed.
	for _, player in players:GetPlayers() do
		if PlotHandler.getPlayerPlot(player) then
			onPlotAssigned(player)
		end
	end
end

-- Runs when the module is required. ModuleLoader requires every module before any Setup, so the plots are built before anything uses them.
buildPlots()

return PlotLayoutHandler
