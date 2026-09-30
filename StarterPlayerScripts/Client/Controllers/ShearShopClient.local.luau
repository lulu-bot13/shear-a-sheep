--[[
	The shear shop UI (StarterGui.Shop).

	Pressing any ProximityPrompt tagged "ShearShop" opens the shop. Each shear in
	ShearShopUIData gets a card cloned from the Template: name, speed / damage, a spinning
	3D preview and a purchase button. Buying is validated by the server (ShearShopHandler);
	the cards update from the player's "ShearId" attribute and Money.

	Performance: the previews are built once (on first open), and ONE render connection
	exists only while the shop is open. It turns each preview by moving its ViewportFrame
	camera (no model is moved) and skips cards scrolled out of view.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearShopClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local UIData = require(script.Parent.Parent.Modules.ShearShopUIData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shearTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Shears")
local shopGui = playerGui:WaitForChild("Shop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: Frame
local scrollFrame = mainFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local cardTemplate = scrollFrame:WaitForChild("Template") :: Frame
local closeButton = mainFrame:WaitForChild("Close") :: TextButton
local money = player:WaitForChild("leaderstats"):WaitForChild("Money") :: IntValue

--// Configs
local SHOP_PROMPT_TAG = "ShearShop"
local CLOSE_DISTANCE_EXTRA = 6 -- studs past the prompt's activation range before the shop closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local MESSAGE_SECONDS = 1.3
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local REASON_TEXT = {
	NoMoney = "Not enough money",
	TooFar = "Too far away",
	Owned = "Already owned",
	Busy = "Finish shearing first",
}

type Card = {
	info: any,
	frame: Frame,
	purchase: TextButton,
	viewport: ViewportFrame?,
	camera: Camera?,
	center: Vector3,
	distance: number,
	messageToken: number,
}

--// State
local cards: { Card } = {}
local cardById: { [string]: Card } = {}
local previewsBuilt = false
local activePrompt: ProximityPrompt? = nil
local renderConnection: RBXScriptConnection? = nil
local openToken = 0
local spinAngle = 0

local openScale = Instance.new("UIScale")
openScale.Parent = mainFrame

--// Helpers ---------------------------------------------------------------------

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function getCurrentRank(): number
	return UIData.getRank(player:GetAttribute("ShearId") or "DefaultShear")
end

local function getState(card: Card): string
	local rank = UIData.getRank(card.info.id)
	local currentRank = getCurrentRank()
	if rank == currentRank then
		return "equipped"
	elseif rank < currentRank then
		return "owned"
	elseif money.Value >= card.info.price then
		return "ready"
	end
	return "poor"
end

local function refreshCard(card: Card)
	local state = getState(card)
	local colors = UIData.ButtonColors

	if state == "equipped" then
		card.purchase.Text = "Equipped"
		card.purchase.BackgroundColor3 = colors.Equipped
	elseif state == "owned" then
		card.purchase.Text = "Owned"
		card.purchase.BackgroundColor3 = colors.Owned
	else
		card.purchase.Text = `Purchase - {UIData.formatMoney(card.info.price)}`
		card.purchase.BackgroundColor3 = if state == "ready" then colors.Ready else colors.Poor
	end

	card.purchase:SetAttribute("State", state)
end

local function refreshAll()
	for _, card in cards do
		card.messageToken += 1 -- a pending message must not overwrite the fresh text
		refreshCard(card)
	end
end

-- Shows a short message on a card's button, then goes back to its normal text.
local function flashMessage(card: Card, text: string)
	card.messageToken += 1
	local token = card.messageToken
	card.purchase.Text = text
	shake(card.purchase)

	task.delay(MESSAGE_SECONDS, function()
		if token == card.messageToken then
			refreshCard(card)
		end
	end)
end

--// Cards & previews ---------------------------------------------------------------

-- Sizes the scroll frame's canvas (Y) to fit every card plus the frame's own padding.
local function updateCanvasSize()
	local layout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end

	local padding = scrollFrame:FindFirstChildOfClass("UIPadding")
	local paddingY = 0
	if padding then
		local frameHeight = scrollFrame.AbsoluteSize.Y
		paddingY = padding.PaddingTop.Offset + padding.PaddingTop.Scale * frameHeight
			+ padding.PaddingBottom.Offset + padding.PaddingBottom.Scale * frameHeight
	end

	scrollFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + paddingY)
end

local function createCards()
	cardTemplate.Visible = false
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None

	-- Every card added re-fits the canvas. The layout only measures its content after the child lands, so the
	-- refresh is deferred; the size-changed hook keeps it right when the window is resized too.
	scrollFrame.ChildAdded:Connect(function(child: Instance)
		if child:IsA("GuiObject") then
			task.defer(updateCanvasSize)
		end
	end)

	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
	end

	for index, info in UIData.Shears do
		local frame = cardTemplate:Clone()
		frame.Name = info.id
		frame.LayoutOrder = index
		frame.Visible = true

		local nameLabel = frame:WaitForChild("ShearName") :: TextLabel
		local buffsLabel = frame:WaitForChild("Buffs") :: TextLabel
		local purchase = frame:WaitForChild("Purchase") :: TextButton

		nameLabel.Text = info.displayName
		buffsLabel.Text = `Speed: x{string.format("%.2f", info.speed)}\nDamage: {info.damage}`
		purchase.AutoButtonColor = true

		local card: Card = {
			info = info,
			frame = frame,
			purchase = purchase,
			viewport = nil,
			camera = nil,
			center = Vector3.zero,
			distance = 5,
			messageToken = 0,
		}
		table.insert(cards, card)
		cardById[info.id] = card

		purchase.MouseButton1Click:Connect(function()
			local state = getState(card)
			if state == "ready" then
				network.fireServer(network.RemoteEvents.PurchaseShear, info.id)
			elseif state == "poor" then
				flashMessage(card, REASON_TEXT.NoMoney)
			else
				shake(purchase)
			end
		end)

		frame.Parent = scrollFrame
	end

	updateCanvasSize()
end

-- Builds the ViewportFrame + model for one card. Only geometry is kept (no scripts, VFX or animation rigs).
local function buildPreview(card: Card)
	local template = shearTemplates:FindFirstChild(card.info.id)
	local holder = card.frame:FindFirstChild("ShearImage")
	if not template or not holder then
		return
	end

	local tool = template:Clone()
	local model = Instance.new("Model")
	model.Name = card.info.id

	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") then
			for _, descendant in child:GetDescendants() do
				if not (descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint")) then
					descendant:Destroy()
				end
			end
			child.Anchored = true
			child.Parent = model
		end
	end
	tool:Destroy()

	model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart?
	model:PivotTo(CFrame.new())

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -1)

	local camera = Instance.new("Camera")
	camera.FieldOfView = UIData.PreviewFieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	model.Parent = viewport
	viewport.Parent = holder

	local boxCFrame, boxSize = model:GetBoundingBox()
	card.center = boxCFrame.Position
	card.distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	card.viewport = viewport
	card.camera = camera

	camera.CFrame = CFrame.lookAt(card.center + Vector3.new(0, 0, card.distance), card.center)
end

local function buildPreviews()
	if previewsBuilt then
		return
	end
	previewsBuilt = true

	for _, card in cards do
		buildPreview(card)
	end
end

-- Spins every visible preview: orbits its camera round the shear (one connection for all cards).
local function onRender(deltaTime: number)
	spinAngle = (spinAngle + deltaTime * UIData.SpinSpeed) % (math.pi * 2)

	local pitch = UIData.PreviewPitch
	local flat = math.cos(pitch)
	local viewTop = scrollFrame.AbsolutePosition.Y
	local viewBottom = viewTop + scrollFrame.AbsoluteSize.Y

	for _, card in cards do
		local viewport, camera = card.viewport, card.camera
		if not viewport or not camera then
			continue
		end

		-- Scrolled out of view: nothing to draw, so don't touch it.
		local top = viewport.AbsolutePosition.Y
		if top > viewBottom or top + viewport.AbsoluteSize.Y < viewTop then
			continue
		end

		local offset = Vector3.new(math.sin(spinAngle) * flat, math.sin(pitch), math.cos(spinAngle) * flat) * card.distance
		camera.CFrame = CFrame.lookAt(card.center + offset, card.center)
	end
end

--// Open / close ------------------------------------------------------------------

local function getPromptPosition(prompt: ProximityPrompt): Vector3?
	local holder = prompt.Parent
	if holder and holder:IsA("BasePart") then
		return holder.Position
	elseif holder and holder:IsA("Attachment") then
		return holder.WorldPosition
	end
	return nil
end

local function closeShop()
	if not shopGui.Enabled then
		return
	end

	openToken += 1
	activePrompt = nil
	shopGui.Enabled = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function openShop(prompt: ProximityPrompt)
	activePrompt = prompt
	if shopGui.Enabled then
		return
	end

	openToken += 1
	local token = openToken

	buildPreviews()
	refreshAll()

	openScale.Scale = 0.85
	shopGui.Enabled = true
	tweenService:Create(openScale, OPEN_TWEEN, { Scale = 1 }):Play()

	renderConnection = runService.RenderStepped:Connect(onRender)

	-- Walk away from the NPC and the shop closes itself.
	task.spawn(function()
		while token == openToken do
			local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local current = activePrompt
			local promptPosition = if current then getPromptPosition(current) else nil
			if not rootPart or not current or not promptPosition then
				closeShop()
				return
			end

			if (rootPart.Position - promptPosition).Magnitude > current.MaxActivationDistance + CLOSE_DISTANCE_EXTRA then
				closeShop()
				return
			end
			task.wait(DISTANCE_CHECK_SECONDS)
		end
	end)
end

local function connectPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end

	instance.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == player then
			if shopGui.Enabled then
				closeShop()
			else
				openShop(instance)
			end
		end
	end)
end

--// Setup ---------------------------------------------------------------------------

createCards()
shopGui.Enabled = false

closeButton.MouseButton1Click:Connect(closeShop)

money.Changed:Connect(function()
	if shopGui.Enabled then
		refreshAll()
	end
end)

player:GetAttributeChangedSignal("ShearId"):Connect(function()
	if shopGui.Enabled then
		refreshAll()
	end
end)

for _, instance in collectionService:GetTagged(SHOP_PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(connectPrompt)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShearPurchaseResult, function(id: string, success: boolean, reason: string?)
	local card = cardById[id]
	if not card then
		return
	end

	if success then
		refreshAll()
		local scale = card.frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = card.frame
		end
		scale.Scale = 1.06
		tweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		flashMessage(card, REASON_TEXT[reason or ""] or "Can't buy")
	end
end)

-- Shearing started: the shop must not stay up over the mini-game.
network.connectEvent(network.RemoteEvents.ActivateShearing, closeShop)
