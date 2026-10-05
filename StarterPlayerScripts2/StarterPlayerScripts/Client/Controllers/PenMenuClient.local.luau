--[[
	The pen menu, shown on the right of the screen while the player stands at one of their pens (the
	server opens/closes it as they walk up and away). It drives the hand-built `PenMenu` ScreenGui
	(StarterGui.PenMenu). The names this script looks for:

		PenMenu [ScreenGui]
		└─ Main [Frame]
		   ├─ Title [TextLabel]          "Basic Sheep - Common" / "Waiting for sheep..."
		   ├─ Preview [ViewportFrame]    spinning 3D sheep (its own Camera child is used if there is one)
		   └─ Buttons [Frame]            UIListLayout
		      ├─ Upgrade [TextButton]    "Upgrade: 1k" / "Max Level"
		      ├─ Hire [TextButton]       "Hire (2)" = unused workers / red "Remove" when the pen has a worker
		      └─ Shear [TextButton]      "[E] Shear" - E on the keyboard does the same

	Sell (newest pen only) and a Luck line ("Luck: x1.25 > x2") are not part of the Studio layout. A
	TextButton `Sell` and a TextLabel `Luck` in Buttons are used if present; otherwise they are added
	(Sell under Shear, styled like it, Luck above Upgrade) and Main is made taller to fit them.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PenMenuClient
]]--

--// Services
local contextActionService = game:GetService("ContextActionService")
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

local penMenuGui = playerGui:WaitForChild("PenMenu") :: ScreenGui
local main = penMenuGui:WaitForChild("Main") :: Frame
local titleLabel = main:WaitForChild("Title") :: TextLabel
local preview = main:WaitForChild("Preview") :: ViewportFrame
local buttonsFrame = main:WaitForChild("Buttons") :: Frame
local upgradeButton = buttonsFrame:WaitForChild("Upgrade") :: TextButton
local hireButton = buttonsFrame:WaitForChild("Hire") :: TextButton
local shearButton = buttonsFrame:WaitForChild("Shear") :: TextButton

-- The script keeps references into this GUI for the whole session, so it must survive respawns.
penMenuGui.ResetOnSpawn = false

--// Style
local GOLD = Color3.fromRGB(255, 176, 32)
local WHITE = Color3.new(1, 1, 1)
local DISABLED_FILL = Color3.fromRGB(96, 99, 110)
local REMOVE_FILL = Color3.fromRGB(232, 78, 88)
local SELL_FILL = Color3.fromRGB(232, 78, 88)
local LUCK_COLOR = "#7CFF8A" -- the luck an upgrade would give
local SLIDE_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHEAR_ACTION = "PenMenuShear"

-- Where the menu rests (as built in Studio) and where it waits, off the right edge of the screen.
local SHOWN_POSITION = main.Position
local HIDDEN_POSITION = main.Position + UDim2.new(0.4, 40, 0, 0)

--// State
local currentData: any = nil
local visible = false
local hideToken = 0

--// Helpers ------------------------------------------------------------------

-- 1500 -> "$1,500"
local function formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. formatted:gsub("^,", "")
end

--// Buttons ------------------------------------------------------------------

-- 1.6 -> "x1.6", 2 -> "x2"
local function formatLuck(luck: number): string
	return "x" .. (string.format("%.2f", luck):gsub("%.?0+$", ""))
end

type ButtonInfo = {
	button: TextButton,
	fill: Color3, -- the colour the button has in Studio
	scale: UIScale,
}

-- Hover / press feedback, and remembers the button's own colour so states can dim it.
local function makeInteractive(button: TextButton, fill: Color3?): ButtonInfo
	local scale = Instance.new("UIScale")
	scale.Parent = button

	local function tweenScale(target: number)
		tweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = target }):Play()
	end
	button.MouseEnter:Connect(function()
		tweenScale(1.04)
	end)
	button.MouseLeave:Connect(function()
		tweenScale(1)
	end)
	button.MouseButton1Down:Connect(function()
		print(`Pressing on {button.Name}`)
		tweenScale(0.96)
	end)
	button.MouseButton1Up:Connect(function()
		tweenScale(1.04)
	end)

	return { button = button, fill = fill or button.BackgroundColor3, scale = scale }
end

-- "ready" = its own colour, "poor" = can't afford (muted, still clickable so it can shake), "disabled" = greyed out.
local function setButtonState(info: ButtonInfo, state: string)
	if state == "ready" then
		info.button.BackgroundColor3 = info.fill
	elseif state == "poor" then
		info.button.BackgroundColor3 = info.fill:Lerp(DISABLED_FILL, 0.6)
	else
		info.button.BackgroundColor3 = DISABLED_FILL
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

