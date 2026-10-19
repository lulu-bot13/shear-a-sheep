--!strict

--[[
	Wool-priced farm upgrades (sheep capacity, more wool, faster speed). Costs grow exponentially with each level bought.

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
	Capacity = { id = "Capacity", displayName = "Sheep Capacity", icon = "", baseCost = 40, costGrowth = 1.55 },
	MoreWool = { id = "MoreWool", displayName = "More Wool", icon = "", baseCost = 75, costGrowth = 1.7 },
	FasterSpeed = { id = "FasterSpeed", displayName = "Faster Speed", icon = "", baseCost = 100, costGrowth = 2.2, maxLevel = 8 },
} :: { [string]: UpgradeInfo }

upgradeData.Order = { "Capacity", "MoreWool", "FasterSpeed" } -- top to bottom in the UpgradeShop

upgradeData.MoreWoolPerLevel = 0.25 -- each More Wool level adds this to the wool multiplier
upgradeData.BaseWalkSpeed = 16 -- Roblox's default walk speed
upgradeData.WalkSpeedPerLevel = 2 -- each Faster Speed level adds this (level 8 = 32)

--// Shop ----------------------------------------------------------------------------------

upgradeData.ShopPromptTag = "UpgradeShop" -- UpgradeHandler tags every plot's shack prompt with this; the client opens on it
upgradeData.ShackName = "UpgradePlotShack" -- the shack in each plot (its ProximityPrompt lives under an Attachment)

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

return upgradeData
