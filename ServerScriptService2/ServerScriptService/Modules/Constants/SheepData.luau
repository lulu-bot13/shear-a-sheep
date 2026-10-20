--!strict

--[[
	Every sheep type (wool health, wool and Luck it gives, rarity, base spawn weight) and the luck-weighted spawn roll.

	Location: ServerScriptService.Modules.Constants.SheepData
]]--

export type SheepInfo = {
	id: string,
	name: string,
	ShearHealth: number,
	WoolAmount: number,
	LuckAmount: number, -- Luck the player earns for shearing it bare
	IndexLuck: number?, -- permanent Luck for claiming it in the Index once; nil = worked out from its odds
	rarity: string,
	color: Color3,
	chance: number, -- base spawn weight (before luck)
}

local rarityColors = {
	Common = Color3.fromRGB(107, 114, 128),
	Uncommon = Color3.fromRGB(21, 128, 61),
	Rare = Color3.fromRGB(29, 78, 216),
	Epic = Color3.fromRGB(126, 34, 206),
	Legendary = Color3.fromRGB(194, 65, 12),
	Mythic = Color3.fromRGB(190, 18, 60),
}

local rarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local sheepData = {}

-- Keyed by model name in ReplicatedStorage.Assets.Models.Sheeps.
sheepData.Sheep = {
	Basic = {
		id = "Basic_Sheep",
		name = "Basic Sheep",
		ShearHealth = 100,
		WoolAmount = 15,
		LuckAmount = 1,
		IndexLuck = 8,
		rarity = "Common",
		color = rarityColors.Common,
		chance = 500000,
	},
	GreySheep = {
		id = "Grey_Sheep",
		name = "Grey Sheep",
		ShearHealth = 105,
		WoolAmount = 18,
		LuckAmount = 1,
		IndexLuck = 11,
		rarity = "Common",
		color = rarityColors.Common,
		chance = 250000,
	},
	BrownSheep = {
		id = "Brown_Sheep",
		name = "Brown Sheep",
		ShearHealth = 115,
		WoolAmount = 20,
		LuckAmount = 2,
		IndexLuck = 16,
		rarity = "Uncommon",
		color = rarityColors.Uncommon,
		chance = 150000,
	},
	BlackSheep = {
		id = "Black_Sheep",
		name = "Black Sheep",
		ShearHealth = 130,
		WoolAmount = 28,
		LuckAmount = 3,
		IndexLuck = 27,
		rarity = "Uncommon",
		color = rarityColors.Uncommon,
		chance = 60000,
	},
	FluffySheep = {
		id = "Fluffy_Sheep",
		name = "Fluffy Sheep",
		ShearHealth = 145,
		WoolAmount = 35,
		LuckAmount = 5,
		IndexLuck = 41,
		rarity = "Rare",
		color = rarityColors.Rare,
		chance = 30000,
	},
	GoldenSheep = {
		id = "Golden_Sheep",
		name = "Golden Sheep",
		ShearHealth = 175,
		WoolAmount = 50,
		LuckAmount = 10,
		IndexLuck = 94,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 7500,
	},
	EmeraldSheep = {
		id = "Emerald_Sheep",
		name = "Emerald Sheep",
		ShearHealth = 190,
		WoolAmount = 60,
		LuckAmount = 12,
		IndexLuck = 208,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 2000,
	},
	SpottedSheep = {
		id = "Spotted_Sheep",
		name = "Spotted Sheep",
		ShearHealth = 215,
		WoolAmount = 80,
		LuckAmount = 25,
		IndexLuck = 547,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 400,
	},
	DiamondSheep = {
		id = "Diamond_Sheep",
		name = "Diamond Sheep",
		ShearHealth = 250,
		WoolAmount = 100,
		LuckAmount = 60,
		IndexLuck = 1256,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 100,
	},
} :: { [string]: SheepInfo }