local upgrade = makeInteractive(upgradeButton)
local hire = makeInteractive(hireButton)
local shear = makeInteractive(shearButton)

local buttonsLayout = buttonsFrame:FindFirstChildOfClass("UIListLayout")
if buttonsLayout then
	buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
end

-- A new row takes height (only possible when Main's height is a plain pixel size): Main and Buttons grow by it.
local function makeRoomForRow(rowHeight: number)
	local oldHeight = main.Size.Y.Offset
	if main.Size.Y.Scale ~= 0 or oldHeight <= 0 then
		return
	end

	local gap = if buttonsLayout then buttonsLayout.Padding.Offset + buttonsLayout.Padding.Scale * buttonsFrame.Size.Y.Offset else 8
	local growth = rowHeight + gap
	local newHeight = oldHeight + growth

	for _, child in { titleLabel, preview, buttonsFrame } do
		local position = child.Position
		child.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale * oldHeight / newHeight, position.Y.Offset)
	end
	buttonsFrame.Size = UDim2.new(buttonsFrame.Size.X.Scale, buttonsFrame.Size.X.Offset, buttonsFrame.Size.Y.Scale, buttonsFrame.Size.Y.Offset + growth)
	main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, main.Size.Y.Scale, newHeight)
end

--[[
	Sell and the luck line are not part of the Studio layout. A TextButton named `Sell` and a TextLabel
	named `Luck` in Buttons are used if they exist; otherwise Sell is added under Shear (a copy of Shear)
	and Luck above Upgrade, and Main grows to fit them.
]]--
local function findOrCreateSell(): ButtonInfo
	local existing = buttonsFrame:FindFirstChild("Sell")
	if existing and existing:IsA("TextButton") then
		return makeInteractive(existing)
	end

	local copy = shearButton:Clone()
	copy.Name = "Sell"
	copy.Text = "Sell"
	copy.BackgroundColor3 = SELL_FILL
	copy.LayoutOrder = 100
	for _, child in copy:GetChildren() do
		if child:IsA("UIScale") then
			child:Destroy()
		end
	end
	copy.Parent = buttonsFrame
	makeRoomForRow(shearButton.Size.Y.Offset)

	return makeInteractive(copy, SELL_FILL)
end

local function findOrCreateLuckLabel(): TextLabel
	local existing = buttonsFrame:FindFirstChild("Luck")
	if existing and existing:IsA("TextLabel") then
		return existing
	end

	local label = Instance.new("TextLabel")
	label.Name = "Luck"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 26)
	label.LayoutOrder = -1
	label.Font = shearButton.Font
	label.TextSize = 20
	label.TextColor3 = WHITE
	label.RichText = true
	label.Parent = buttonsFrame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label

	makeRoomForRow(26)
	return label
end

local sell = findOrCreateSell()
local luckLabel = findOrCreateLuckLabel()

main.Position = HIDDEN_POSITION
penMenuGui.Enabled = false

-- One highlight for the whole session: selecting a pen just points it at that pen's model
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

--// Sheep preview ----------------------------------------------------------------

local viewportCamera = preview:FindFirstChildOfClass("Camera")
if not viewportCamera then
	viewportCamera = Instance.new("Camera")
	viewportCamera.Parent = preview
end
viewportCamera.FieldOfView = 40
preview.CurrentCamera = viewportCamera

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
		return
	end

	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("GuiBase") or descendant:IsA("ParticleEmitter") or descendant:IsA("Humanoid") or descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = preview
	previewModel = clone

	local boxCFrame, boxSize = clone:GetBoundingBox()
	previewCenter = boxCFrame.Position
	previewDistance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(viewportCamera.FieldOfView / 2)) * 0.9
end

runService.RenderStepped:Connect(function(deltaTime: number)
	if not visible or not previewModel then
		return
	end

	previewAngle += deltaTime * 0.9
	local orbit = Vector3.new(math.sin(previewAngle) * previewDistance, previewDistance * 0.25, math.cos(previewAngle) * previewDistance)
	viewportCamera.CFrame = CFrame.lookAt(previewCenter + orbit, previewCenter)
end)

--// Show / hide --------------------------------------------------------------------

local onShearKey: (string, Enum.UserInputState) -> Enum.ContextActionResult

local function show()
	hideToken += 1
	if visible then
		return
	end

	visible = true
	main.Position = HIDDEN_POSITION
	penMenuGui.Enabled = true
	tweenService:Create(main, SLIDE_IN, { Position = SHOWN_POSITION }):Play()

	-- E does what the Shear button says it does.
	contextActionService:BindAction(SHEAR_ACTION, onShearKey, false, Enum.KeyCode.E)
end

