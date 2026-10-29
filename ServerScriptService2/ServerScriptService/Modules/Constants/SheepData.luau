--!strict

--[[
	Every sheep type (wool health, wool and Luck it gives, rarity, base spawn weight) and the luck-weighted spawn roll.

	Location: ServerScriptService.Modules.Constants.SheepData
]]--

local PrestigeData = require(script.Parent.PrestigeData)
local RebirthData = require(script.Parent.RebirthData)

export type SheepInfo = {
	id: string,
	name: string,
	ShearHealth: number,
	WoolAmount: number,
	LuckAmount: number, -- Luck the player earns for shearing it bare
	IndexLuck: number?, -- permanent Luck for claiming it in the Index once; nil = worked out from its odds
	luckDrops: boolean?, -- shearing it only drops Luck on the ground (its wool still pays out)
	baby: boolean?, -- its model lives in Assets.Models.Sheeps.BabySheeps
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
	Grey = {
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
	Brown = {
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
	Black = {
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
	Fluffy = {
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
	Golden = {
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
	Emerald = {
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
	Lucky = {
		id = "Luck_Sheep",
		name = "Luck Sheep",
		ShearHealth = 200,
		WoolAmount = 150,
		LuckAmount = 125,
		IndexLuck = 456,
		luckDrops = true,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 2100,
	},
	Spotted = {
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
	Diamond = {
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
	Pumpkin = {
		id = "Pumpkin_Sheep",
		name = "Pumpkin Sheep",
		ShearHealth = 150,
		WoolAmount = 40,
		LuckAmount = 6,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 500,
	},
	Ice = {
		id = "Ice_Sheep",
		name = "Ice Sheep",
		ShearHealth = 160,
		WoolAmount = 42,
		LuckAmount = 7,
		rarity = "Rare",
		color = rarityColors.Rare,
		chance = 20000,
	},
	Mummy = {
		id = "Mummy_Sheep",
		name = "Mummy Sheep",
		ShearHealth = 185,
		WoolAmount = 55,
		LuckAmount = 11,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 5000,
	},
	Ruby = {
		id = "Ruby_Sheep",
		name = "Ruby Sheep",
		ShearHealth = 230,
		WoolAmount = 85,
		LuckAmount = 35,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 300,
	},
	Vampire = {
		id = "Vampire_Sheep",
		name = "Vampire Sheep",
		ShearHealth = 240,
		WoolAmount = 95,
		LuckAmount = 45,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 200,
	},
	Obsidian = {
		id = "Obsidian_Sheep",
		name = "Obsidian Sheep",
		ShearHealth = 270,
		WoolAmount = 120,
		LuckAmount = 80,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 60,
	},
	Stone = {
		id = "Stone_Sheep",
		name = "Stone Sheep",
		ShearHealth = 225,
		WoolAmount = 32,
		LuckAmount = 2,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 5050,
	},
	CottonCandy = {
		id = "CottonCandy_Sheep",
		name = "Cotton Candy Sheep",
		ShearHealth = 155,
		WoolAmount = 38,
		LuckAmount = 6,
		rarity = "Rare",
		color = rarityColors.Rare,
		chance = 22000,
	},
	Rainbow = {
		id = "Rainbow_Sheep",
		name = "Rainbow Sheep",
		ShearHealth = 260,
		WoolAmount = 110,
		LuckAmount = 70,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 80,
	},

} :: { [string]: SheepInfo }

--[[
	Baby sheep: every "Baby<Type>" model in Assets.Models.Sheeps.BabySheeps becomes a copy of <Type>.
	The type's spawn weight is split between them, so its overall odds stay the same: BABY_SHARE of the time it's the baby.
]]
sheepData.BABY_SHARE = 0.6

local babyModels = game:GetService("ReplicatedStorage").Assets.Models.Sheeps:FindFirstChild("BabySheeps")
if babyModels then
	for _, model in babyModels:GetChildren() do
		local baseKey = string.match(model.Name, "^Baby(.+)$")
		local base = baseKey and sheepData.Sheep[baseKey]
		if not model:IsA("Model") or not base or base.baby then
			warn(`SheepData: '{model.Name}' in BabySheeps doesn't match a sheep type (expected Baby<Type>).`)
			continue
		end

		sheepData.Sheep[model.Name] = {
			id = `Baby_{base.id}`,
			name = `Baby {base.name}`,
			ShearHealth = base.ShearHealth,
			WoolAmount = base.WoolAmount,
			LuckAmount = base.LuckAmount,
			luckDrops = base.luckDrops,
			baby = true,
			rarity = base.rarity,
			color = base.color,
			chance = base.chance * sheepData.BABY_SHARE,
		}
		base.chance *= 1 - sheepData.BABY_SHARE
	end
end

--[[
	Luck boosts every tier above Common: a sheep's weight is multiplied by luckFactor ^ (tier index), where
	luckFactor = (1 + LUCK_STRENGTH * log10(1 + luck / LUCK_SCALE)) * the rebirth and Prestige luck multipliers.
]]
sheepData.LUCK_STRENGTH = 0.5
sheepData.LUCK_SCALE = 100

local tierIndex: { [string]: number } = {}
for index, rarity in rarityOrder do
	tierIndex[rarity] = index - 1
end

function sheepData.getLuckFactor(luck: number, rebirths: number, prestiges: number, boost: number?): number
	local luckPart = 1 + sheepData.LUCK_STRENGTH * math.log10(1 + math.max(luck, 0) / sheepData.LUCK_SCALE)
	return luckPart * RebirthData.getLuckMultiplier(rebirths) * PrestigeData.getLuckMultiplier(prestiges) * (boost or 1)
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

-- Picks a sheep type name for a player with this much Luck, rebirths and Prestiges; `boost` multiplies the luck factor (e.g. Night).
function sheepData.roll(luck: number, rebirths: number, prestiges: number, random: Random?, boost: number?): string?
	local luckFactor = sheepData.getLuckFactor(luck, rebirths, prestiges, boost)
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

-- N in "1 in N" for this sheep type with this Luck, rebirths and Prestiges (all 0 = base odds); nil for an unknown type.
function sheepData.getOdds(name: string, luck: number, rebirths: number, prestiges: number, boost: number?): number?
	local info = sheepData.Sheep[name]
	if not info then
		return nil
	end

	local luckFactor = sheepData.getLuckFactor(luck, rebirths, prestiges, boost)
	return math.max(1, math.floor(getTotalWeight(luckFactor) / getWeight(info, luckFactor) + 0.5))
end

function sheepData.getOddsText(name: string, luck: number, rebirths: number, prestiges: number, boost: number?): string
	local odds = sheepData.getOdds(name, luck, rebirths, prestiges, boost)
	return if odds then `1 in {odds}` else "1 in ?"
end

--[[
	Index Luck: a one-time, permanent reward for claiming a sheep type in the Index (Prestiges keep it).
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
