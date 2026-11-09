--!strict

--[[
	Builds a game's monetization config (every game pass and developer product, keyed by name) with lookups by id, and checks it once on the server.
	Duplicate ids, a giftable item with no giftProductId and ids still 0 are warned about, never errored on.

	Location: ReplicatedStorage.Shared.Utils.MonetizationConfig
]]--

--// Services
local runService = game:GetService("RunService")

export type Kind = "GamePass" | "DevProduct"

export type Item = {
	key: string, -- filled in from the table key
	kind: Kind,
	id: number, -- the game pass id or developer product id; 0 = not set up yet
	giftable: boolean,
	giftProductId: number, -- the developer product bought to gift this item; 0 = not set up yet
	displayName: string,
	rewardText: string?, -- what a game pass gives, shown on its shop card
	[string]: any, -- free-form perk data (multiplier, durationMinutes, gems...)
}

export type Config = {
	Items: { [string]: Item },
	get: (key: any) -> Item?,
	findByProductId: (productId: number) -> (Item?, boolean),
	findByPassId: (gamePassId: number) -> Item?,
}

local MonetizationConfig = {}

-- A developer product gifted through its own id: its receipt is a gift only while the buyer has picked a recipient.
function MonetizationConfig.sharesGiftProduct(item: Item): boolean
	return item.kind == "DevProduct" and item.giftable and item.id ~= 0 and item.giftProductId == item.id
end

local function validate(items: { [string]: Item })
	local passIds: { [number]: string } = {}
	local productIds: { [number]: string } = {}
	local unset = {}
	local unsetGifts = {}

	local function claim(ids: { [number]: string }, id: number, label: string, unsetList: { string })
		if id == 0 then
			table.insert(unsetList, label)
		elseif ids[id] then
			warn(`[MonetizationConfig] {label} uses id {id}, already used by {ids[id]}`)
		else
			ids[id] = label
		end
	end

	for key, item in items do
		if item.kind ~= "GamePass" and item.kind ~= "DevProduct" then
			warn(`[MonetizationConfig] {key} has kind "{tostring(item.kind)}"; it must be "GamePass" or "DevProduct"`)
			continue
		end
		claim(if item.kind == "GamePass" then passIds else productIds, item.id, `{key}.id`, unset)
		if item.giftable and not MonetizationConfig.sharesGiftProduct(item) then
			claim(productIds, item.giftProductId, key, unsetGifts)
		end
	end

	if #unset > 0 then
		table.sort(unset)
		warn(`[MonetizationConfig] {#unset} ids are still 0 (those items can't be bought yet): {table.concat(unset, ", ")}`)
	end
	if #unsetGifts > 0 then
		table.sort(unsetGifts)
		warn(`[MonetizationConfig] Gifting is off for {table.concat(unsetGifts, ", ")} until each has a gift developer product id in giftProductId`)
	end
end

-- Fills in each item's key and defaults, checks the ids (server only) and returns the config with its lookups.
function MonetizationConfig.create(items: { [string]: any }): Config
	local isServer = runService:IsServer()
	for key, item in items do
		item.key = key
		item.giftable = item.giftable == true
		if isServer and item.giftable and type(item.giftProductId) ~= "number" then
			warn(`[MonetizationConfig] {key} is giftable but has no giftProductId`)
		end
		item.giftProductId = if type(item.giftProductId) == "number" then item.giftProductId else 0
		item.displayName = item.displayName or key
	end
	local typedItems = items :: { [string]: Item }

	if isServer then
		validate(typedItems)
	end

	local config = {} :: Config
	config.Items = typedItems

	function config.get(key: any): Item?
		return if type(key) == "string" then typedItems[key] else nil
	end

	-- The item a developer product id belongs to, and whether it's that item's gift product; nil for 0 or an unknown id.
	function config.findByProductId(productId: number): (Item?, boolean)
		if productId == 0 then
			return nil, false
		end
		for _, item in typedItems do
			if item.kind == "DevProduct" and item.id == productId then
				return item, false
			elseif item.giftable and item.giftProductId == productId then
				return item, true
			end
		end
		return nil, false
	end

	function config.findByPassId(gamePassId: number): Item?
		if gamePassId == 0 then
			return nil
		end
		for _, item in typedItems do
			if item.kind == "GamePass" and item.id == gamePassId then
				return item
			end
		end
		return nil
	end

	return config
end

return MonetizationConfig