--[[
	Luck boosts every tier above Common: a sheep's weight is multiplied by luckFactor ^ (tier index),
	where luckFactor = 1 + LUCK_STRENGTH * log10(1 + luck). The log keeps exponential Luck from breaking the odds.
]]
sheepData.LUCK_STRENGTH = 0.5

local tierIndex: { [string]: number } = {}
for index, rarity in rarityOrder do
	tierIndex[rarity] = index - 1
end

function sheepData.getLuckFactor(luck: number): number
	return 1 + sheepData.LUCK_STRENGTH * math.log10(1 + math.max(luck, 0))
end

local function getWeight(info: SheepInfo, luckFactor: number): number
	return info.chance * luckFactor ^ (tierIndex[info.rarity] or 0)
end

local function getTotalWeight(luckFactor: number): number
	local total = 0
	for _, info in sheepData.Sheep do
		total += getWeight(info, luckFactor)
	end
	return total
end

-- Picks a sheep type name for a player with this much Luck.
function sheepData.roll(luck: number, random: Random?): string?
	local luckFactor = sheepData.getLuckFactor(luck)
	local roll = (random or Random.new()):NextNumber() * getTotalWeight(luckFactor)

	local cumulative = 0
	for name, info in sheepData.Sheep do
		cumulative += getWeight(info, luckFactor)
		if roll <= cumulative then
			return name
		end
	end
	return nil
end

-- N in "1 in N" for this sheep type at this much Luck; nil for an unknown type.
function sheepData.getOdds(name: string, luck: number): number?
	local info = sheepData.Sheep[name]
	if not info then
		return nil
	end

	local luckFactor = sheepData.getLuckFactor(luck)
	return math.max(1, math.floor(getTotalWeight(luckFactor) / getWeight(info, luckFactor) + 0.5))
end

function sheepData.getOddsText(name: string, luck: number): string
	local odds = sheepData.getOdds(name, luck)
	return if odds then `1 in {odds}` else "1 in ?"
end

--[[
	Index Luck: a one-time, permanent reward for claiming a sheep type in the Index (rebirths keep it).
	It follows the type's base "1 in N" odds: INDEX_LUCK_BASE * N ^ INDEX_LUCK_EXPONENT, so rarer sheep are worth far more.
	Sheep:  Basic Grey Brown Black Fluffy Golden Emerald Spotted Diamond   (whole Index: 2,208)
	Luck:   8     11   16    27    41     94     208     547     1256
	A new sheep without an IndexLuck gets this formula automatically.
]]
sheepData.INDEX_LUCK_BASE = 5
sheepData.INDEX_LUCK_EXPONENT = 0.6

local baseTotalWeight = getTotalWeight(1)

function sheepData.getIndexLuck(name: string): number
	local info = sheepData.Sheep[name]
	if not info then
		return 0
	end
	if info.IndexLuck then
		return info.IndexLuck
	end
	local odds = baseTotalWeight / info.chance
	return math.floor(sheepData.INDEX_LUCK_BASE * odds ^ sheepData.INDEX_LUCK_EXPONENT + 0.5)
end

-- Luck from every type claimed in this Index ({ [sheepType]: "Found" | "Claimed" }).
function sheepData.getClaimedIndexLuck(index: { [string]: string }): number
	local total = 0
	for name, status in index do
		if status == "Claimed" then
			total += sheepData.getIndexLuck(name)
		end
	end
	return total
end

-- Every sheep type key, commonest first: the order the Index shows them in.
local indexOrder: { string } = {}
for name in sheepData.Sheep do
	table.insert(indexOrder, name)
end
table.sort(indexOrder, function(a: string, b: string): boolean
	return sheepData.Sheep[a].chance > sheepData.Sheep[b].chance
end)

sheepData.IndexOrder = indexOrder
sheepData.RarityColors = rarityColors
sheepData.RarityOrder = rarityOrder

return sheepData
