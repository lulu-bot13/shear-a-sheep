--[[
	Wires a Robux shop card (Buy, Gift, Owned) to its config item and shows the item's live price from MarketplaceService (cached, retried).
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ShopCardBinder
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")

--// Configs
local ROBUX_GLYPH = "\u{E002}"
local OWNED_TEXT = "OWNED"
local PRICE_ATTEMPTS = 3
local PRICE_RETRY_SECONDS = 2
local GREY_COLOR = Color3.fromRGB(150, 150, 150)
local GREY_GRADIENT = ColorSequence.new(Color3.fromRGB(175, 175, 175), Color3.fromRGB(115, 115, 115))

export type Kind = "GamePass" | "DevProduct"

-- The fields this module reads from a MonetizationConfig item.
export type Item = {
	key: string,
	kind: Kind,
	id: number,
	giftable: boolean,
	giftProductId: number,
	displayName: string,
	[string]: any,
}

export type Options = {
	onBuy: ((item: Item) -> ())?, -- runs whenever Buy goes through, just before the purchase is prompted
	onBuyProduct: ((item: Item) -> ())?, -- how a developer product is prompted; default: straight from the client
	onGift: ((item: Item) -> ())?, -- the Gift button, for giftable items with a gift product id
	formatPrice: ((price: number) -> string)?, -- default: ShopCardBinder.formatPrice
}

export type Card = {
	item: Item,
	frame: GuiObject,
	setOwned: (owned: boolean) -> (), -- greys Buy out with OWNED on it; the Gift button stays usable
	setBlocked: (blocked: boolean) -> (), -- greys Buy out and makes it do nothing
	refreshPrice: () -> (), -- tries the price again if it couldn't be fetched before
}

type ButtonLook = {
	color: Color3,
	gradient: UIGradient?,
	gradientColor: ColorSequence?,
	autoButtonColor: boolean,
}

--// State
local player = players.LocalPlayer
local priceCache: { [string]: number } = {}
local priceFetching: { [string]: boolean } = {}
local buttonLooks: { [GuiButton]: ButtonLook } = {}

local ShopCardBinder = {}

-- How a price shows on a Buy button; replace to change the format everywhere.
ShopCardBinder.formatPrice = function(price: number): string
	return `{ROBUX_GLYPH} {price}`
end

-- The Robux price of a game pass or developer product (cached); nil for an id of 0 or when it can't be fetched. Yields.
function ShopCardBinder.getPriceAsync(id: number, kind: Kind): number?
	if id == 0 then
		return nil
	end

	local cacheKey = `{kind}:{id}`
	while priceFetching[cacheKey] do
		task.wait()
	end
	if priceCache[cacheKey] then
		return priceCache[cacheKey]
	end

	priceFetching[cacheKey] = true
	local infoType = if kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local price: number? = nil
	for attempt = 1, PRICE_ATTEMPTS do
		local success, info = pcall(marketplaceService.GetProductInfoAsync, marketplaceService, id, infoType)
		if success and type(info) == "table" and type(info.PriceInRobux) == "number" then
			price = info.PriceInRobux
			break
		end
		if attempt < PRICE_ATTEMPTS then
			task.wait(PRICE_RETRY_SECONDS)
		else
			warn(`[ShopCardBinder] couldn't fetch the price of {kind} {id}: {if success then "no PriceInRobux" else info}`)
		end
	end
	priceFetching[cacheKey] = nil

	if price then
		priceCache[cacheKey] = price
	end
	return price
end

-- Greys a button out (its UIGradient if it has one, else its colour) or puts its Studio look back.
function ShopCardBinder.setButtonEnabled(button: GuiButton, enabled: boolean)
	local look = buttonLooks[button]
	if not look then
		local gradient = button:FindFirstChildOfClass("UIGradient")
		look = {
			color = button.BackgroundColor3,
			gradient = gradient,
			gradientColor = if gradient then gradient.Color else nil,
			autoButtonColor = button.AutoButtonColor,
		}
		buttonLooks[button] = look
	end

	if look.gradient and look.gradientColor then
		look.gradient.Color = if enabled then look.gradientColor else GREY_GRADIENT
	else
		button.BackgroundColor3 = if enabled then look.color else GREY_COLOR
	end
	button.AutoButtonColor = enabled and look.autoButtonColor
end

local function findChild(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

-- Binds a card frame to its config item.
function ShopCardBinder.bind(frame: GuiObject, item: Item, options: Options?): Card
	local opts: Options = options or {}
	local formatPrice = opts.formatPrice or ShopCardBinder.formatPrice

	local buyButton = findChild(frame, "Buy", "GuiButton") :: GuiButton?
	local priceLabel = if buyButton then findChild(buyButton, "Label", "TextLabel") :: TextLabel? else nil
	local giftButton = findChild(frame, "Gift", "GuiButton") :: GuiButton?

	local studioText = if priceLabel then priceLabel.Text else ""
	local giftZIndex = if giftButton then giftButton.ZIndex else 0
	local price: number? = nil
	local owned = false
	local blocked = false
	local fetching = false

	-- OWNED beats the price; the Studio text stays until the price is known. An owned Buy stops taking clicks and
	-- Gift is drawn over it, so where the two overlap the click reaches Gift.
	local function updateBuy()
		if priceLabel then
			priceLabel.Text = if owned then OWNED_TEXT elseif price then formatPrice(price) else studioText
		end
		if buyButton then
			ShopCardBinder.setButtonEnabled(buyButton, not owned and not blocked)
			buyButton.Interactable = not owned
			if giftButton then
				giftButton.ZIndex = if owned then math.max(giftZIndex, buyButton.ZIndex + 1) else giftZIndex
			end
		end
	end

	local function refreshPrice()
		if price or fetching then
			return
		end
		fetching = true
		task.spawn(function()
			price = ShopCardBinder.getPriceAsync(item.id, item.kind)
			fetching = false
			updateBuy()
		end)
	end

	if buyButton then
		buyButton.Activated:Connect(function()
			-- Nothing to buy until the real price is known (an id of 0 never gets one).
			if not price or owned or blocked then
				return
			end
			if opts.onBuy then
				opts.onBuy(item)
			end
			if item.kind == "GamePass" then
				marketplaceService:PromptGamePassPurchase(player, item.id)
			elseif opts.onBuyProduct then
				opts.onBuyProduct(item)
			else
				marketplaceService:PromptProductPurchase(player, item.id)
			end
		end)
	end

	if giftButton then
		giftButton.Activated:Connect(function()
			if item.giftable and item.giftProductId ~= 0 and opts.onGift then
				opts.onGift(item)
			end
		end)
	end

	refreshPrice()

	return {
		item = item,
		frame = frame,
		setOwned = function(isOwned: boolean)
			owned = isOwned
			updateBuy()
		end,
		setBlocked = function(isBlocked: boolean)
			blocked = isBlocked
			updateBuy()
		end,
		refreshPrice = refreshPrice,
	}
end

return ShopCardBinder
