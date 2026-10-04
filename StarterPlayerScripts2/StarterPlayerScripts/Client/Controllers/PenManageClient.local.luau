--[[
	The pen manager: a "customize" style screen opened from the Manage button of the pen menu.

	Left panel:  which pen is being managed, plus the category list (only Pens for now).
	Right panel: the pens in the player's inventory as cards (preview, name, x count).
	Pick a card and press Replace: the server swaps the pen's model for that pen and puts the
	pen it had back into the inventory, so the counts on the cards update by themselves.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PenManageClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local penTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Pens")
local penInventory = player:WaitForChild("Inventory"):WaitForChild("Pens")

--// Style (matches the pen menu)
local FONT = Enum.Font.SourceSansBold
local GOLD = Color3.fromRGB(255, 176, 32)
local PANEL_COLOR = Color3.fromRGB(16, 17, 24)
local CARD_COLOR = Color3.fromRGB(30, 32, 44)
local CARD_EDGE = Color3.fromRGB(70, 73, 90)
local MUTED_TEXT = Color3.fromRGB(170, 172, 184)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local CLOSE_STYLE = { fill = Color3.fromRGB(232, 40, 52), edge = Color3.fromRGB(150, 20, 30) }
local CATEGORY_STYLE = { fill = Color3.fromRGB(48, 52, 70), edge = GOLD }
local REPLACE_STYLE = { fill = Color3.fromRGB(150, 230, 30), edge = Color3.fromRGB(40, 150, 20) }
local DISABLED_FILL = Color3.fromRGB(96, 99, 110)
local DISABLED_EDGE = Color3.fromRGB(58, 60, 68)

local LEFT_WIDTH = 300
local RIGHT_WIDTH = 560
local CARD_SIZE = Vector2.new(160, 190)
local SIDE_MARGIN = 28
local SLIDE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LEFT_SHOWN = UDim2.new(0, SIDE_MARGIN, 0.5, 0)
local LEFT_HIDDEN = UDim2.new(0, -(LEFT_WIDTH + 60), 0.5, 0)
local RIGHT_SHOWN = UDim2.new(1, -SIDE_MARGIN, 0.5, 40)
local RIGHT_HIDDEN = UDim2.new(1, RIGHT_WIDTH + 60, 0.5, 40)

type Card = {
	button: TextButton,
	stroke: UIStroke,
	countLabel: TextLabel,
	value: IntValue,
	connection: RBXScriptConnection,
}

--// State
local cards: { [string]: Card } = {}
local managedPenId: number? = nil
local currentPenType: string? = nil
local selectedType: string? = nil
local visible = false
local hideToken = 0

--// Helpers ---------------------------------------------------------------------

-- "Oak_Pen" -> "Oak Pen"
local function formatName(penType: string): string
	return (string.gsub(penType, "_", " "))
end

local function addCorner(target: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = target
end

local function addStroke(target: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or BLACK
	stroke.Thickness = thickness
	stroke.Parent = target
	return stroke
end

local function createLabel(name: string, size: UDim2, textSize: number, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	addStroke(label, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return label
end

-- Outer black frame + dark inner panel with the orange border, like the pen menu.
local function createPanel(name: string, size: UDim2, parent: Instance): (Frame, Frame)
	local root = Instance.new("Frame")
	root.Name = name
	root.Size = size
	root.BackgroundColor3 = BLACK
	root.Parent = parent
	addCorner(root, 12)

	local rootPadding = Instance.new("UIPadding")
	rootPadding.PaddingTop = UDim.new(0, 5)
	rootPadding.PaddingBottom = UDim.new(0, 5)
	rootPadding.PaddingLeft = UDim.new(0, 5)
	rootPadding.PaddingRight = UDim.new(0, 5)
	rootPadding.Parent = root

	local inner = Instance.new("Frame")
	inner.Name = "Panel"
	inner.Size = UDim2.new(1, 0, 1, 0)
	inner.BackgroundColor3 = PANEL_COLOR
	inner.Parent = root
	addCorner(inner, 8)
	addStroke(inner, 3, GOLD)

	local innerPadding = Instance.new("UIPadding")
	innerPadding.PaddingTop = UDim.new(0, 12)
	innerPadding.PaddingBottom = UDim.new(0, 12)
	innerPadding.PaddingLeft = UDim.new(0, 14)
	innerPadding.PaddingRight = UDim.new(0, 14)
	innerPadding.Parent = inner

	return root, inner
end

-- A chunky button: coloured fill, darker edge, outlined label, hover / press feedback.
local function createButton(name: string, text: string, size: UDim2, textSize: number, style: { fill: Color3, edge: Color3 }, parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.AutoButtonColor = false
	button.Font = FONT
	button.TextSize = textSize
	button.TextColor3 = WHITE
	button.Text = text
	button.BackgroundColor3 = style.fill
	button.Parent = parent
	addCorner(button, 10)

	local edge = addStroke(button, 3, style.edge)
	edge.Name = "Edge"
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local textStroke = addStroke(button, 2.5)
	textStroke.Name = "TextStroke"
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function tweenScale(target: number)
		tweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = target }):Play()
	end
	button.MouseEnter:Connect(function()
		tweenScale(1.03)
	end)
	button.MouseLeave:Connect(function()
		tweenScale(1)
	end)
	button.MouseButton1Down:Connect(function()
		tweenScale(0.96)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(1.03)
	end)

	return button
end

--// Build the GUI once ------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PenManageGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 20
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false

local scales: { UIScale } = {}
local function addScale(target: Instance)
	local scale = Instance.new("UIScale")
	scale.Parent = target
	table.insert(scales, scale)
end

-- Left: what is being managed + categories.
local leftRoot, leftPanel = createPanel("Left", UDim2.fromOffset(LEFT_WIDTH, 0), screenGui)
leftRoot.AnchorPoint = Vector2.new(0, 0.5)
leftRoot.Position = LEFT_HIDDEN
leftRoot.AutomaticSize = Enum.AutomaticSize.Y
leftPanel.AutomaticSize = Enum.AutomaticSize.Y
leftPanel.Size = UDim2.new(1, 0, 0, 0)
addScale(leftRoot)

local leftLayout = Instance.new("UIListLayout")
leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
leftLayout.Padding = UDim.new(0, 10)
leftLayout.Parent = leftPanel

local titleLabel = createLabel("Title", UDim2.new(1, 0, 0, 40), 34, GOLD, leftPanel)
titleLabel.Text = "MANAGE PEN"
titleLabel.LayoutOrder = 1

local penNameLabel = createLabel("PenName", UDim2.new(1, 0, 0, 28), 26, WHITE, leftPanel)
penNameLabel.LayoutOrder = 2

local currentLabel = createLabel("Current", UDim2.new(1, 0, 0, 24), 20, MUTED_TEXT, leftPanel)
currentLabel.LayoutOrder = 3

local pensCategory = createButton("Pens", "Pens", UDim2.new(1, 0, 0, 56), 30, CATEGORY_STYLE, leftPanel)
pensCategory.LayoutOrder = 4

-- Right: the inventory grid.
local rightRoot, rightPanel = createPanel("Right", UDim2.new(0, RIGHT_WIDTH, 0.6, 0), screenGui)
rightRoot.AnchorPoint = Vector2.new(1, 0.5)
rightRoot.Position = RIGHT_HIDDEN
addScale(rightRoot)

local gridTitle = createLabel("GridTitle", UDim2.new(1, 0, 0, 30), 26, WHITE, rightPanel)
gridTitle.Text = "Your Pens"

local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.Position = UDim2.fromOffset(0, 38)
grid.Size = UDim2.new(1, 0, 1, -38)
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.ScrollBarThickness = 6
grid.ScrollingDirection = Enum.ScrollingDirection.Y
grid.Parent = rightPanel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
gridLayout.CellPadding = UDim2.fromOffset(12, 12)
gridLayout.SortOrder = Enum.SortOrder.Name
gridLayout.Parent = grid

local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingTop = UDim.new(0, 4)
gridPadding.PaddingLeft = UDim.new(0, 4)
gridPadding.PaddingRight = UDim.new(0, 4)
gridPadding.Parent = grid

local emptyLabel = createLabel("Empty", UDim2.new(1, 0, 0, 60), 24, MUTED_TEXT, rightPanel)
emptyLabel.Position = UDim2.fromOffset(0, 80)
emptyLabel.TextWrapped = true
emptyLabel.Text = "You don't have any pens in your inventory."

-- The red X sits above the top-left corner of the grid, like the reference.
local closeButton = createButton("Close", "X", UDim2.fromOffset(64, 64), 44, CLOSE_STYLE, rightRoot)
closeButton.AnchorPoint = Vector2.new(0, 1)
closeButton.Position = UDim2.new(0, 0, 0, -10)

-- Bottom centre: confirm the swap.
local replaceButton = createButton("Replace", "Select a pen", UDim2.fromOffset(280, 64), 30, REPLACE_STYLE, screenGui)
replaceButton.AnchorPoint = Vector2.new(0.5, 1)
replaceButton.Position = UDim2.new(0.5, 0, 1, -40)
replaceButton.Visible = false
addScale(replaceButton)

screenGui.Parent = playerGui

--// Behaviour --------------------------------------------------------------------

local function setReplaceEnabled(enabled: boolean)
	local edge = replaceButton:FindFirstChild("Edge") :: UIStroke
	replaceButton.BackgroundColor3 = if enabled then REPLACE_STYLE.fill else DISABLED_FILL
	edge.Color = if enabled then REPLACE_STYLE.edge else DISABLED_EDGE
end

local function refreshSelection()
	for penType, card in cards do
		local selected = penType == selectedType
		card.stroke.Color = if selected then GOLD else CARD_EDGE
		card.stroke.Thickness = if selected then 4 else 2
	end

	if selectedType and managedPenId then
		replaceButton.Text = `Replace with {formatName(selectedType)}`
		setReplaceEnabled(true)
	else
		replaceButton.Text = "Select a pen"
		setReplaceEnabled(false)
	end
end

local function refreshEmpty()
	local hasCards = false
	for _, card in cards do
		if card.button.Visible then
			hasCards = true
			break
		end
	end
	emptyLabel.Visible = not hasCards
end

local function refreshHeader()
	penNameLabel.Text = if managedPenId then `Pen {managedPenId}` else ""
	currentLabel.Text = if currentPenType then `Current: {formatName(currentPenType)}` else ""
end

-- A still 3D preview of a pen template; only geometry is kept and the marker parts are hidden.
local function createPreview(penType: string, parent: Instance)
	local template = penTemplates:FindFirstChild(penType)
	if not template or not template:IsA("Model") then
		return
	end

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Position = UDim2.fromOffset(6, 30)
	viewport.Size = UDim2.new(1, -12, 1, -62)
	viewport.Ambient = Color3.fromRGB(170, 170, 170)
	viewport.LightColor = WHITE
	viewport.Parent = parent

	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("GuiBase") or descendant:IsA("ParticleEmitter") then
			descendant:Destroy()
		end
	end
	for _, markerName in { "SheepPos", "PlayerPos" } do
		local marker = clone:FindFirstChild(markerName)
		if marker and marker:IsA("BasePart") then
			marker.Transparency = 1
		end
	end
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local boxCFrame, boxSize = clone:GetBoundingBox()
	local distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(boxCFrame.Position + Vector3.new(0.7, 0.55, 1).Unit * distance, boxCFrame.Position)
end

local function refreshCard(card: Card)
	card.countLabel.Text = `x{card.value.Value}`
	card.button.Visible = card.value.Value > 0
end

local function removeCard(penType: string)
	local card = cards[penType]
	if not card then
		return
	end

	cards[penType] = nil
	card.connection:Disconnect()
	card.button:Destroy()

	if selectedType == penType then
		selectedType = nil
		refreshSelection()
	end
	refreshEmpty()
end

local function addCard(value: Instance)
	if not value:IsA("IntValue") or cards[value.Name] then
		return
	end

	local penType = value.Name

	local button = Instance.new("TextButton")
	button.Name = penType
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = CARD_COLOR
	button.Parent = grid
	addCorner(button, 10)

	local stroke = addStroke(button, 2, CARD_EDGE)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local nameLabel = createLabel("NameLabel", UDim2.new(1, 0, 0, 28), 22, WHITE, button)
	nameLabel.Position = UDim2.fromOffset(0, 4)
	nameLabel.Text = formatName(penType)

	local countLabel = createLabel("CountLabel", UDim2.new(1, 0, 0, 28), 26, WHITE, button)
	countLabel.AnchorPoint = Vector2.new(0, 1)
	countLabel.Position = UDim2.new(0, 0, 1, -4)

	createPreview(penType, button)

	local card: Card = {
		button = button,
		stroke = stroke,
		countLabel = countLabel,
		value = value :: IntValue,
		connection = (value :: IntValue).Changed:Connect(function()
			local existing = cards[penType]
			if existing then
				refreshCard(existing)
				refreshEmpty()
			end
		end),
	}
	cards[penType] = card

	button.MouseButton1Click:Connect(function()
		selectedType = if selectedType == penType then nil else penType
		refreshSelection()
	end)

	refreshCard(card)
	refreshSelection()
	refreshEmpty()
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local scale = math.clamp(math.min(camera.ViewportSize.Y / 720, camera.ViewportSize.X / 1000), 0.5, 1.15)
	for _, uiScale in scales do
		uiScale.Scale = scale
	end
end

local manageClosed: BindableEvent

local function close()
	if not visible then
		return
	end

	visible = false
	managedPenId = nil
	currentPenType = nil
	selectedType = nil
	refreshSelection()
	replaceButton.Visible = false

	hideToken += 1
	local token = hideToken

	tweenService:Create(leftRoot, SLIDE, { Position = LEFT_HIDDEN }):Play()
	local tween = tweenService:Create(rightRoot, SLIDE, { Position = RIGHT_HIDDEN })
	tween:Play()
	tween.Completed:Connect(function()
		if token == hideToken and not visible then
			screenGui.Enabled = false
		end
	end)

	manageClosed:Fire()
end

local function open(data: any)
	managedPenId = data.penId
	currentPenType = data.penType
	selectedType = nil
	refreshHeader()
	refreshSelection()
	refreshEmpty()

	hideToken += 1
	visible = true
	updateScale()
	replaceButton.Visible = true
	screenGui.Enabled = true

	tweenService:Create(leftRoot, SLIDE, { Position = LEFT_SHOWN }):Play()
	tweenService:Create(rightRoot, SLIDE, { Position = RIGHT_SHOWN }):Play()
end

--// Wiring --------------------------------------------------------------------------

local function getBindable(name: string): BindableEvent
	local existing = player:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end

	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = player
	return event
end

local manageRequest = getBindable("ManagePenRequest")
manageClosed = getBindable("ManagePenClosed")

manageRequest.Event:Connect(open)
closeButton.MouseButton1Click:Connect(close)

replaceButton.MouseButton1Click:Connect(function()
	local penId = managedPenId
	local penType = selectedType
	if not penId or not penType then
		return
	end

	local card = cards[penType]
	if not card or card.value.Value <= 0 then
		return
	end

	network.fireServer(network.RemoteEvents.ReplacePen, penId, penType)
	selectedType = nil
	refreshSelection()
end)

for _, child in penInventory:GetChildren() do
	addCard(child)
end
penInventory.ChildAdded:Connect(addCard)
penInventory.ChildRemoved:Connect(function(child: Instance)
	removeCard(child.Name)
end)

network.waitUntilReadyAsync()

-- The server re-sends the menu after a swap; keep the header in step, and close if the player moved on to another pen.
network.connectEvent(network.RemoteEvents.OpenPenMenu, function(data: any)
	if not visible then
		return
	end

	if data.penId ~= managedPenId then
		close()
		return
	end

	currentPenType = data.penType
	refreshHeader()
end)
network.connectEvent(network.RemoteEvents.ClosePenMenu, close)
network.connectEvent(network.RemoteEvents.ActivateShearing, close)