local function hide()
	currentData = nil
	selectionHighlight.Enabled = false
	contextActionService:UnbindAction(SHEAR_ACTION)
	if not visible then
		return
	end

	visible = false
	hideToken += 1
	local token = hideToken

	local tween = tweenService:Create(main, SLIDE_OUT, { Position = HIDDEN_POSITION })
	tween:Play()
	tween.Completed:Connect(function()
		if token == hideToken and not visible then
			penMenuGui.Enabled = false
		end
	end)
end

-- Fills the menu in from the server's menu data.
local function render(data: any)
	currentData = data

	if data.penModel and selectionHighlight.Adornee ~= data.penModel then
		selectionHighlight.Adornee = data.penModel
	end
	selectionHighlight.Enabled = data.penModel ~= nil

	if data.sheepReady and data.sheepType then
		setPreview(data.sheepType)
		local rarityColor: Color3 = data.rarityColor or WHITE
		titleLabel.TextColor3 = rarityColor:Lerp(WHITE, 0.45)
		titleLabel.Text = `{data.sheepName} - {data.rarity}`
	else
		setPreview(nil)
		titleLabel.TextColor3 = WHITE
		titleLabel.Text = "Waiting for sheep..."
	end

	-- Upgrade
	if data.upgradeCost then
		upgradeButton.Text = `Upgrade: {formatMoney(data.upgradeCost)}`
		setButtonState(upgrade, if data.canAffordUpgrade then "ready" else "poor")
	else
		upgradeButton.Text = "Max Level"
		setButtonState(upgrade, "disabled")
	end

	-- Hire a worker (automation)
	if data.workerHired then
		hireButton.Text = "Remove"
		hireButton.BackgroundColor3 = REMOVE_FILL
	else
		-- With no unused worker the button still works: it opens the Hire Workers screen.
		hireButton.Text = `Hire ({data.workersAvailable})`
		setButtonState(hire, if data.workersAvailable > 0 then "ready" else "poor")
	end

	-- Start shearing
	if data.workerHired then
		shearButton.Text = "Worker is shearing"
		setButtonState(shear, "disabled")
	elseif data.sheepReady then
		shearButton.Text = if data.sheepDamaged then "[E] Continue" else "[E] Shear"
		setButtonState(shear, "ready")
	else
		shearButton.Text = "Waiting for sheep..."
		setButtonState(shear, "disabled")
	end

	-- Sell is only offered for the newest pen.
	sell.button.Visible = data.canSell == true
	sell.button.Text = `Sell +{formatMoney(data.sellValue or 0)}`
	setButtonState(sell, "ready")

	-- Luck: what the pen has now, and what the next upgrade makes it.
	if data.nextLuck then
		luckLabel.Text = `Luck: {formatLuck(data.luck)} <font color="{LUCK_COLOR}">→ {formatLuck(data.nextLuck)}</font>`
	else
		luckLabel.Text = `Luck: {formatLuck(data.luck)} (max)`
	end

	show()
end

--// Button presses ---------------------------------------------------------------

local function pressShear()
	local data = currentData
	if not data then
		return
	end
	if data.workerHired or not data.sheepReady then
		shake(shearButton)
		return
	end
	network.fireServer(network.RemoteEvents.StartShearing, data.penId)
end

onShearKey = function(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin or not penMenuGui.Enabled then
		return Enum.ContextActionResult.Pass
	end
	pressShear()
	return Enum.ContextActionResult.Sink
end

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

shearButton.MouseButton1Click:Connect(pressShear)

sell.button.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or not data.canSell then
		return
	end
	network.fireServer(network.RemoteEvents.SellPen, data.penId)
end)

--// Hire Workers screen (HireWorkersClient) --------------------------------------------

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

local openHireWorkers = getBindable("OpenHireWorkers")
local hireWorkersClosed = getBindable("HireWorkersClosed")

hireButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data then
		return
	end
	if data.workerHired then
		network.fireServer(network.RemoteEvents.RemoveWorker, data.penId)
		return
	end
	-- Nobody free to send to the pen: go and hire one.
	if data.workersAvailable <= 0 then
		penMenuGui.Enabled = false
		openHireWorkers:Fire(data.penId) -- a worker bought there goes straight onto this pen
		return
	end
	network.fireServer(network.RemoteEvents.HireWorker, data.penId)
end)

-- The Hire Workers screen takes over while it is open, so the menu steps aside.
hireWorkersClosed.Event:Connect(function()
	if visible then
		penMenuGui.Enabled = true
	end
end)

--// Server events -------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.OpenPenMenu, render)
network.connectEvent(network.RemoteEvents.ClosePenMenu, hide)
-- Hide instantly when shearing begins rather than waiting for the server's next close message.
network.connectEvent(network.RemoteEvents.ActivateShearing, hide)
