--[[
	The pen shop UI (StarterGui.PenShop).

	Pressing any ProximityPrompt tagged "PenShop" opens the shop. Each pen style in PenShopUIData gets a card
	cloned from the Template: a large spinning 3D preview, its name, a short description and a button.
	Pressing the button opens the purchase options (pay with money or Robux) for styles the player doesn't own
	yet, or equips a style they already own. The server (PenShopHandler) validates everything.

	Performance: previews are built once (on first open) and ONE render connection exists only while the shop
	is open. It turns each preview by moving its ViewportFrame camera and skips cards scrolled out of view.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PenShopClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local UIData = require(script.Parent.Parent.Modules.PenShopUIData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local penTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Pens")
local shopGui = playerGui:WaitForChild("PenShop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: Frame
local scrollFrame = mainFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local cardTemplate = scrollFrame:WaitForChild("Template") :: Frame
local closeButton = mainFrame:WaitForChild("Close") :: TextButton
local optionsFrame = mainFrame:WaitForChild("Options") :: Frame
local optionsPanel = optionsFrame:WaitForChild("Panel") :: Frame
local optionsItemName = optionsPanel:WaitForChild("ItemName") :: TextLabel
local moneyButton = optionsPanel:WaitForChild("MoneyButton") :: TextButton
local robuxButton = optionsPanel:WaitForChild("RobuxButton") :: TextButton
local cancelButton = optionsPanel:WaitForChild("Cancel") :: TextButton
local money = player:WaitForChild("leaderstats"):WaitForChild("Money") :: IntValue

--// Configs
local SHOP_PROMPT_TAG = "PenShop"
local CLOSE_DISTANCE_EXTRA = 6 -- studs past the prompt's activation range before the shop closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local MESSAGE_SECONDS = 1.3
local OWNED_ATTRIBUTE = "OwnedPenSkins"
local EQUIPPED_ATTRIBUTE = "PenSkinId"
local DEFAULT_SKIN_ID = "Base_Pen"
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local REASON_TEXT = {
	NoMoney = "Not enough money",
	TooFar = "Too far away",
	Owned = "Already owned",
	NotOwned = "Not owned yet",
	RobuxUnavailable = "Robux coming soon",
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
local optionsCard: Card? = nil
local optionsToken = 0

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

local function isOwned(id: string): boolean
	if id == DEFAULT_SKIN_ID then
		return true
	end
	local raw = player:GetAttribute(OWNED_ATTRIBUTE)
	if type(raw) ~= "string" then
		return false
	end
	for owned in string.gmatch(raw, "[^,]+") do
		if owned == id then
			return true
		end
	end
	return false
end

local function getEquipped(): string
	return player:GetAttribute(EQUIPPED_ATTRIBUTE) or DEFAULT_SKIN_ID
end

local function getState(card: Card): string
	if card.info.id == getEquipped() then
		return "equipped"
	elseif isOwned(card.info.id) then
		return "owned"
	elseif money.Value >= card.info.price then
		return "ready"
	end
	return "poor"
end

local function refreshOptions()
	local card = optionsCard
	if not card then
		return
	end

	local colors = UIData.ButtonColors
	local info = card.info
	optionsItemName.Text = info.displayName

	moneyButton.Text = `Buy with Money - {UIData.formatMoney(info.price)}`
	moneyButton.BackgroundColor3 = if money.Value >= info.price then colors.Ready else colors.Poor

	if info.robuxAvailable then
		robuxButton.Text = `Buy with Robux - R$ {info.robux}`
		robuxButton.BackgroundColor3 = colors.Robux
	else
		robuxButton.Text = `Robux - R$ {info.robux} (coming soon)`
		robuxButton.BackgroundColor3 = colors.Disabled
	end
end

local function refreshCard(card: Card)
	local state = getState(card)
	local colors = UIData.ButtonColors

	if state == "equipped" then
		card.purchase.Text = "Equipped"
		card.purchase.BackgroundColor3 = colors.Equipped
	elseif state == "owned" then
		card.purchase.Text = "Equip"
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
	refreshOptions()
end

-- Shows a short message on a button, then goes back to its normal text.
local function flashMessage(button: TextButton, text: string, restore: () -> ())
	local token = (button:GetAttribute("MessageToken") or 0) + 1
	button:SetAttribute("MessageToken", token)
	button.Text = text
	shake(button)

	task.delay(MESSAGE_SECONDS, function()
		if button:GetAttribute("MessageToken") == token then
			restore()
		end
	end)
end

--// Purchase options ------------------------------------------------------------

local function closeOptions()
	optionsCard = nil
	optionsToken += 1
	optionsFrame.Visible = false
end

local function openOptions(card: Card)
	optionsCard = card
	optionsToken += 1
	moneyButton:SetAttribute("MessageToken", 0)
	robuxButton:SetAttribute("MessageToken", 0)
	refreshOptions()
	optionsFrame.Visible = true
end

--// Cards & previews ---------------------------------------------------------------

local function createCards()
	cardTemplate.Visible = false
	optionsFrame.Visible = false

	for index, info in UIData.Pens do
		local frame = cardTemplate:Clone()
		frame.Name = info.id
		frame.LayoutOrder = index
		frame.Visible = true

		local nameLabel = frame:WaitForChild("PenName") :: TextLabel
		local descriptionLabel = frame:WaitForChild("Description") :: TextLabel
		local purchase = frame:WaitForChild("Purchase") :: TextButton

		nameLabel.Text = info.displayName
		descriptionLabel.Text = info.description
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
			if state == "owned" then
				network.fireServer(network.RemoteEvents.PenSkinAction, "Equip", info.id)
			elseif state == "ready" or state == "poor" then
				openOptions(card)
			else
				shake(purchase)
			end
		end)

		frame.Parent = scrollFrame
	end
end

-- Builds the ViewportFrame + model for one card. Only geometry is kept.
local function buildPreview(card: Card)
	local template = penTemplates:FindFirstChild(card.info.id)
	local holder = card.frame:FindFirstChild("PenImage")
	if not template or not holder then
		return
	end

	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		elseif not (descendant:IsA("Model") or descendant:IsA("Folder")) then
			descendant:Destroy()
		end
	end
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
	card.distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.0
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

-- Spins every visible preview: orbits its camera round the pen (one connection for all cards).
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
	closeOptions()
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
	closeOptions()
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
cancelButton.MouseButton1Click:Connect(closeOptions)

moneyButton.MouseButton1Click:Connect(function()
	local card = optionsCard
	if not card then
		return
	end

	if money.Value < card.info.price then
		flashMessage(moneyButton, REASON_TEXT.NoMoney, refreshOptions)
		return
	end
	network.fireServer(network.RemoteEvents.PenSkinAction, "Buy", card.info.id)
end)

robuxButton.MouseButton1Click:Connect(function()
	local card = optionsCard
	if not card then
		return
	end

	if not card.info.robuxAvailable then
		flashMessage(robuxButton, REASON_TEXT.RobuxUnavailable, refreshOptions)
		return
	end
	network.fireServer(network.RemoteEvents.PenSkinAction, "BuyRobux", card.info.id)
end)

money.Changed:Connect(function()
	if shopGui.Enabled then
		refreshAll()
	end
end)

for _, attribute in { OWNED_ATTRIBUTE, EQUIPPED_ATTRIBUTE } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if shopGui.Enabled then
			refreshAll()
		end
	end)
end

for _, instance in collectionService:GetTagged(SHOP_PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(connectPrompt)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.PenSkinResult, function(id: string, success: boolean, reason: string?)
	local card = cardById[id]
	if not card then
		return
	end

	if success then
		closeOptions()
		refreshAll()
		local scale = card.frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = card.frame
		end
		scale.Scale = 1.06
		tweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		local text = REASON_TEXT[reason or ""] or "Can't buy"
		if optionsCard == card then
			flashMessage(moneyButton, text, refreshOptions)
		else
			flashMessage(card.purchase, text, function()
				refreshCard(card)
			end)
		end
	end
end)

-- Shearing started: the shop must not stay up over the mini-game.
network.connectEvent(network.RemoteEvents.ActivateShearing, closeShop)
