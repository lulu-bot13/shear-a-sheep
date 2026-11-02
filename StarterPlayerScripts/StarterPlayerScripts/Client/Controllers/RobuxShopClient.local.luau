--[[
	The Robux shop window (StarterGui.RobuxShop): opens from Main.Buttons.Shop, scrolls to a category's header, binds every card to MonetizationData
	and swaps the shop for the gift window while gifting. The server (MonetizationHandler, GiftService) checks and grants everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RobuxShopClient
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
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
local categories = mainFrame:WaitForChild("Categories")
local giftFrame = shopGui:WaitForChild("GiftFrame") :: GuiObject

--// Configs
local SCROLL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HEADER_SUFFIX = "Header"

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

--// State
local cards: { [string]: shopCardBinder.Card } = {}
local scrollTween: Tween? = nil

--// Categories --------------------------------------------------------------------

-- The tab's Section attribute names its header ("PassesHeader" or just "Passes"); the tab's own name is the fallback.
local function getHeader(tab: Instance): GuiObject?
	local section = tab:GetAttribute("Section")
	local names = if type(section) == "string" then { section, section .. HEADER_SUFFIX } else {}
	table.insert(names, tab.Name .. HEADER_SUFFIX)
	for _, name in names do
		local header = itemsFrame:FindFirstChild(name)
		if header and header:IsA("GuiObject") then
			return header
		end
	end
	return nil
end

-- Absolute sizes include the window's UIScale; CanvasPosition doesn't, so they're divided by it.
local function scrollTo(header: GuiObject)
	local scale = windowsManager.getScaleFactor(itemsFrame)
	local offset = (header.AbsolutePosition - itemsFrame.AbsolutePosition) / scale + itemsFrame.CanvasPosition
	local maximum = (itemsFrame.AbsoluteCanvasSize - itemsFrame.AbsoluteWindowSize) / scale
	local target = Vector2.new(
		math.clamp(offset.X, 0, math.max(maximum.X, 0)),
		math.clamp(offset.Y, 0, math.max(maximum.Y, 0))
	)

	if scrollTween then
		scrollTween:Cancel()
	end
	local tween = tweenService:Create(itemsFrame, SCROLL_TWEEN, { CanvasPosition = target })
	scrollTween = tween
	tween:Play()
end

for _, tab in categories:GetChildren() do
	if tab:IsA("GuiButton") then
		tab.Activated:Connect(function()
			local header = getHeader(tab)
			if header then
				scrollTo(header)
			else
				warn(`[RobuxShopClient] no header in Items for the {tab.Name} tab`)
			end
		end)
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

for key, item in MonetizationData.Items do
	local frame = itemsFrame:FindFirstChild(key, true)
	if not frame or not frame:IsA("GuiObject") then
		continue
	end
	cards[key] = shopCardBinder.bind(frame, item, {
		onBuy = purchaseEffect.play,
		-- Products are prompted by the server, so it can refuse one that can't be bought right now.
		onBuyProduct = function()
			network.fireServer(network.RemoteEvents.RequestProductPrompt, key)
		end,
		onGift = picker.open,
	})
end

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
	onOpen = function()
		for _, card in cards do
			card.refreshPrice()
		end
		network.fireServer(network.RemoteEvents.RequestShopState)
	end,
	onClose = picker.close,
})

-- The gift window takes the shop's place while it's open; closing it brings the shop back unless the whole window closed.
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
