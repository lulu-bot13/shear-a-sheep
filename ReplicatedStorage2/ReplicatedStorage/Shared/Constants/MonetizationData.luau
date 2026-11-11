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
export type Item = MonetizationConfig.Item -- id 0 = not set up yet (hidden everywhere); perks: multiplier, durationMinutes, gems; rewardText and icon for passes

return MonetizationConfig.create({
	--// Game passes
	DoubleWool = {
		kind = "GamePass",
		id = 2064520281,
		giftable = true,
		giftProductId = 3726902421,
		displayName = "2x WOOL",
		rewardText = "2x wool every shear",
		icon = "rbxassetid://136230905804958",
		multiplier = 2,
	},
	DoubleLuck = {
		kind = "GamePass",
		id = 2064262952,
		giftable = true,
		giftProductId = 3726902227,
		displayName = "2x LUCK",
		rewardText = "Higher chance for rare sheep to spawn!",
		icon = "rbxassetid://77360653541449",
		multiplier = 2,
	},
	AutoShears = {
		kind = "GamePass",
		id = 2063911904,
		giftable = true,
		giftProductId = 3726902027,
		displayName = "AUTO SHEARS",
		rewardText = "No more need for clicking!",
		icon = "rbxassetid://136356308886914",
	},
	RobuxConveyor = {
		kind = "GamePass",
		id = 2079194287,
		giftable = false,
		giftProductId = 0,
		displayName = "2ND CONVEYOR",
		rewardText = "A 2nd conveyor that brings 3x the sheep!",
		multiplier = 2, -- its refills per main-belt refill (SheepSpawnHandler), so 3x sheep in all
		inShop = false, -- bought from the plot's RobuxConveyor prompt; no Robux shop card yet
	},

	--// Bundles
	StarterPack = {
		kind = "GamePass", -- granted once by MonetizationHandler (StarterPackBought), sold through OfferHandler's popup
		id = 2079758258,
		inShop = false,
		giftable = false,
		giftProductId = 0,
		displayName = "STARTER PACK",
		rewardText = "+100 Gems and 15 min of 3x Luck!",
		gems = 100,
		boostKey = "LuckBoost", -- the boost it adds, for boostMinutes
		boostMinutes = 15,
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
	GemsBig = {
		kind = "DevProduct",
		id = 3729615295,
		giftable = true,
		giftProductId = 3729615295, -- shared: a picked gift reroutes the purchase (GiftService)
		displayName = "BAG OF GEMS",
		gems = 100,
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
