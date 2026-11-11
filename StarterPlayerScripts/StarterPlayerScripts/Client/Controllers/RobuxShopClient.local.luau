--[[
	The Robux shop window (StarterGui.RobuxShop): opens from Main.Buttons.Shop, fills and binds every card from MonetizationData,
	sweeps the card shines while open (ShineRotate spins them), and swaps in the gift window while gifting. The server (MonetizationHandler, GiftService) grants everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RobuxShopClient
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local giftPicker = require(script.Parent.Parent.Modules.GiftPicker)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)
local shopCardBinder = require(script.Parent.Parent.Modules.ShopCardBinder)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shopGui = playerGui:WaitForChild("RobuxShop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: GuiObject
local itemsFrame = mainFrame:WaitForChild("Items") :: ScrollingFrame
local exitButton = mainFrame:WaitForChild("Exit") :: GuiButton
local giftFrame = shopGui:WaitForChild("GiftFrame") :: GuiObject

--// Configs
local BUTTON_HOVER_SCALE = 1.05 -- read by ButtonClient from the HoverScale / PressScale attributes
local BUTTON_PRESS_SCALE = 0.95

local ROTATING_SHINE_TAG = "RotatingShine" -- spun by ShineRotate
local SWEEP_INTERVAL = 5 -- seconds between one card's sweeps
local SWEEP_STAGGER = 0.25 -- seconds between neighbouring cards, top to bottom
local SWEEP_FIRST_DELAY = 0.6 -- after the shop opens
local SWEEP_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local SWEEP_WIDTH = 22 -- pixels
local SWEEP_ROTATION = 20
local SWEEP_START = UDim2.new(-0.5, -SWEEP_WIDTH, 0.5, 0)
local SWEEP_END = UDim2.new(1.5, SWEEP_WIDTH, 0.5, 0)
local SWEEP_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(1, 1),
})

local GIFT_REASON_TEXT = {
	NotGiftable = "That can't be gifted",
	NotLoaded = "Still loading, try again in a moment",
	NotInServer = "That player has left",
	Self = "You can't gift yourself",
	AlreadyOwned = "They already own that!",
	PriceLevel = "Gifting to that player isn't available in your region",
}

-- Text on the gift window row of a player the server won't let you gift to.
local GIFT_LOCK_TEXT = {
	Owned = "OWNED",
	PriceLevel = "UNAVAILABLE",
}

type Sweep = {
	card: GuiObject,
	line: Frame,
	tween: Tween,
	nextPlay: number,
}

--// State
local cards: { [string]: shopCardBinder.Card } = {}
local sweeps: { Sweep } = {}
local animation: RBXScriptConnection? = nil

