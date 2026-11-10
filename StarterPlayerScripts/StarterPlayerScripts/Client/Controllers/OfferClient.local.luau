--[[
	Shows the offer OfferHandler picks as a small dismissible toast built here: "Get it" prompts the purchase, "Not today" hides it for the session.
	Auto Shears can offer its one-time free trial; the Starter Pack counts down to when it's gone.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.OfferClient
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local iconIds = require(replicatedStorage.Shared.Constants.IconIds)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)
local shopCardBinder = require(script.Parent.Parent.Modules.ShopCardBinder)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local DISPLAY_ORDER = 60 -- under Alerts (100) and the purchase effect
local FONT = Font.fromEnum(Enum.Font.SourceSansBold)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local PANEL_COLOR = Color3.fromRGB(35, 35, 50)
local GET_COLOR = Color3.fromRGB(70, 200, 90)
local TRIAL_COLOR = Color3.fromRGB(70, 150, 255)
local DISMISS_COLOR = Color3.fromRGB(120, 120, 130)
local BUTTON_GAP = 0.03 -- of the button row's width
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HIDE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local ROBUX_GLYPH = "\u{E002}"
local TUTORIAL_GUI_NAME = "Tutorial" -- no offers while TutorialClient has it up

local OFFER_ICONS = {
	LuckBoost = iconIds.Luck,
	ServerLuck = iconIds.Luck,
	StarterPack = iconIds.Gem,
}

-- OfferHandler.Offer
type Offer = {
	key: string,
	title: string,
	text: string,
	duration: number,
	secondsLeft: number?,
	trial: boolean?,
}

--// State
local showToken = 0
local currentOffer: Offer? = nil

--// Toast -------------------------------------------------------------------------------

local function addStroke(parent: GuiObject, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function newLabel(name: string, position: UDim2, size: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	addStroke(label, 2)
	return label
end

local toastGui = Instance.new("ScreenGui")
toastGui.Name = "OfferToast"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = DISPLAY_ORDER
toastGui.Enabled = false
toastGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Offer"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -16, 0.55, 0)
panel.Size = UDim2.fromScale(0.3, 0.2)
panel.BackgroundColor3 = PANEL_COLOR
panel.BackgroundTransparency = 0.1
panel.Parent = toastGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0.12, 0)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = WHITE
panelStroke.Thickness = 2.5
panelStroke.Parent = panel
local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = 2.4
aspect.Parent = panel
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MinSize = Vector2.new(250, 104)
sizeLimit.MaxSize = Vector2.new(420, 175)
sizeLimit.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local icon = Instance.new("ImageLabel")
icon.Name = "Icon"
icon.BackgroundTransparency = 1
icon.Position = UDim2.fromScale(0.03, 0.08)
icon.Size = UDim2.fromScale(0.52, 0.52)
icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
icon.ScaleType = Enum.ScaleType.Fit
icon.Parent = panel

local titleLabel = newLabel("Title", UDim2.fromScale(0.27, 0.06), UDim2.fromScale(0.7, 0.22))
titleLabel.Parent = panel
local bodyLabel = newLabel("Body", UDim2.fromScale(0.27, 0.29), UDim2.fromScale(0.7, 0.3))
bodyLabel.Parent = panel
local countdownLabel = newLabel("Countdown", UDim2.fromScale(0.02, 0.66), UDim2.fromScale(0.23, 0.24))
countdownLabel.TextXAlignment = Enum.TextXAlignment.Center
countdownLabel.Parent = panel

local buttonRow = Instance.new("Frame")
buttonRow.Name = "Buttons"
buttonRow.BackgroundTransparency = 1
buttonRow.Position = UDim2.fromScale(0.27, 0.64)
buttonRow.Size = UDim2.fromScale(0.7, 0.28)
buttonRow.Parent = panel
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.Padding = UDim.new(BUTTON_GAP, 0)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = buttonRow

local function newButton(name: string, text: string, color: Color3, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.BackgroundColor3 = color
	button.FontFace = FONT
	button.Text = text
	button.TextColor3 = WHITE
	button.TextScaled = true
	button.AutoButtonColor = true
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.3, 0)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.12, 0)
	padding.PaddingBottom = UDim.new(0.12, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = button
	addStroke(button, 1.5)
	button.Parent = buttonRow
	return button
end

local getButton = newButton("GetIt", "Get it", GET_COLOR, 1)
local trialButton = newButton("Trial", "Try free", TRIAL_COLOR, 2)
local dismissButton = newButton("NotToday", "Not today", DISMISS_COLOR, 3)

--// Showing ------------------------------------------------------------------------

local function formatCountdown(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	return string.format("Ends in\n%d:%02d:%02d", hours, minutes, math.floor(seconds % 60))
end

local function layoutButtons()
	local shown = {}
	for _, button in { getButton, trialButton, dismissButton } do
		if button.Visible then
			table.insert(shown, button)
		end
	end
	local width = (1 - BUTTON_GAP * (#shown - 1)) / #shown
	for _, button in shown do
		button.Size = UDim2.fromScale(width, 1)
	end
end

local function hide()
	showToken += 1
	currentOffer = nil
	local tween = tweenService:Create(panelScale, HIDE_TWEEN, { Scale = 0 })
	local token = showToken
	tween.Completed:Once(function()
		if token == showToken then
			toastGui.Enabled = false
		end
	end)
	tween:Play()
end

local function respond(action: string)
	local offer = currentOffer
	if not offer then
		return
	end
	network.fireServer(network.RemoteEvents.OfferResponse, offer.key, action)
	hide()
	if action ~= "Accept" then
		return
	end

	local item = MonetizationData.get(offer.key)
	if not item or item.id == 0 then
		return
	end
	purchaseEffect.play()
	if item.kind == "GamePass" then
		marketplaceService:PromptGamePassPurchase(player, item.id)
	else
		network.fireServer(network.RemoteEvents.RequestProductPrompt, item.key)
	end
end

-- Counts the Starter Pack down once a second, only while this offer is up.
local function runCountdown(token: number, secondsLeft: number)
	local endsAt = os.clock() + secondsLeft
	task.spawn(function()
		while token == showToken do
			countdownLabel.Text = formatCountdown(math.max(endsAt - os.clock(), 0))
			task.wait(1)
		end
	end)
end

local function show(offer: Offer)
	local item = MonetizationData.get(offer.key)
	local tutorialGui = playerGui:FindFirstChild(TUTORIAL_GUI_NAME)
	if not item or item.id == 0 or (tutorialGui and tutorialGui:IsA("ScreenGui") and tutorialGui.Enabled) then
		return
	end

	showToken += 1
	local token = showToken
	currentOffer = offer

	titleLabel.Text = offer.title
	bodyLabel.Text = offer.text
	icon.Image = item.icon or OFFER_ICONS[item.key] or iconIds.Luck
	getButton.Text = "Get it"
	trialButton.Visible = offer.trial == true
	countdownLabel.Visible = type(offer.secondsLeft) == "number"
	layoutButtons()

	if type(offer.secondsLeft) == "number" then
		runCountdown(token, offer.secondsLeft)
	end
	task.spawn(function()
		local price = shopCardBinder.getPriceAsync(item.id, item.kind)
		if price and token == showToken then
			getButton.Text = `Get it {ROBUX_GLYPH}{price}`
		end
	end)

	toastGui.Enabled = true
	panelScale.Scale = 0.4
	tweenService:Create(panelScale, POP_TWEEN, { Scale = 1 }):Play()

	task.delay(offer.duration, function()
		if token == showToken then
			hide()
		end
	end)
end

getButton.Activated:Connect(function()
	respond("Accept")
end)
trialButton.Activated:Connect(function()
	respond("Trial")
end)
dismissButton.Activated:Connect(function()
	respond("Dismiss")
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShowOffer, function(offer: any)
	if type(offer) == "table" and type(offer.key) == "string" and type(offer.duration) == "number" then
		show(offer)
	end
end)
