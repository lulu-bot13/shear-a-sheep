--!strict

--[[
	Every game pass and developer product, keyed by its Robux shop card's frame name: the single source of truth for ids and perks.
	Prices are never stored here or read from the cards; they come live from MarketplaceService.

	Location: ReplicatedStorage.Shared.Constants.MonetizationData
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationConfig = require(replicatedStorage.Shared.Utils.MonetizationConfig)

export type Kind = MonetizationConfig.Kind
export type Item = MonetizationConfig.Item -- id 0 = not set up yet; perks: multiplier, durationMinutes, gems

return MonetizationConfig.create({
	--// Game passes
	DoubleWool = {
		kind = "GamePass",
		id = 2064520281,
		giftable = true,
		giftProductId = 3726902421,
		displayName = "2x WOOL",
		multiplier = 2,
	},
	DoubleLuck = {
		kind = "GamePass",
		id = 2064262952,
		giftable = true,
		giftProductId = 3726902227,
		displayName = "2x LUCK",
		multiplier = 2,
	},
	AutoShears = {
		kind = "GamePass",
		id = 2063911904,
		giftable = true,
		giftProductId = 3726902027,
		displayName = "AUTO SHEARS",
	},

	--// Boosts (developer products)
	LuckBoost = {
		kind = "DevProduct",
		id = 3726861608,
		giftable = true,
		giftProductId = 3726861608, -- shared: a picked gift reroutes the purchase (GiftService)
		displayName = "3x LUCK BOOST",
		multiplier = 3,
		durationMinutes = 15,
	},
	ServerLuck = {
		kind = "DevProduct",
		id = 3726859794,
		giftable = false,
		giftProductId = 0,
		displayName = "SERVER LUCK",
		multiplier = 2,
		durationMinutes = 15,
	},
	SkipRebirth = {
		kind = "DevProduct",
		id = 3726858775,
		giftable = false,
		giftProductId = 0,
		displayName = "SKIP REBIRTH",
	},

	--// Gems (developer products)
	GemsLarge = {
		kind = "DevProduct",
		id = 3726862793,
		giftable = true,
		giftProductId = 3726862793, -- shared: a picked gift reroutes the purchase (GiftService)
		displayName = "CHEST OF GEMS",
		gems = 150,
	},
	GemsMedium = {
		kind = "DevProduct",
		id = 3726862632,
		giftable = true,
		giftProductId = 3726862632, -- shared: a picked gift reroutes the purchase (GiftService)
		displayName = "POUCH OF GEMS",
		gems = 60,
	},
	GemsSmall = {
		kind = "DevProduct",
		id = 3726862073,
		giftable = true,
		giftProductId = 3726862073, -- shared: a picked gift reroutes the purchase (GiftService)
		displayName = "HANDFUL OF GEMS",
		gems = 10,
	},
})
