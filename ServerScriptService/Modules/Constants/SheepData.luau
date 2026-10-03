local rarityColors = {
	Common = Color3.fromRGB(107, 114, 128),
	Uncommon = Color3.fromRGB(21, 128, 61),
	Rare = Color3.fromRGB(29, 78, 216),
	Epic = Color3.fromRGB(126, 34, 206),
	Legendary = Color3.fromRGB(194, 65, 12),
	Mythic = Color3.fromRGB(190, 18, 60),
}

local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local sheepData = {

	["Basic"] = {
		id = "Basic_Sheep",
		name = "Basic Sheep",
		ShearHealth = 100,
		WoolAmount = 15,
		rarity = "Common",
		color = rarityColors.Common,
		chance = 500000,
	},

	["GreySheep"] = {
		id = "Grey_Sheep",
		name = "Grey Sheep",
		ShearHealth = 105,
		WoolAmount = 18,
		rarity = "Common",
		color = rarityColors.Common,
		chance = 250000,
	},

	["BrownSheep"] = {
		id = "Brown_Sheep",
		name = "Brown Sheep",
		ShearHealth = 115,
		WoolAmount = 20,
		rarity = "Uncommon",
		color = rarityColors.Uncommon,
		chance = 150000,
	},

	["BlackSheep"] = {
		id = "Black_Sheep",
		name = "Black Sheep",
		ShearHealth = 130,
		WoolAmount = 28,
		rarity = "Uncommon",
		color = rarityColors.Uncommon,
		chance = 60000,
	},

	["FluffySheep"] = {
		id = "Fluffy_Sheep",
		name = "Fluffy Sheep",
		ShearHealth = 145,
		WoolAmount = 35,
		rarity = "Rare",
		color = rarityColors.Rare,
		chance = 30000,
	},

	["GoldenSheep"] = {
		id = "Golden_Sheep",
		name = "Golden Sheep",
		ShearHealth = 175,
		WoolAmount = 50,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 7500,
	},

	["EmeraldSheep"] = {
		id = "Emerald_Sheep",
		name = "Emerald Sheep",
		ShearHealth = 190,
		WoolAmount = 60,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 2000,
	},

	["SpottedSheep"] = {
		id = "Spotted_Sheep",
		name = "Spotted Sheep",
		ShearHealth = 215,
		WoolAmount = 80,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 400,
	},

	["DiamondSheep"] = {
		id = "Diamond_Sheep",
		name = "Diamond Sheep",
		ShearHealth = 250,
		WoolAmount = 100,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 100,
	},

}

--[[
	Per-rarity-tier weight multipliers used by pen upgrades: as a pen levels
	up, common sheep get less likely and rare+ sheep get more likely. Level 1
	is the untouched base table (no override -- see Pen.lua).
]]--
sheepData.UpgradeMultipliers = {
	[1] = { Common = 1,    Uncommon = 1,    Rare = 1,    Epic = 1,   Legendary = 1,  Mythic = 1 },
	[2] = { Common = 0.8,  Uncommon = 1.3,  Rare = 1.6,  Epic = 2.2, Legendary = 3,  Mythic = 4 },
	[3] = { Common = 0.6,  Uncommon = 1.6,  Rare = 2.4,  Epic = 3.6, Legendary = 5,  Mythic = 8 },
	[4] = { Common = 0.45, Uncommon = 2,    Rare = 3.2,  Epic = 5,   Legendary = 8,  Mythic = 14 },
	[5] = { Common = 0.3,  Uncommon = 2.5,  Rare = 4.5,  Epic = 8,   Legendary = 14, Mythic = 25 },
}
sheepData.MaxPenLevel = 5
sheepData.LuckyRarities = { Rare = true, Epic = true, Legendary = true, Mythic = true }

-- Sum of every species' base weight (1,000,000 by construction).
function sheepData.getTotalWeight(chances: { [string]: number }?): number
	local total = 0
	for sheepName, data in sheepData do
		if type(data) == "table" and data.chance then
			total += (chances and chances[sheepName]) or data.chance
		end
	end
	return total
end

--[[
	Builds the spawn weights for a pen level, biasing rarer tiers upward.

	@param level The pen's level
	@param luckBonus Extra weight for Rare and better sheep from rebirths (0.1 = 10% more likely)

	@return A table of sheepName -> weight, or nil to use the base table as-is
]]--
function sheepData.buildChancesForLevel(level: number, luckBonus: number?): { [string]: number }?
	local multipliers = sheepData.UpgradeMultipliers[level]
	local bonus = luckBonus or 0
	if not multipliers or (level <= 1 and bonus <= 0) then
		return nil -- nil means "use the base table as-is"
	end

	local chances = {}
	for sheepName, data in sheepData do
		if type(data) == "table" and data.chance then
			local multiplier = multipliers[data.rarity] or 1
			if bonus > 0 and sheepData.LuckyRarities[data.rarity] then
				multiplier *= 1 + bonus
			end
			chances[sheepName] = data.chance * multiplier
		end
	end
	return chances
end

function sheepData.getOddsText(sheepName: string, chances: { [string]: number }?): string
	local data = sheepData[sheepName]
	if not data then
		return "1 in ?"
	end

	local weight = (chances and chances[sheepName]) or data.chance
	local total = sheepData.getTotalWeight(chances)
	if weight <= 0 or total <= 0 then
		return "1 in ?"
	end

	local odds = math.max(1, math.floor(total / weight + 0.5))
	return `1 in {odds}`
end

sheepData.RarityColors = rarityColors
sheepData.RarityOrder = rarityOrder

return sheepData