--[[
	Fills the Titles board in Workspace with every title and the sheep sheared needed to earn it.
]]--

--// Services
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local TitleHandler = require(serverScriptService.Modules.Controllers.TitleHandler)

local leaderboards = workspace:WaitForChild("Base"):WaitForChild("CenterPlaza"):WaitForChild("Leaderboards")
local board = leaderboards:WaitForChild("Titles", 15)
local template = board and board:FindFirstChild("Template", true) :: Frame?
if not template then
	warn(`TitlesBoard: no Titles board with a Template row in {leaderboards:GetFullName()}.`)
	return
end
local list = template.Parent :: GuiObject
local listLayout = list:FindFirstChildOfClass("UIListLayout")
template.Visible = false

-- No scrolling: every row has to fit on the board.
if list:IsA("ScrollingFrame") then
	list.ScrollingEnabled = false
	list.ScrollBarThickness = 0
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	list.CanvasSize = UDim2.fromScale(1, 1)
end

-- The template's height, shrunk so `count` rows and the gaps between them fit in the list.
local function getRowHeight(count: number): UDim
	local padding = if listLayout then listLayout.Padding else UDim.new(0, 0)
	local gaps = count - 1
	local fitHeight = UDim.new((1 - padding.Scale * gaps) / count, -padding.Offset * gaps / count)

	local height = template.Size.Y
	if height.Scale == 0 or height.Scale > fitHeight.Scale then
		return fitHeight
	end
	return height
end

local titles = TitleHandler.getTitles()
local rowHeight = getRowHeight(#titles)

for index, title in titles do
	local row = template:Clone()
	row.Name = title.name
	row.LayoutOrder = #titles - index + 1 -- highest requirement at the top
	row.Size = UDim2.new(template.Size.X, rowHeight)
	row.Visible = true

	local titleLabel = row:WaitForChild("Title") :: TextLabel
	titleLabel.Text = title.name
	titleLabel.TextColor3 = title.color

	local shearedLabel = row:WaitForChild("Sheared") :: TextLabel
	shearedLabel.Text = tostring(title.sheepRequired)
	shearedLabel.FontFace = titleLabel.FontFace
	shearedLabel.TextColor3 = title.color

	row.Parent = list
end