local function findChild(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function formatNumber(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

--// Shines -------------------------------------------------------------------------

-- A thin white line, faded at its edges, that crosses the card art inside a clipping frame (above the art, below the text and buttons).
local function addSweep(card: GuiObject)
	local art = findChild(card, "Background", "GuiObject") :: GuiObject?
	local parent = art or card

	local clip = Instance.new("Frame")
	clip.Name = "ShineSweep"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Interactable = false
	clip.ZIndex = parent.ZIndex

	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = SWEEP_START
	line.Size = UDim2.new(0, SWEEP_WIDTH, 2, 0)
	line.Rotation = SWEEP_ROTATION
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BorderSizePixel = 0
	line.Visible = false
	line.ZIndex = parent.ZIndex
	line.Parent = clip

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = SWEEP_FADE
	gradient.Parent = line

	local tween = tweenService:Create(line, SWEEP_TWEEN, { Position = SWEEP_END })
	tween.Completed:Connect(function()
		line.Visible = false
	end)

	clip.Parent = parent
	table.insert(sweeps, { card = card, line = line, tween = tween, nextPlay = 0 })
end

local function playSweep(sweep: Sweep)
	sweep.tween:Cancel()
	sweep.line.Position = SWEEP_START
	sweep.line.Visible = true
	sweep.tween:Play()
end

-- One connection starts each card's sweep in turn, top to bottom; it only runs while the shop is open.
local function startAnimations()
	if animation then
		return
	end

	local order = table.clone(sweeps)
	table.sort(order, function(a: Sweep, b: Sweep): boolean
		local positionA, positionB = a.card.AbsolutePosition, b.card.AbsolutePosition
		if math.abs(positionA.Y - positionB.Y) > 1 then
			return positionA.Y < positionB.Y
		end
		return positionA.X < positionB.X
	end)
	local now = os.clock()
	for index, sweep in order do
		sweep.nextPlay = now + SWEEP_FIRST_DELAY + (index - 1) * SWEEP_STAGGER
	end

	animation = runService.RenderStepped:Connect(function()
		local clock = os.clock()
		for _, sweep in sweeps do
			if clock >= sweep.nextPlay then
				sweep.nextPlay = clock + SWEEP_INTERVAL
				if mainFrame.Visible then
					playSweep(sweep)
				end
			end
		end
	end)
end

local function stopAnimations()
	if animation then
		animation:Disconnect()
		animation = nil
	end
	for _, sweep in sweeps do
		sweep.tween:Cancel()
		sweep.line.Visible = false
	end
end

--// Gifting ------------------------------------------------------------------------

local picker = giftPicker.new({
	frame = giftFrame,
	getLocksAsync = function(item: MonetizationData.Item): { [number]: string }
		local success, locks = network.invokeServerAsync(network.RemoteFunctions.GetGiftLocks, item.key)
		local lockTexts = {}
		if success and type(locks) == "table" then
			for userId, lock in locks do
				local userIdNumber = tonumber(userId)
				if userIdNumber then
					lockTexts[userIdNumber] = GIFT_LOCK_TEXT[lock] or GIFT_LOCK_TEXT.PriceLevel
				end
			end
		end
		return lockTexts
	end,
	onConfirm = function(item: MonetizationData.Item, recipientUserId: number)
		local success, accepted, reason = network.invokeServerAsync(network.RemoteFunctions.RequestGift, item.key, recipientUserId)
		if success and accepted then
			purchaseEffect.play()
			marketplaceService:PromptProductPurchase(player, item.giftProductId)
		else
			alerts.show(GIFT_REASON_TEXT[if success then reason else ""] or "Couldn't send that gift, try again", "error")
		end
	end,
})

marketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
	local item = picker.getItem()
	if purchased and userId == player.UserId and item and productId == item.giftProductId then
		picker.close()
	end
end)

--// Cards ---------------------------------------------------------------------------

local function setHoverScale(button: Instance?)
	if button and button:IsA("GuiButton") then
		button:SetAttribute("HoverScale", BUTTON_HOVER_SCALE)
		button:SetAttribute("PressScale", BUTTON_PRESS_SCALE)
	end
end

-- What the player gets: a gem pack's gems, or a game pass's rewardText. Nil leaves the Studio text (a gem amount not set yet).
local function getAmountText(item: MonetizationData.Item): string?
	if type(item.gems) == "number" and item.gems > 0 then
		return `+{formatNumber(item.gems)}`
	elseif item.kind == "GamePass" and type(item.rewardText) == "string" then
		return item.rewardText
	end
	return nil
end

local function fillCard(card: GuiObject, item: MonetizationData.Item)
	local title = findChild(card, "Title", "TextLabel") :: TextLabel?
	if title then
		title.Text = item.displayName
	end
	local amount = findChild(card, "Amount", "TextLabel") :: TextLabel?
	local amountText = getAmountText(item)
	if amount and amountText then
		amount.Text = amountText
	end

	local shine = findChild(card, "Shine", "ImageLabel") :: ImageLabel?
	if shine then
		shine:AddTag(ROTATING_SHINE_TAG)
	end
	addSweep(card)
	setHoverScale(card:FindFirstChild("Buy"))
	setHoverScale(card:FindFirstChild("Gift"))
end

for key, item in MonetizationData.Items do
	local card = itemsFrame:FindFirstChild(key, true)
	if not card or not card:IsA("GuiObject") then
		-- Items still at id 0 (e.g. the Starter Pack) are hidden everywhere, and inShop = false ones are sold elsewhere, so they need no card.
		if item.id ~= 0 and item.inShop ~= false then
			warn(`[RobuxShopClient] no {key} card in RobuxShop.Main.Items; build it in Studio`)
		end
		continue
	elseif item.id == 0 then
		card.Visible = false
		continue
	end
	fillCard(card, item)
	cards[key] = shopCardBinder.bind(card, item, {
		onBuy = purchaseEffect.play,
		-- Products are prompted by the server, so it can refuse one that can't be bought right now.
		onBuyProduct = function()
			network.fireServer(network.RemoteEvents.RequestProductPrompt, key)
		end,
		onGift = picker.open,
	})
end
setHoverScale(exitButton)
setHoverScale(giftFrame:FindFirstChild("Exit"))

local function applyState(state: any)
	if type(state) ~= "table" or type(state.passes) ~= "table" then
		return
	end
	for key, card in cards do
		if card.item.kind == "GamePass" then
			card.setOwned(state.passes[key] == true)
		end
	end
	local skipRebirth = cards.SkipRebirth
	if skipRebirth then
		skipRebirth.setBlocked(state.rebirthMaxed == true)
	end
end

--// Setup -------------------------------------------------------------------------------

local window = windowsManager.register("RobuxShop", {
	gui = shopGui,
	frame = mainFrame,
	closeButton = exitButton,
	onOpen = function()
		for _, card in cards do
			card.refreshPrice()
		end
		startAnimations()
		network.fireServer(network.RemoteEvents.RequestShopState)
	end,
	onClose = function()
		stopAnimations()
		picker.close()
	end,
})

-- Gifting from outside the shop (pass boards) opens the shop straight onto the gift window.
shopCardBinder.setGiftHandler(function(item)
	window.open()
	picker.open(item)
end)

-- The gift window takes the shop's place while it's open; closing it (its Exit) brings the shop back unless the whole window closed.
giftFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if giftFrame.Visible then
		mainFrame.Visible = false
	elseif window.isOpen() then
		mainFrame.Visible = true
	end
end)

-- Main.Buttons.Shop toggles the shop; bound again whenever Main is recreated on respawn.
local boundButtons: { [Instance]: boolean } = {}
local function bindShopButton(hud: Instance)
	if hud.Name ~= "Main" or not hud:IsA("ScreenGui") then
		return
	end
	local buttons = hud:WaitForChild("Buttons", 10)
	local shopButton = buttons and buttons:WaitForChild("Shop", 10)
	if shopButton and shopButton:IsA("GuiButton") then
		if boundButtons[shopButton] then
			return
		end
		boundButtons[shopButton] = true
		shopButton.Destroying:Connect(function()
			boundButtons[shopButton] = nil
		end)
		shopButton.Activated:Connect(window.toggle)
	else
		warn("[RobuxShopClient] no Main.Buttons.Shop button to open the Robux shop")
	end
end

playerGui.ChildAdded:Connect(bindShopButton)
task.spawn(bindShopButton, playerGui:WaitForChild("Main"))

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShopState, applyState)
network.fireServer(network.RemoteEvents.RequestShopState)
