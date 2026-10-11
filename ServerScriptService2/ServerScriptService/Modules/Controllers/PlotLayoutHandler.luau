--!strict

--[[
	Copies the source plot's Waypoints and PenSlots onto every other plot when the game starts.
	Each copy is placed relative to that plot's SpawnArea, so only the source plot needs editing.

	Location: ServerScriptService.Modules.Controllers.PlotLayoutHandler
]]--

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local SOURCE_PLOT_NAME = "Plot_1"
local ANCHOR_NAME = "SpawnArea"
local PURCHASED_ATTRIBUTE = "Purchased"
local LAYOUT_FOLDERS = { "Waypoints", "PenSlots" }

local PlotLayoutHandler = {}

local function getAnchor(plot: Instance): BasePart?
	local anchor = plot:FindFirstChild(ANCHOR_NAME)
	return if anchor and anchor:IsA("BasePart") then anchor else nil
end

-- Moves every part and model directly inside the folder (descending into sub-folders) from the source anchor's space to the target's.
local function reposition(container: Instance, sourceAnchor: CFrame, targetAnchor: CFrame)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			child.CFrame = targetAnchor * sourceAnchor:ToObjectSpace(child.CFrame)
		elseif child:IsA("Model") then
			child:PivotTo(targetAnchor * sourceAnchor:ToObjectSpace(child:GetPivot()))
		else
			reposition(child, sourceAnchor, targetAnchor)
		end
	end
end

local function layoutPlot(source: Folder, sourceAnchor: BasePart, plot: Folder)
	local anchor = getAnchor(plot)
	if not anchor then
		warn(`PlotLayoutHandler: {plot.Name} has no {ANCHOR_NAME}.`)
		return
	end

	for _, name in LAYOUT_FOLDERS do
		local original = source:FindFirstChild(name)
		if not original then
			warn(`PlotLayoutHandler: {source.Name} has no {name}.`)
			continue
		end

		local existing = plot:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end

		local copy = original:Clone()
		reposition(copy, sourceAnchor.CFrame, anchor.CFrame)
		copy.Parent = plot
	end
end

function PlotLayoutHandler.Setup()
	local source = plotsFolder:WaitForChild(SOURCE_PLOT_NAME)
	local sourceAnchor = getAnchor(source)
	if not source:IsA("Folder") or not sourceAnchor then
		warn(`PlotLayoutHandler: {SOURCE_PLOT_NAME} needs to be a Folder with a {ANCHOR_NAME}.`)
		return
	end

	for _, plot in plotsFolder:GetChildren() do
		if plot ~= source and plot:IsA("Folder") and not plot:GetAttribute(PURCHASED_ATTRIBUTE) then
			layoutPlot(source, sourceAnchor, plot)
		end
	end
end

return PlotLayoutHandler
