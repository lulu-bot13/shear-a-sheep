--!strict
--[[
	Makes the Rebirths and Wool boards scrollable: their rows, gaps and padding are turned into pixels and the canvas
	is fitted to the rows Leaderboards.server.luau shows, since AutomaticCanvasSize can't fit Scale-sized rows.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.LeaderboardClient
]]--

--// Configs
local SCROLLING_BOARDS = { Rebirths = true, Wool = true } -- not Titles, which fits every row without scrolling
local ROW_PATTERN = "^Rank%d+$" -- the rows Leaderboards.server.luau clones from the Template

--// Instances
local boardsFolder = workspace:WaitForChild("Base"):WaitForChild("CenterPlaza"):WaitForChild("Leaderboards")

--// State
local boundLists: { [ScrollingFrame]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--// Helpers ---------------------------------------------------------------------

local function toPixels(size: UDim, reference: number): UDim
	return UDim.new(0, math.floor(size.Offset + size.Scale * reference + 0.5))
end

-- The board (direct child of the Leaderboards folder) that holds this instance.
local function getBoardName(instance: Instance): string?
	local current: Instance? = instance
	while current and current.Parent ~= boardsFolder do
		current = current.Parent
	end
	return if current then current.Name else nil
end

--// Board setup -----------------------------------------------------------------

local function bindList(list: ScrollingFrame, template: GuiObject)
	if boundLists[list] then
		return
	end
	boundLists[list] = true

	-- Studio sizes, read once: everything below is converted from these so resizing never compounds.
	local layout = list:FindFirstChildOfClass("UIListLayout")
	local padding = list:FindFirstChildOfClass("UIPadding")
	local rowSize = template.Size
	local designedCanvas = list.CanvasSize.Y
	local designedGap = if layout then layout.Padding else nil
	local designedTop = if padding then padding.PaddingTop else nil
	local designedBottom = if padding then padding.PaddingBottom else nil

	list.AutomaticCanvasSize = Enum.AutomaticSize.None

	-- The height the Studio Scale values were laid out against: the Studio canvas, or the frame if that's taller.
	local function getReferenceHeight(): number
		local frameHeight = list.AbsoluteSize.Y
		return math.max(frameHeight, designedCanvas.Scale * frameHeight + designedCanvas.Offset)
	end

	local function sizeRow(row: Instance, reference: number)
		if row:IsA("GuiObject") and string.match(row.Name, ROW_PATTERN) then
			row.Size = UDim2.new(rowSize.X, toPixels(rowSize.Y, reference))
		end
	end

	-- Taller than the window only when the shown rows don't fit, so short boards don't scroll into empty space.
	local function updateCanvas()
		if not layout then
			return
		end
		local paddingY = if padding then padding.PaddingTop.Offset + padding.PaddingBottom.Offset else 0
		local needed = math.ceil(layout.AbsoluteContentSize.Y + paddingY)
		local canvasSize = UDim2.fromOffset(0, if needed > list.AbsoluteWindowSize.Y then needed else 0)
		if list.CanvasSize ~= canvasSize then
			list.CanvasSize = canvasSize
		end
	end

	local function updateSizes()
		local reference = getReferenceHeight()
		if reference <= 0 then
			return -- not laid out yet
		end

		for _, child in list:GetChildren() do
			sizeRow(child, reference)
		end
		if layout and designedGap then
			layout.Padding = toPixels(designedGap, reference)
		end
		if padding and designedTop and designedBottom then
			padding.PaddingTop = toPixels(designedTop, reference)
			padding.PaddingBottom = toPixels(designedBottom, reference)
		end
		updateCanvas()
	end

	list.ChildAdded:Connect(function(child)
		local reference = getReferenceHeight()
		if reference > 0 then
			sizeRow(child, reference)
		end
	end)
	list:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSizes)
	list:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(updateCanvas)
	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas) -- rows shown or hidden by the server
	end
	updateSizes()
end

-- Deferred so the rest of a streamed-in board (its UIListLayout, UIPadding and rows) has arrived too.
local function onDescendantAdded(instance: Instance)
	if instance.Name ~= "Template" or not instance:IsA("GuiObject") then
		return
	end
	task.defer(function()
		local list = instance.Parent
		local boardName = getBoardName(instance)
		if list and list:IsA("ScrollingFrame") and boardName and SCROLLING_BOARDS[boardName] then
			bindList(list, instance)
		end
	end)
end

for _, descendant in boardsFolder:GetDescendants() do
	onDescendantAdded(descendant)
end
boardsFolder.DescendantAdded:Connect(onDescendantAdded)
