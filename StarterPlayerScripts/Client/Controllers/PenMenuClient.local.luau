--[[
	The pen menu, shown on the right of the screen while the player stands at one of
	their pens (the server opens/closes it as they walk up and away). Four things:
	START SHEARING, upgrade, automate (hire a worker) and sell (newest pen only).

	Styled after the tycoon-style item card: dark card, orange border, bold outlined
	text and big chunky coloured buttons.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PenMenuClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sheepTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Sheeps")

--// Style
local FONT = Enum.Font.SourceSansBold
local GOLD = Color3.fromRGB(255, 176, 32)
local GREEN_TEXT = Color3.fromRGB(110, 255, 130)
local BLUE_TEXT = Color3.fromRGB(120, 210, 255)
local PANEL_COLOR = Color3.fromRGB(16, 17, 24)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local BUTTON_STYLES = {
	Upgrade = { fill = Color3.fromRGB(120, 226, 160), edge = Color3.fromRGB(48, 160, 96) },
	Automate = { fill = Color3.fromRGB(150, 230, 30), edge = Color3.fromRGB(40, 150, 20) },
	Shear = { fill = Color3.fromRGB(48, 178, 240), edge = Color3.fromRGB(18, 100, 180) },
	Sell = { fill = Color3.fromRGB(232, 78, 88), edge = Color3.fromRGB(150, 34, 48) },
}
local DISABLED_FILL = Color3.fromRGB(96, 99, 110)
local DISABLED_EDGE = Color3.fromRGB(58, 60, 68)

local PANEL_WIDTH = 320
local SLIDE_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHOWN_POSITION = UDim2.new(1, -28, 0.5, 0)
local HIDDEN_POSITION = UDim2.new(1, PANEL_WIDTH + 60, 0.5, 0)

--// State
local currentData: any = nil
local visible = false
local hideToken = 0

--// Helpers ------------------------------------------------------------------

-- 1500 -> "$1.50K", 2000000 -> "$2.00M" (matches the reference card's money style).
local function formatMoney(amount: number): string
	if amount >= 1e6 then
		return string.format("$%.2fM", amount / 1e6)
	elseif amount >= 1e3 then
		return string.format("$%.2fK", amount / 1e3)
	end
	return "$" .. tostring(math.floor(amount))
end

local function addStroke(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local function createLabel(name: string, order: number, height: number, textSize: number, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, height)
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = ""
	label.Parent = parent
	addStroke(label, 2.5)
	return label
end

--// Build the GUI once --------------------------------------------------------

-- ONE highlight for the whole session: selecting a pen just points it at that pen's model
-- (it's never recreated) and hiding the menu switches it off.
local selectionHighlight = Instance.new("Highlight")
selectionHighlight.Name = "PenSelectionHighlight"
selectionHighlight.FillColor = GOLD
selectionHighlight.FillTransparency = 0.85
selectionHighlight.OutlineColor = GOLD
selectionHighlight.OutlineTransparency = 0
selectionHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
selectionHighlight.Enabled = false
selectionHighlight.Parent = workspace

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PenMenuGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false

-- Outer black frame + inner dark panel with the orange border.
local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(1, 0.5)
root.Position = HIDDEN_POSITION
root.Size = UDim2.fromOffset(PANEL_WIDTH, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundColor3 = BLACK
root.Parent = screenGui

local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = UDim.new(0, 12)
rootCorner.Parent = root

local rootPadding = Instance.new("UIPadding")
rootPadding.PaddingTop = UDim.new(0, 5)
rootPadding.PaddingBottom = UDim.new(0, 5)
rootPadding.PaddingLeft = UDim.new(0, 5)
rootPadding.PaddingRight = UDim.new(0, 5)
rootPadding.Parent = root

local uiScale = Instance.new("UIScale")
uiScale.Parent = root

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(1, 0, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = PANEL_COLOR
panel.Parent = root

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = GOLD
panelStroke.Thickness = 3
panelStroke.Parent = panel

local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 12)
panelPadding.PaddingBottom = UDim.new(0, 14)
panelPadding.PaddingLeft = UDim.new(0, 14)
panelPadding.PaddingRight = UDim.new(0, 14)
panelPadding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = panel

local titleLabel = createLabel("Title", 1, 38, 36, GOLD, panel)
titleLabel.Text = "Pen"
local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
if titleStroke then
	titleStroke.Thickness = 3
end
local luckLabel = createLabel("Luck", 2, 24, 22, GREEN_TEXT, panel)

-- Sheep preview: a slowly orbiting 3D view of the sheep currently in the pen.
local previewHolder = Instance.new("Frame")
previewHolder.Name = "PreviewHolder"
previewHolder.LayoutOrder = 3
previewHolder.BackgroundTransparency = 1
previewHolder.Size = UDim2.new(1, 0, 0, 130)
previewHolder.Parent = panel

local viewport = Instance.new("ViewportFrame")
viewport.Name = "Preview"
viewport.BackgroundTransparency = 1
viewport.Size = UDim2.fromScale(1, 1)
viewport.Ambient = Color3.fromRGB(170, 170, 170)
viewport.LightColor = Color3.fromRGB(255, 255, 255)
viewport.Visible = false
viewport.Parent = previewHolder

local viewportCamera = Instance.new("Camera")
viewportCamera.FieldOfView = 40
viewportCamera.Parent = viewport
viewport.CurrentCamera = viewportCamera

local waitingLabel = Instance.new("TextLabel")
waitingLabel.Name = "WaitingLabel"
waitingLabel.BackgroundTransparency = 1
waitingLabel.Size = UDim2.fromScale(1, 1)
waitingLabel.Font = FONT
waitingLabel.TextSize = 24
waitingLabel.TextColor3 = Color3.fromRGB(170, 172, 184)
waitingLabel.Text = "A sheep is on its way..."
waitingLabel.Parent = previewHolder
addStroke(waitingLabel, 2)

local sheepLabel = createLabel("SheepLabel", 4, 26, 24, WHITE, panel)
local levelLabel = createLabel("LevelLabel", 5, 26, 26, BLUE_TEXT, panel)

-- Builds one chunky button: coloured fill, darker edge, round icon badge and an outlined label.
local function createButton(name: string, order: number, height: number, glyph: string, style: { fill: Color3, edge: Color3 })
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, height)
	button.AutoButtonColor = false
	button.Text = ""
	button.BackgroundColor3 = style.fill
	button.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Color = style.edge
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	local gloss = Instance.new("UIGradient")
	gloss.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 205, 205))
	gloss.Rotation = 90
	gloss.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 8, 0.5, 0)
	badge.Size = UDim2.fromOffset(height - 16, height - 16)
	badge.BackgroundColor3 = style.edge
	badge.Font = FONT
	badge.TextSize = math.floor(height * 0.5)
	badge.TextColor3 = WHITE
	badge.Text = glyph
	badge.Parent = button

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, height, 0, 0)
	label.Size = UDim2.new(1, -(height + 8), 1, 0)
	label.Font = FONT
	label.TextSize = math.floor(height * 0.5)
	label.TextColor3 = WHITE
	label.TextScaled = false
	label.Text = name
	label.Parent = button
	addStroke(label, 2.5)

	-- Hover / press feedback.
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

	return button, label, badge
end

local upgradeButton, upgradeLabel = createButton("Upgrade", 6, 52, "▲", BUTTON_STYLES.Upgrade)
local automateButton, automateLabel = createButton("Automate", 7, 52, "⚙", BUTTON_STYLES.Automate)
local shearButton, shearLabel = createButton("Shear", 8, 60, "▶", BUTTON_STYLES.Shear)
local sellButton, sellLabel = createButton("Sell", 9, 40, "$", BUTTON_STYLES.Sell)

screenGui.Parent = playerGui

--// Behaviour ------------------------------------------------------------------

-- "ready" = normal colours, "poor" = can't afford (muted, but still clickable so it can shake), "disabled" = greyed out.
local function setButtonState(button: TextButton, styleName: string, state: string)
	local style = BUTTON_STYLES[styleName]
	local stroke = button:FindFirstChild("Edge") :: UIStroke
	local badge = button:FindFirstChild("Badge") :: TextLabel

	if state == "ready" then
		button.BackgroundColor3 = style.fill
		stroke.Color = style.edge
		badge.BackgroundColor3 = style.edge
	elseif state == "poor" then
		button.BackgroundColor3 = style.fill:Lerp(DISABLED_FILL, 0.6)
		stroke.Color = style.edge:Lerp(DISABLED_EDGE, 0.6)
		badge.BackgroundColor3 = style.edge:Lerp(DISABLED_EDGE, 0.6)
	else
		button.BackgroundColor3 = DISABLED_FILL
		stroke.Color = DISABLED_EDGE
		badge.BackgroundColor3 = DISABLED_EDGE
	end
end

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

--// Sheep preview
local previewModel: Model? = nil
local previewType: string? = nil
local previewCenter = Vector3.zero
local previewDistance = 8
local previewAngle = 0

local function setPreview(sheepType: string?)
	if previewType == sheepType then
		return
	end
	previewType = sheepType

	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end

	local template = if sheepType then sheepTemplates:FindFirstChild(sheepType) else nil
	if not template or not template:IsA("Model") then
		viewport.Visible = false
		waitingLabel.Visible = true
		return
	end

	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("GuiBase") or descendant:IsA("ParticleEmitter") or descendant:IsA("Humanoid") or descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = viewport
	previewModel = clone

	local boxCFrame, boxSize = clone:GetBoundingBox()
	previewCenter = boxCFrame.Position
	previewDistance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(viewportCamera.FieldOfView / 2)) * 0.9

	viewport.Visible = true
	waitingLabel.Visible = false
