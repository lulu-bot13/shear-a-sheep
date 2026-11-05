--[[
	The Robux shop window (StarterGui.RobuxShop): opens from Main.Buttons.Shop, fits its canvas, scrolls to and highlights categories, binds
	every card to MonetizationData and swaps in the gift window while gifting. The server (MonetizationHandler, GiftService) grants everything.

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
local TAB_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAB_SELECTED_COLOR = Color3.fromRGB(255, 196, 46) -- the unselected colour is each tab's own Studio colour
local HEADER_SUFFIX = "Header"
local MIN_SCALE_FACTOR = 0.05 -- below this the window is closing, so nothing is measured
local MEASURE_DEPTH = 3 -- how far below Items the canvas looks for content (sections, their grids, the cards in them)
local IN_VIEW_MARGIN = 12 -- a header this close below the top of the list already counts as the section in view

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
local canvasQueued = false
local tabs: { GuiButton } = {}
local tabColors: { [GuiButton]: Color3 } = {}
local selectedTab: GuiButton? = nil

--// Canvas ------------------------------------------------------------------------

--[[
	Scale on Y inside a ScrollingFrame is relative to the canvas, so Items' own children are turned into pixels using the
	canvas height Studio laid them out on; otherwise every taller canvas would make them taller and it would never settle.
]]
local designCanvas = itemsFrame.CanvasSize
local itemsPadding = itemsFrame:FindFirstChildOfClass("UIPadding")
local itemsList = itemsFrame:FindFirstChildOfClass("UIListLayout")
local listPadding = if itemsList then itemsList.Padding else nil
local designLayouts: { [GuiObject]: { size: UDim2, position: UDim2 } } = {}

-- Nil while the window is shrunk to (almost) nothing by its close tween.
local function getScaleFactor(): number?
	local factor = windowsManager.getScaleFactor(itemsFrame)
	return if factor > MIN_SCALE_FACTOR then factor else nil
end

local function toCanvasPixels(size: UDim, windowHeight: number): UDim
	local canvasHeight = math.max(windowHeight, designCanvas.Y.Offset + designCanvas.Y.Scale * windowHeight)
	return UDim.new(0, math.floor(size.Offset + size.Scale * canvasHeight))
end

-- Top and bottom padding, with offsets multiplied by factor (1 for Offset pixels, the UIScale for screen pixels).
local function getPaddingY(padding: UIPadding?, height: number, factor: number): (number, number)
	if not padding then
		return 0, 0
	end
	return padding.PaddingTop.Offset * factor + padding.PaddingTop.Scale * height,
		padding.PaddingBottom.Offset * factor + padding.PaddingBottom.Scale * height
end

local function rememberLayout(child: Instance)
	if child:IsA("GuiObject") and not designLayouts[child] then
		designLayouts[child] = { size = child.Size, position = child.Position }
	end
end

local function updateChildSizes(windowHeight: number)
	for child, design in designLayouts do
		if design.size.Y.Scale ~= 0 then
			child.Size = UDim2.new(design.size.X, toCanvasPixels(design.size.Y, windowHeight))
		end
		if design.position.Y.Scale ~= 0 then
			child.Position = UDim2.new(design.position.X, toCanvasPixels(design.position.Y, windowHeight))
		end
	end
	if itemsList and listPadding and listPadding.Scale ~= 0 then
		itemsList.Padding = toCanvasPixels(listPadding, windowHeight)
	end
end

--[[
	The lowest bottom edge (screen pixels) of what's shown under parent: its visible children and, for a section, everything
	its layout holds even past the section's own size. Cards are measured whole, so their shines and buttons don't count.
]]
local function measureBottom(parent: GuiObject, depth: number, factor: number): number
	local bottom = -math.huge
	local layout = parent:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout and parent ~= itemsFrame then
		local top, bottomPadding = getPaddingY(parent:FindFirstChildOfClass("UIPadding"), parent.AbsoluteSize.Y, factor)
		bottom = parent.AbsolutePosition.Y + top + layout.AbsoluteContentSize.Y + bottomPadding
	end
	for _, child in parent:GetChildren() do
		if not child:IsA("GuiObject") or not child.Visible then
			continue
		end
		bottom = math.max(bottom, child.AbsolutePosition.Y + child.AbsoluteSize.Y)
		local isCard = MonetizationData.Items[child.Name] ~= nil
		if depth > 1 and not isCard and not child.ClipsDescendants and not child:IsA("ScrollingFrame") then
			bottom = math.max(bottom, measureBottom(child, depth - 1, factor))
		end
	end
	return bottom
end

-- Only when the content doesn't fit does the canvas get taller (in Offset pixels) so the player can scroll to the rest.
local function updateCanvasSize()
	local factor = getScaleFactor()
	if not factor then
		return
	end

	local windowHeight = itemsFrame.AbsoluteWindowSize.Y / factor
	updateChildSizes(windowHeight)

	local _, bottomPadding = getPaddingY(itemsPadding, windowHeight, 1)
	local canvasTop = itemsFrame.AbsolutePosition.Y - itemsFrame.CanvasPosition.Y * factor
	local bottom = measureBottom(itemsFrame, MEASURE_DEPTH, factor)
	local needed = if bottom > canvasTop then math.ceil((bottom - canvasTop) / factor + bottomPadding) else 0
	local canvasSize = UDim2.new(designCanvas.X, UDim.new(0, if needed > windowHeight then needed else 0))
	if itemsFrame.CanvasSize ~= canvasSize then
		itemsFrame.CanvasSize = canvasSize
	end
end

-- Layouts only measure their content after a change lands, so every refresh waits for the end of the frame (once).
local function queueCanvasUpdate()
	if canvasQueued then
		return
	end
	canvasQueued = true
	task.defer(function()
		canvasQueued = false
		updateCanvasSize()
	end)
end

local function watchContent(instance: Instance)
	if instance:IsA("UIGridStyleLayout") then
		instance:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(queueCanvasUpdate)
	end
	if instance.Parent == itemsFrame and instance:IsA("GuiObject") then
		rememberLayout(instance)
		instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueCanvasUpdate)
		instance:GetPropertyChangedSignal("Visible"):Connect(queueCanvasUpdate)
	end
end

itemsFrame.AutomaticCanvasSize = Enum.AutomaticSize.None -- updateCanvasSize sizes it instead
for _, descendant in itemsFrame:GetDescendants() do
	watchContent(descendant)
end
itemsFrame.DescendantAdded:Connect(watchContent)
itemsFrame.ChildAdded:Connect(queueCanvasUpdate)
itemsFrame.ChildRemoved:Connect(function(child: Instance)
	if child:IsA("GuiObject") then
		designLayouts[child] = nil
	end
	queueCanvasUpdate()
end)
itemsFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(queueCanvasUpdate)
queueCanvasUpdate()

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

local function selectTab(tab: GuiButton?, instant: boolean?)
	if tab == selectedTab then
		return
	end
	selectedTab = tab
	for button, color in tabColors do
		local goal = if button == tab then TAB_SELECTED_COLOR else color
		if instant then
			button.BackgroundColor3 = goal
		else
			tweenService:Create(button, TAB_TWEEN, { BackgroundColor3 = goal }):Play()
		end
	end
end

-- The tab whose header is the last one at (or above) the top of the list; the lowest one once scrolled to the end.
local function getTabInView(): GuiButton?
	local factor = getScaleFactor() or 1
	local viewTop = itemsFrame.AbsolutePosition.Y + IN_VIEW_MARGIN * factor
	local maximum = itemsFrame.AbsoluteCanvasSize.Y - itemsFrame.AbsoluteWindowSize.Y
	local atEnd = maximum > 1 and itemsFrame.CanvasPosition.Y * factor >= maximum - 1

	local inView: GuiButton?, inViewY = nil, -math.huge
	local first: GuiButton?, firstY = nil, math.huge
	local last: GuiButton?, lastY = nil, -math.huge
	for _, tab in tabs do
		local header = getHeader(tab)
		if not header then
			continue
		end
		local y = header.AbsolutePosition.Y
		if y <= viewTop and y > inViewY then
			inView, inViewY = tab, y
		end
		if y < firstY then
			first, firstY = tab, y
		end
		if y > lastY then
			last, lastY = tab, y
		end
	end
	return if atEnd then last else inView or first
end

local function refreshTabInView()
	local playing = scrollTween and scrollTween.PlaybackState == Enum.PlaybackState.Playing
	if not playing then
		selectTab(getTabInView() or selectedTab)
	end
end

for _, tab in categories:GetChildren() do
	if tab:IsA("GuiButton") then
		table.insert(tabs, tab)
		tabColors[tab] = tab.BackgroundColor3
		tab.Activated:Connect(function()
			local header = getHeader(tab)
			if header then
				selectTab(tab)
				scrollTo(header)
			else
				warn(`[RobuxShopClient] no header in Items for the {tab.Name} tab`)
			end
		end)
	end
end

-- Tabs in the order Categories shows them, so the first one wins while the headers haven't been laid out yet.
local tabList = categories:FindFirstChildOfClass("UIListLayout")
table.sort(tabs, function(a: GuiButton, b: GuiButton): boolean
	if tabList and tabList.SortOrder == Enum.SortOrder.Name then
		return a.Name < b.Name
	end
	return a.LayoutOrder < b.LayoutOrder
end)

itemsFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(refreshTabInView)
selectTab(getTabInView() or tabs[1], true)

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
		-- Nothing is laid out while the window is closed, so the canvas and the tab in view are measured again now.
		queueCanvasUpdate()
		task.defer(refreshTabInView)
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
