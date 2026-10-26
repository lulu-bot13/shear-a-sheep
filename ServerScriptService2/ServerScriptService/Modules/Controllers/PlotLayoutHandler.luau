--!strict

--[[
	Rebuilds every plot from Plots.TemplatePlot when the server starts, placing each copy relative to that plot's SpawnArea.
	The template is then moved to ServerStorage so it is never handed out as a plot.

	Location: ServerScriptService.Modules.Controllers.PlotLayoutHandler
]]--

--// Services
local serverStorage = game:GetService("ServerStorage")

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local TEMPLATE_NAME = "TemplatePlot"
local ANCHOR_NAME = "SpawnArea"
local CENTER_NAME = "Center"
local OWNER_GUI_NAMES = { "PlayerBase", "SheepCapacity" } -- hidden until PlotOwnerClient shows them on a claimed plot

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

-- Runs when the module is required. ModuleLoader requires every module before any Setup, so the plots are built before anything uses them.
buildPlots()

return PlotLayoutHandler
