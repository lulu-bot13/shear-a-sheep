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
		      ├─ Hire [TextButton]       "Hire: 1k" / "Hired"
		      └─ Shear [TextButton]      "[E] Shear" - E on the keyboard does the same

	Manage (opens the pen manager, PenManageClient) and Sell (newest pen only) are not part of the Studio
	layout. If Buttons has TextButtons named `Manage` and `Sell` they are used; otherwise a row with those
	two is added under Shear, styled like Shear, and Main is made taller to fit it.

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
local SELL_FILL = Color3.fromRGB(232, 78, 88)
local MANAGE_FILL = Color3.fromRGB(150, 110, 235)
local SLIDE_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SHEAR_ACTION = "PenMenuShear"

-- Where the menu rests (as built in Studio) and where it waits, off the right edge of the screen.
local SHOWN_POSITION = main.Position
local HIDDEN_POSITION = main.Position + UDim2.new(0.4, 40, 0, 0)

--// State
local currentData: any = nil
local visible = false
local hideToken = 0

--// Helpers ------------------------------------------------------------------

-- 999 -> "999", 1500 -> "1.5k", 2000000 -> "2M"
local function formatMoney(amount: number): string
	local function trim(value: number, suffix: string): string
		local text = string.format("%.1f", value)
		return (string.gsub(text, "%.0$", "")) .. suffix
	end

	if amount >= 1e9 then
		return trim(amount / 1e9, "B")
	elseif amount >= 1e6 then
		return trim(amount / 1e6, "M")
	elseif amount >= 1e3 then
		return trim(amount / 1e3, "k")
	end
	return tostring(math.floor(amount))
end

--// Buttons ------------------------------------------------------------------

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

--[[
	Manage and Sell: use TextButtons of those names if the Buttons frame already has them, otherwise add a
	row below Shear with a copy of the Shear button for each. A new row takes height, so Main and Buttons
	grow by that much and everything above keeps its pixel position.
]]--
local function findOrCreateExtraButtons(): (ButtonInfo, ButtonInfo)
	local existingManage = buttonsFrame:FindFirstChild("Manage")
	local existingSell = buttonsFrame:FindFirstChild("Sell")
	if existingManage and existingManage:IsA("TextButton") and existingSell and existingSell:IsA("TextButton") then
		return makeInteractive(existingManage), makeInteractive(existingSell)
	end

	local layout = buttonsFrame:FindFirstChildOfClass("UIListLayout")
	local row = Instance.new("Frame")
	row.Name = "Extra"
	row.BackgroundTransparency = 1
	row.Size = shearButton.Size
	row.LayoutOrder = 100
	row.Parent = buttonsFrame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 8)
	rowLayout.Parent = row

	local function copyOfShear(name: string, text: string, fill: Color3, order: number): TextButton
		local copy = shearButton:Clone()
		copy.Name = name
		copy.Text = text
		copy.BackgroundColor3 = fill
		copy.LayoutOrder = order
		copy.Size = UDim2.new(0.5, -4, 1, 0)
		for _, child in copy:GetChildren() do
			if child:IsA("UIScale") then
				child:Destroy()
			end
		end
		copy.Parent = row
		return copy
	end

	local manageButton = copyOfShear("Manage", "Manage", MANAGE_FILL, 1)
	local sellButton = copyOfShear("Sell", "Sell", SELL_FILL, 2)

	-- Make room for the row (only possible when Main's height is a plain pixel size).
	local oldHeight = main.Size.Y.Offset
	if main.Size.Y.Scale == 0 and oldHeight > 0 then
		local gap = if layout then layout.Padding.Offset + layout.Padding.Scale * buttonsFrame.Size.Y.Offset else 8
		local growth = shearButton.Size.Y.Offset + gap
		local newHeight = oldHeight + growth

		for _, child in { titleLabel, preview, buttonsFrame } do
			local position = child.Position
			child.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale * oldHeight / newHeight, position.Y.Offset)
		end
		buttonsFrame.Size = UDim2.new(buttonsFrame.Size.X.Scale, buttonsFrame.Size.X.Offset, buttonsFrame.Size.Y.Scale, buttonsFrame.Size.Y.Offset + growth)
		main.Size = UDim2.new(main.Size.X.Scale, main.Size.X.Offset, main.Size.Y.Scale, newHeight)
	end

	return makeInteractive(manageButton, MANAGE_FILL), makeInteractive(sellButton, SELL_FILL)
end

local manage, sell = findOrCreateExtraButtons()

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
		hireButton.Text = "Hired"
		setButtonState(hire, "disabled")
	else
		hireButton.Text = `Hire: {formatMoney(data.workerCost)}`
		setButtonState(hire, if data.canAffordWorker then "ready" else "poor")
	end

	-- Start shearing
	if data.sheepReady then
		shearButton.Text = if data.sheepDamaged then "[E] Continue" else "[E] Shear"
		setButtonState(shear, "ready")
	else
		shearButton.Text = "Waiting for sheep..."
		setButtonState(shear, "disabled")
	end

	-- Sell is only offered for the newest pen; Manage takes the whole row when it isn't.
	local canSell = data.canSell == true
	sell.button.Visible = canSell
	sell.button.Text = `Sell +{formatMoney(data.sellValue or 0)}`
	setButtonState(sell, "ready")
	if sell.button.Parent == manage.button.Parent and manage.button.Parent ~= buttonsFrame then
		manage.button.Size = if canSell then UDim2.new(0.5, -4, 1, 0) else UDim2.new(1, 0, 1, 0)
	end
	setButtonState(manage, "ready")

	show()
end

--// Button presses ---------------------------------------------------------------

local function pressShear()
	local data = currentData
	if not data then
		return
	end
	if not data.sheepReady then
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

hireButton.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or data.workerHired then
		return
	end
	if not data.canAffordWorker then
		shake(hireButton)
		return
	end
	network.fireServer(network.RemoteEvents.HireWorker, data.penId)
end)

shearButton.MouseButton1Click:Connect(pressShear)

sell.button.MouseButton1Click:Connect(function()
	local data = currentData
	if not data or not data.canSell then
		return
	end
	network.fireServer(network.RemoteEvents.SellPen, data.penId)
end)

--// Pen manager (PenManageClient) -----------------------------------------------------

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
local manageClosed = getBindable("ManagePenClosed")

-- The manager takes over the screen, so the menu steps aside while it is open.
manage.button.MouseButton1Click:Connect(function()
	local data = currentData
	if not data then
		return
	end

	penMenuGui.Enabled = false
	manageRequest:Fire(data)
end)

manageClosed.Event:Connect(function()
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