end

runService.RenderStepped:Connect(function(deltaTime: number)
	if not visible or not previewModel then
		return
	end

	previewAngle += deltaTime * 0.9
	local orbit = Vector3.new(math.sin(previewAngle) * previewDistance, previewDistance * 0.25, math.cos(previewAngle) * previewDistance)
	viewportCamera.CFrame = CFrame.lookAt(previewCenter + orbit, previewCenter)
end)

--// Show / hide
local function updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		uiScale.Scale = math.clamp(camera.ViewportSize.Y / 720, 0.6, 1.15)
	end
end

local function show()
	hideToken += 1
	if visible then
		return
	end

	visible = true
	updateScale()
	root.Position = HIDDEN_POSITION
	screenGui.Enabled = true
	tweenService:Create(root, SLIDE_IN, { Position = SHOWN_POSITION }):Play()
end

local function hide()
	currentData = nil
	selectionHighlight.Enabled = false
	if not visible then
		return
	end

	visible = false
	hideToken += 1
	local token = hideToken

	local tween = tweenService:Create(root, SLIDE_OUT, { Position = HIDDEN_POSITION })
	tween:Play()
	tween.Completed:Connect(function()
		if token == hideToken and not visible then
			screenGui.Enabled = false
		end
	end)
end

-- Fills the card in from the server's menu data.
local function render(data: any)
	currentData = data

	if data.penModel and selectionHighlight.Adornee ~= data.penModel then
		selectionHighlight.Adornee = data.penModel
	end
	selectionHighlight.Enabled = data.penModel ~= nil

	titleLabel.Text = data.penName or "Pen"
	luckLabel.Text = `Rare sheep luck  x{string.format("%.2f", data.luck or 1)}`
	levelLabel.Text = `Level {data.level} / {data.maxLevel}`

	if data.sheepReady and data.sheepType then
		setPreview(data.sheepType)
		local rarityColor: Color3 = data.rarityColor or WHITE
		sheepLabel.TextColor3 = rarityColor:Lerp(WHITE, 0.45)
		sheepLabel.Text = `{data.sheepName} - {data.rarity}`
	else
		setPreview(nil)
		sheepLabel.Text = ""
	end

	-- Upgrade
	if data.upgradeCost then
		upgradeLabel.Text = `Upgrade  {formatMoney(data.upgradeCost)}`
		setButtonState(upgradeButton, "Upgrade", if data.canAffordUpgrade then "ready" else "poor")
	else
		upgradeLabel.Text = "MAX LEVEL"
		setButtonState(upgradeButton, "Upgrade", "disabled")
	end

	-- Automate (hire a worker)
	if data.workerHired then
		automateLabel.Text = "Automated ✓"
		setButtonState(automateButton, "Automate", "disabled")
	else
		automateLabel.Text = `Automate  {formatMoney(data.workerCost)}`
		setButtonState(automateButton, "Automate", if data.canAffordWorker then "ready" else "poor")
	end

	-- Start shearing
	if data.sheepReady then
		shearLabel.Text = if data.sheepDamaged then "CONTINUE SHEARING" else "START SHEARING"
		setButtonState(shearButton, "Shear", "ready")
	else
		shearLabel.Text = "WAITING FOR SHEEP..."
		setButtonState(shearButton, "Shear", "disabled")
	end

	-- Sell (only when allowed, to keep the card simple)
	sellButton.Visible = data.canSell == true
	sellLabel.Text = `Sell Pen  +{formatMoney(data.sellValue or 0)}`
	setButtonState(sellButton, "Sell", "ready")

	show()
end

--// Button presses ---------------------------------------------------------------

upgradeButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or not data.upgradeCost then
		return
	end
	if not data.canAffordUpgrade then
		shake(upgradeButton)
		return
	end
	network.fireServer(network.RemoteEvents.UpgradePen, data.penId)
end)

automateButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or data.workerHired then
		return
	end
	if not data.canAffordWorker then
		shake(automateButton)
		return
	end
	network.fireServer(network.RemoteEvents.HireWorker, data.penId)
end)

shearButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data then
		return
	end
	if not data.sheepReady then
		shake(shearButton)
		return
	end
	network.fireServer(network.RemoteEvents.StartShearing, data.penId)
end)

sellButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or not data.canSell then
		return
	end
	network.fireServer(network.RemoteEvents.SellPen, data.penId)
end)

--// Server events -------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.OpenPenMenu, render)
network.connectEvent(network.RemoteEvents.ClosePenMenu, hide)
-- Hide instantly when shearing begins rather than waiting for the server's next close message.
network.connectEvent(network.RemoteEvents.ActivateShearing, hide)
