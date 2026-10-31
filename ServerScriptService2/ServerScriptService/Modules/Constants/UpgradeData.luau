--!strict

--[[
	Wool-priced farm upgrades (sheep capacity, more wool, faster speed, shear damage, faster respawn). Costs grow exponentially with each level bought.

	Location: ServerScriptService.Modules.Constants.UpgradeData
]]--

export type UpgradeInfo = {
	id: string, -- must match its key in Upgrades
	displayName: string, -- the Title in the UpgradeShop
	icon: string, -- "rbxassetid://..." for the card's Icon; empty keeps the template's image
	baseCost: number, -- wool for the first level
	costGrowth: number, -- each level costs this many times the one before
	maxLevel: number?, -- levels that can be bought; nil = no limit (Capacity is capped by FarmData instead)
}

local upgradeData = {}

upgradeData.Upgrades = {
	Capacity = { id = "Capacity", displayName = "Sheep Capacity", icon = "rbxassetid://92809451973771", baseCost = 40, costGrowth = 1.55 },
	MoreWool = { id = "MoreWool", displayName = "More Wool", icon = "rbxassetid://80186787578807", baseCost = 45, costGrowth = 1.7, maxLevel = 48 }, -- level 1 = the tutorial's first 3 sheep
	FasterSpeed = { id = "FasterSpeed", displayName = "Faster Speed", icon = "rbxassetid://73292507992618", baseCost = 100, costGrowth = 2.2, maxLevel = 8 },
	ShearDamage = { id = "ShearDamage", displayName = "Shear Damage", icon = "rbxassetid://74100799276370", baseCost = 60, costGrowth = 1.8, maxLevel = 10 },
	FasterRespawn = { id = "FasterRespawn", displayName = "Faster Respawn", icon = "rbxassetid://75508274630013", baseCost = 120, costGrowth = 1.9, maxLevel = 8 },
} :: { [string]: UpgradeInfo }

upgradeData.Order = { "MoreWool", "Capacity", "FasterSpeed", "ShearDamage", "FasterRespawn" } -- top to bottom in the UpgradeShop

upgradeData.MoreWoolPerLevel = 0.25 -- each More Wool level adds this to the wool multiplier
upgradeData.BaseWalkSpeed = 16 -- Roblox's default walk speed
upgradeData.WalkSpeedPerLevel = 2 -- each Faster Speed level adds this (level 8 = 32)

--[[
	Shear Damage multiplies the held shear's damage by 1 + 0.1 per level (level 10 = x2). Swings to shear a sheep bare:
	                 Basic(100)  Black(130)  Golden(175)  Diamond(250)
	Default  lv0     5           7           9            13
	Default  lv5     4           5           6            9
	Default  lv10    3           4           5            7
	Master   lv0     2           3           3            5
	Master   lv10    1           2           2            3
	Levels 1-5 cost 1.3k in total, about a first run's wool before rebirth; it resets on rebirth like the other upgrades.
]]
upgradeData.ShearDamagePerLevel = 0.1

--[[
	Faster Respawn takes 0.1s off FarmData.SpawnInterval (1.5s) per level, down to 0.7s at level 8.
	A default shear needs ~1.75s per Basic sheep, so the refill only becomes the bottleneck once Shear Damage or a
	better shear is bought; it is priced to follow Shear Damage (levels 1-3 cost ~780 wool, all 8 about 22.5k).
]]
upgradeData.RespawnSecondsPerLevel = 0.1

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

function upgradeData.getMoreWoolMultiplier(level: number): number
	return 1 + upgradeData.MoreWoolPerLevel * level
end

function upgradeData.getWalkSpeed(level: number): number
	return upgradeData.BaseWalkSpeed + upgradeData.WalkSpeedPerLevel * level
end

-- Wool taken off per swing by a shear with this base damage at this Shear Damage level.
function upgradeData.getShearDamage(baseDamage: number, level: number): number
	return math.floor(baseDamage * (1 + upgradeData.ShearDamagePerLevel * level) + 0.5)
end

-- Seconds between sheep refilling a farm with this base interval at this Faster Respawn level.
function upgradeData.getSpawnInterval(baseInterval: number, level: number): number
	return baseInterval - upgradeData.RespawnSecondsPerLevel * level
end

return upgradeData
