--!strict

--[[
	The five wool-priced farm upgrades. Each one fixes a different bottleneck, so whichever is holding the player back is the one to buy.
	Upgrades are kept through rebirths and reset on Prestige; prices are tuned so a Prestige run (rebirths 1-25) can max them all only near its end.

	Location: ServerScriptService.Modules.Constants.UpgradeData
]]--

local SpawnOdds = require(game:GetService("ReplicatedStorage").Shared.Utils.SpawnOdds)

export type UpgradeInfo = {
	id: string, -- must match its key in Upgrades
	displayName: string, -- the Title in the UpgradeShop
	icon: string, -- "rbxassetid://..." for the card's Icon; empty keeps the template's image
	baseCost: number, -- wool for the first level
	costGrowth: number, -- each level costs this many times the one before
	maxLevel: number?, -- levels that can be bought; nil = no limit (Capacity is capped by FarmData instead)
}

local upgradeData = {}

--[[
	Wool spent at a glance (rebirth costs for comparison: rebirth 5 ~4.8k, rebirth 10 ~26k, rebirth 25 ~4M):
	              per level             first levels           all levels
	More Wool     +0.25 wool x          45, 76, 130, 221       25 levels, ~37M (the late-run sink)
	Capacity      +1 sheep (3 -> 40)    40, 56, 78, 109        37 levels, ~26M (20 sheep ~30k)
	Shear Damage  +20% shear damage     60, 120, 240, 480      10 levels, ~61k
	Faster Resp.  x0.8 refill time      60, 120, 240, 480      10 levels, ~61k (6s -> 0.64s)
	Spawn Luck    +6% luck factor       120, 150, 187, 234     30 levels (4 + 2 per rebirth), ~390k
	Level 1 More Wool, 2 More Wool and 1 Capacity are the tutorial's first shop visit (161 wool).
]]
upgradeData.Upgrades = {
	MoreWool = { id = "MoreWool", displayName = "More Wool", icon = "rbxassetid://80186787578807", baseCost = 45, costGrowth = 1.7, maxLevel = 25 },
	Capacity = { id = "Capacity", displayName = "Sheep Capacity", icon = "rbxassetid://92809451973771", baseCost = 40, costGrowth = 1.4 },
	ShearDamage = { id = "ShearDamage", displayName = "Shear Damage", icon = "rbxassetid://74100799276370", baseCost = 60, costGrowth = 2, maxLevel = 10 },
	FasterRespawn = { id = "FasterRespawn", displayName = "Faster Respawn", icon = "rbxassetid://75508274630013", baseCost = 60, costGrowth = 2, maxLevel = 10 },
	SpawnLuck = { id = "SpawnLuck", displayName = "Spawn Luck", icon = "", baseCost = 120, costGrowth = 1.25, maxLevel = SpawnOdds.SPAWN_LUCK_MAX_LEVEL },
} :: { [string]: UpgradeInfo }

upgradeData.Order = { "MoreWool", "Capacity", "ShearDamage", "FasterRespawn", "SpawnLuck" } -- top to bottom in the UpgradeShop

--[[
	Upgrades taken out of the shop, by their save key: PlayerDataHandler refunds the wool spent on them once and drops the key.
	Faster Speed was walk speed only (no income), and Sheep Size's Giant chance was a weaker copy of Spawn Luck.
]]
upgradeData.Retired = {
	SpeedLevel = { baseCost = 100, costGrowth = 2.2, maxLevel = 8 },
	SizeLevel = { baseCost = 250, costGrowth = 2.2, maxLevel = 5 },
} :: { [string]: { baseCost: number, costGrowth: number, maxLevel: number } }

upgradeData.MoreWoolPerLevel = 0.25 -- each More Wool level adds this to the wool multiplier
upgradeData.BaseWalkSpeed = 16 -- Roblox's default walk speed (abilities multiply it)

--[[
	Shear Damage multiplies the held shear's damage by 1 + 0.2 per level (level 10 = x3), so every level or two takes a swing off:
	                 Basic(100)  Black(130)  Golden(175)  Diamond(250)
	Default  lv0     5           7           9            13
	Default  lv3     4           5           6            8
	Default  lv5     3           4           5            7
	Default  lv10    2           3           3            5
	Master   lv0     2           3           3            5
	Master   lv10    1           1           1            2
]]
upgradeData.ShearDamagePerLevel = 0.2

--[[
	Faster Respawn multiplies FarmData.SpawnInterval (6s) by 0.8 per level: 4.8s, 3.8s, 3.1s ... 0.64s at level 10.
	The slow base refill leaves new players short of sheep on purpose, so level 1 is cheap: it's the obvious first fix.
]]
upgradeData.RespawnMultiplierPerLevel = 0.8

--// Shop ----------------------------------------------------------------------------------

upgradeData.ShopPromptTag = "UpgradeShop" -- UpgradeHandler tags every plot's shack prompt with this; the client opens on it
upgradeData.ShackName = "UpgradePlotShack" -- the shack in each plot (its ProximityPrompt lives under an Attachment)
upgradeData.SellerName = "PlayerCharacterTemplate" -- the NPC in the shack, dressed as the plot's owner

-- Wool for the next level; nil for an unknown upgrade or one at its maxLevel.
function upgradeData.getCost(id: string, level: number): number?
	local info = upgradeData.Upgrades[id]
	if not info or (info.maxLevel and level >= info.maxLevel) then
		return nil
	end
	return math.floor(info.baseCost * info.costGrowth ^ level)
end

-- Wool a player spent on `levels` of a retired upgrade (its save key), refunded when the key is dropped.
function upgradeData.getRetiredRefund(key: string, levels: number): number
	local info = upgradeData.Retired[key]
	if not info then
		return 0
	end
	local total = 0
	for level = 0, math.clamp(math.floor(levels), 0, info.maxLevel) - 1 do
		total += math.floor(info.baseCost * info.costGrowth ^ level)
	end
	return total
end

function upgradeData.getMoreWoolMultiplier(level: number): number
	return 1 + upgradeData.MoreWoolPerLevel * level
end

-- Wool taken off per swing by a shear with this base damage at this Shear Damage level.
function upgradeData.getShearDamage(baseDamage: number, level: number): number
	return math.floor(baseDamage * (1 + upgradeData.ShearDamagePerLevel * level) + 0.5)
end

-- Seconds between sheep refilling a farm with this base interval at this Faster Respawn level.
-- Saves from before the rebalance may hold more levels than maxLevel; they count as maxLevel.
function upgradeData.getSpawnInterval(baseInterval: number, level: number): number
	local maxLevel = upgradeData.Upgrades.FasterRespawn.maxLevel or level
	return baseInterval * upgradeData.RespawnMultiplierPerLevel ^ math.min(level, maxLevel)
end

return upgradeData
