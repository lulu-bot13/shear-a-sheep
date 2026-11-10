--!strict

--[[
	Every sheep type (wool health, wool and Luck it gives, rarity, base spawn weight) and the luck-weighted spawn roll.

	Location: ServerScriptService.Modules.Constants.SheepData
]]--

local SpawnOdds = require(game:GetService("ReplicatedStorage").Shared.Utils.SpawnOdds)
local MutationData = require(script.Parent.MutationData)
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
	baby: boolean?, -- a scaled-down copy of its adult
	variant: string?, -- "Baby" or "Giant" for a copy of an adult type (see Variants); nil = the adult itself
	adult: string?, -- variants only: the adult type it's a copy of
	halloween: boolean?, -- only spawns during Halloween mode (Night)
	idleAnimation: string?, -- its own looped idle; nil = the adult/baby default in IdleAnimations
	rarity: string,
	color: Color3,
	chance: number, -- base spawn weight (before luck); an adult's is its share after the Baby/Giant split
	typeChance: number?, -- adults only: the whole type's weight (adult + variants), which the roll uses
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
		halloween = true,
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
		halloween = true,
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
		halloween = true,
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
	Mustache = {
		id = "Mustache_Sheep",
		name = "Mustache Sheep",
		ShearHealth = 180,
		WoolAmount = 36,
		LuckAmount = 4,
		rarity = "Uncommon",
		color = rarityColors.Uncommon,
		chance = 15000,
	},
	Cactus = {
		id = "Cactus_Sheep",
		name = "Cactus Sheep",
		ShearHealth = 220,
		WoolAmount = 54,
		LuckAmount = 9,
		rarity = "Rare",
		color = rarityColors.Rare,
		chance = 6000,
	},
	Square = {
		id = "Square_Sheep",
		name = "Square Sheep",
		ShearHealth = 245,
		WoolAmount = 64,
		LuckAmount = 13,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 2500,
	},
	Ninja = {
		id = "Ninja_Sheep",
		name = "Ninja Sheep",
		ShearHealth = 255,
		WoolAmount = 70,
		LuckAmount = 15,
		rarity = "Epic",
		color = rarityColors.Epic,
		chance = 1500,
	},
	Princess = {
		id = "Princess_Sheep",
		name = "Princess Sheep",
		ShearHealth = 420,
		WoolAmount = 175,
		LuckAmount = 130,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 10, -- the rarest sheep
	},
	Robot = {
		id = "Robot_Sheep",
		name = "Robot Sheep",
		ShearHealth = 300,
		WoolAmount = 100,
		LuckAmount = 38,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 150,
	},
	Wizard = {
		id = "Wizard_Sheep",
		name = "Wizard Sheep",
		ShearHealth = 320,
		WoolAmount = 112,
		LuckAmount = 50,
		rarity = "Legendary",
		color = rarityColors.Legendary,
		chance = 100,
	},
	Alien = {
		id = "Alien_Sheep",
		name = "Alien Sheep",
		ShearHealth = 380,
		WoolAmount = 155,
		LuckAmount = 110,
		rarity = "Mythic",
		color = rarityColors.Mythic,
		chance = 25,
	},

} :: { [string]: SheepInfo }

export type VariantInfo = {
	id: string, -- prefix of the type key and name: "Baby" -> BabyBasic / "Baby Basic Sheep"
	folder: string, -- its models live in Assets.Models.Sheeps.<folder>, named by type key
	share: number, -- of the adult's spawn weight
	scale: number, -- times the adult model's scale, for models SheepHandler makes
	health: number, -- ShearHealth multiplier
	wool: number, -- WoolAmount multiplier
	luck: number, -- LuckAmount multiplier
	weight: number, -- times the size tier's weight range
}

--[[
	Every type gets a Baby and a Giant copy. Their models live in Assets.Models.Sheeps.BabySheeps / GiantSheeps;
	SheepHandler makes any that are missing by scaling the adult's model. The type's spawn weight is split between
	the three, so its overall odds stay the same (adult 30%, baby 60%, giant 10%; the Sheep Size upgrade shifts these, see SpawnOdds).
]]
sheepData.Variants = {
	{ id = "Baby", folder = "BabySheeps", share = 0.6, scale = 0.6, health = 1, wool = 1, luck = 1, weight = 0.4 },
	{ id = "Giant", folder = "GiantSheeps", share = 0.1, scale = 1.5, health = 1.8, wool = 2.5, luck = 2, weight = 2.5 },
} :: { VariantInfo }

local variantsById: { [string]: VariantInfo } = {}
for _, variant in sheepData.Variants do
	variantsById[variant.id] = variant
end

local adultKeys: { string } = {}
for key in sheepData.Sheep do
	table.insert(adultKeys, key)
end
for _, key in adultKeys do
	local base = sheepData.Sheep[key]
	base.typeChance = base.chance
	local adultShare = 1
	for _, variant in sheepData.Variants do
		sheepData.Sheep[`{variant.id}{key}`] = {
			id = `{variant.id}_{base.id}`,
			name = `{variant.id} {base.name}`,
			ShearHealth = math.floor(base.ShearHealth * variant.health + 0.5),
			WoolAmount = math.floor(base.WoolAmount * variant.wool + 0.5),
			LuckAmount = math.floor(base.LuckAmount * variant.luck + 0.5),
			luckDrops = base.luckDrops,
			baby = variant.id == "Baby" or nil,
			variant = variant.id,
			adult = key,
			halloween = base.halloween,
			idleAnimation = if variant.id == "Baby" then nil else base.idleAnimation, -- babies are a different rig
			rarity = base.rarity,
			color = base.color,
			chance = base.chance * variant.share,
		}
		adultShare -= variant.share
	end
	base.chance *= adultShare
end

--[[
	The Night event's Reapers (ReaperEventHandler spawns them; tuned for a ~10 minute player, Large Shears at 51 damage:
	King ~59 swings / 20 s, Small ~3 swings). Never rolled, and not in the Index, variants or best finds.
]]
sheepData.Bosses = {
	KingReaper = {
		id = "King_Reaper",
		name = "King Reaper",
		ShearHealth = 3000,
		WoolAmount = 600,
		LuckAmount = 60,
		halloween = true,
		idleAnimation = "rbxassetid://110116382654217",
		rarity = "Boss",
		color = Color3.fromRGB(88, 28, 135),
		chance = 0,
	},
	SmallReaper = {
		id = "Small_Reaper",
		name = "Small Reaper",
		ShearHealth = 150,
		WoolAmount = 30,
		LuckAmount = 4,
		baby = true, -- built on the baby rig
		halloween = true,
		idleAnimation = "rbxassetid://134593521798711",
		rarity = "Minion",
		color = Color3.fromRGB(75, 85, 99),
		chance = 0,
	},
} :: { [string]: SheepInfo }

-- A sheep type or boss by model name.
function sheepData.getInfo(name: string): SheepInfo?
	return sheepData.Sheep[name] or sheepData.Bosses[name]
end

-- Looped idles (4 s, priority Idle). "" = not published yet, so that sheep stands without one.
sheepData.IdleAnimations = {
	Adult = "rbxassetid://78449727128378", -- Sheep_Idle
	Baby = "", -- BabySheep_Idle
}

-- The idle animation id for a sheep model name, or nil if it has none.
function sheepData.getIdleAnimation(name: string): string?
	local info = sheepData.getInfo(name)
	if not info then
		return nil
	end
	local id = info.idleAnimation or (if info.baby then sheepData.IdleAnimations.Baby else sheepData.IdleAnimations.Adult)
	return if id ~= "" then id else nil
end

-- The Baby/Giant variant a sheep type is; nil for an adult or an unknown type.
function sheepData.getVariant(name: string): VariantInfo?
	local info = sheepData.Sheep[name]
	return if info and info.variant then variantsById[info.variant] else nil
end

--[[
	Luck boosts every tier above Common: a type's weight is multiplied by luckFactor ^ (tier index), where luckFactor is
	SpawnOdds.getLuckFactor (Luck, the rebirth and Prestige multipliers, Spawn Luck and any boost). The roll picks a type
	(from the player's SheepPools pool, if given), then its Baby / adult / Giant variant by the Sheep Size level.
]]
sheepData.LUCK_STRENGTH = SpawnOdds.LUCK_STRENGTH
sheepData.LUCK_SCALE = SpawnOdds.LUCK_SCALE

-- Everything a spawn roll depends on. `pool` = adult keys that can spawn (nil = every type); `scales` = adult key -> weight multiplier.
export type RollContext = {
	luck: number,
	rebirths: number,
	prestiges: number,
	boost: number?,
	halloween: boolean?,
	spawnLuck: number?,
	sizeLevel: number?,
	pool: { [string]: boolean }?,
	scales: { [string]: number }?,
}

local tierIndex: { [string]: number } = {}
for index, rarity in rarityOrder do
	tierIndex[rarity] = index - 1
end

function sheepData.getLuckFactor(luck: number, rebirths: number, prestiges: number, boost: number?, spawnLuck: number?): number
	return SpawnOdds.getLuckFactor(luck, RebirthData.getLuckMultiplier(rebirths), PrestigeData.getLuckMultiplier(prestiges), spawnLuck, boost)
end

local function getContextLuckFactor(context: RollContext): number
	return sheepData.getLuckFactor(context.luck, context.rebirths, context.prestiges, context.boost, context.spawnLuck)
end

-- An adult type's whole spawn weight; 0 outside the pool, and for Halloween types unless `halloween` is true.
local function getTypeWeight(key: string, luckFactor: number, context: RollContext, halloween: boolean?): number
	local info = sheepData.Sheep[key]
	if info.halloween and not halloween then
		return 0
	elseif context.pool and not context.pool[key] then
		return 0
	end
	local scale = if context.scales then context.scales[key] or 1 else 1
	return (info.typeChance or info.chance) * luckFactor ^ (tierIndex[info.rarity] or 0) * scale
end

local function getTotalWeight(luckFactor: number, context: RollContext, halloween: boolean?): number
	local total = 0
	for _, key in adultKeys do
		total += getTypeWeight(key, luckFactor, context, halloween)
	end
	return total
end

-- The share of an adult type's spawns that are this sheep (its variant's share, or what's left for the adult).
local function getVariantShare(name: string, sizeLevel: number?): number
	local info = sheepData.Sheep[name]
	local adultShare = 1
	for _, variant in sheepData.Variants do
		local share = SpawnOdds.getVariantShare(variant.id, variant.share, sizeLevel)
		if info.variant == variant.id then
			return share
		end
		adultShare -= share
	end
	return math.max(adultShare, 0)
end

-- Picks the Baby, adult or Giant of an adult type by the Sheep Size level; returns its type key.
function sheepData.rollVariant(adultKey: string, sizeLevel: number?, random: Random?): string
	local roll = (random or Random.new()):NextNumber()
	local cumulative = 0
	for _, variant in sheepData.Variants do
		cumulative += SpawnOdds.getVariantShare(variant.id, variant.share, sizeLevel)
		if roll < cumulative then
			return `{variant.id}{adultKey}`
		end
	end
	return adultKey
end

-- Picks a sheep type key (variant included) for this roll context; Halloween types only when context.halloween is true.
function sheepData.rollWith(context: RollContext, random: Random?): string?
	local rng = random or Random.new()
	local luckFactor = getContextLuckFactor(context)
	local roll = rng:NextNumber() * getTotalWeight(luckFactor, context, context.halloween)

	local cumulative = 0
	for _, key in adultKeys do
		local weight = getTypeWeight(key, luckFactor, context, context.halloween)
		cumulative += weight
		if weight > 0 and roll < cumulative then
			return sheepData.rollVariant(key, context.sizeLevel, rng)
		end
	end
	return nil
end

--[[
	N in "1 in N" for this sheep type (variant included) in this roll context; nil for an unknown type or one that can't
	spawn (outside the pool). A Halloween sheep outside Halloween gets its Halloween odds, so the Index can still show them.
]]
function sheepData.getOddsWith(name: string, context: RollContext, anyVariant: boolean?): number?
	local info = sheepData.Sheep[name]
	if not info then
		return nil
	end

	local includeHalloween = context.halloween or info.halloween
	local luckFactor = getContextLuckFactor(context)
	local share = if anyVariant then 1 else getVariantShare(name, context.sizeLevel)
	local weight = getTypeWeight(info.adult or name, luckFactor, context, includeHalloween) * share
	if weight <= 0 then
		return nil
	end
	return math.max(1, math.floor(getTotalWeight(luckFactor, context, includeHalloween) / weight + 0.5))
end

-- Odds of any Baby, adult or Giant of this type (what finding a rebirth sheep needs).
function sheepData.getTypeOddsWith(name: string, context: RollContext): number?
	return sheepData.getOddsWith(name, context, true)
end

function sheepData.getOddsTextWith(name: string, context: RollContext): string
	if sheepData.Bosses[name] then
		return "Night Event"
	end
	local odds = sheepData.getOddsWith(name, context)
	return if odds then `1 in {odds}` else "1 in ?"
end

-- The older calls: every type can spawn and the split is the base one.
function sheepData.roll(luck: number, rebirths: number, prestiges: number, random: Random?, boost: number?, halloween: boolean?): string?
	return sheepData.rollWith({ luck = luck, rebirths = rebirths, prestiges = prestiges, boost = boost, halloween = halloween }, random)
end

-- N in "1 in N" for this sheep type with this Luck, rebirths and Prestiges (all 0 = base odds); nil for an unknown type.
function sheepData.getOdds(name: string, luck: number, rebirths: number, prestiges: number, boost: number?, halloween: boolean?): number?
	return sheepData.getOddsWith(name, { luck = luck, rebirths = rebirths, prestiges = prestiges, boost = boost, halloween = halloween })
end

function sheepData.getOddsText(name: string, luck: number, rebirths: number, prestiges: number, boost: number?, halloween: boolean?): string
	return sheepData.getOddsTextWith(name, { luck = luck, rebirths = rebirths, prestiges = prestiges, boost = boost, halloween = halloween })
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

local baseTotalWeight = 0 -- every type, Halloween ones included, so Index Luck doesn't depend on the season
for _, info in sheepData.Sheep do
	baseTotalWeight += info.chance
end

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

--[[
	Index keys in a player's SheepIndex: the plain sheep type for the Normal page, "<mutation id>:<type>" for a mutation's
	page (e.g. "Rainbow:Basic"), so saves from before the mutation pages need no migration.
]]
sheepData.INDEX_KEY_SEPARATOR = ":"

function sheepData.getIndexKey(sheepType: string, mutationId: string?): string
	return if mutationId then `{mutationId}{sheepData.INDEX_KEY_SEPARATOR}{sheepType}` else sheepType
end

-- The sheep type and mutation (nil = Normal) an Index key stands for; nil for an unknown type or mutation.
function sheepData.parseIndexKey(key: any): (string?, MutationData.MutationInfo?)
	if type(key) ~= "string" then
		return nil, nil
	end
	local split = string.find(key, sheepData.INDEX_KEY_SEPARATOR, 1, true)
	if not split then
		if sheepData.Sheep[key] then
			return key, nil
		end
		return nil, nil
	end

	local mutation = MutationData.get(string.sub(key, 1, split - 1))
	local sheepType = string.sub(key, split + #sheepData.INDEX_KEY_SEPARATOR)
	if not mutation or not sheepData.Sheep[sheepType] then
		return nil, nil
	end
	return sheepType, mutation
end

-- An Index entry's claim reward: its type's IndexLuck times its mutation's luck multiplier; 0 for an unknown key.
function sheepData.getIndexEntryLuck(key: string): number
	local sheepType, mutation = sheepData.parseIndexKey(key)
	if not sheepType then
		return 0
	end
	local luck = sheepData.getIndexLuck(sheepType)
	return if mutation then math.floor(luck * mutation.luck + 0.5) else luck
end

-- Luck from every entry claimed in this Index ({ [index key]: "Found" | "Claimed" }); unknown keys count for nothing.
function sheepData.getClaimedIndexLuck(index: { [string]: string }): number
	local total = 0
	for key, status in index do
		if status == "Claimed" then
			total += sheepData.getIndexEntryLuck(key)
		end
	end
	return total
end

-- The order the Index shows them in: a row per adult type (commonest first) of its Baby, itself, then its Giant.
table.sort(adultKeys, function(a: string, b: string): boolean
	return sheepData.Sheep[a].chance > sheepData.Sheep[b].chance
end)
local indexOrder: { string } = {}
for _, key in adultKeys do
	table.insert(indexOrder, `Baby{key}`)
	table.insert(indexOrder, key)
	table.insert(indexOrder, `Giant{key}`)
end

sheepData.IndexOrder = indexOrder
sheepData.RarityColors = rarityColors
sheepData.RarityOrder = rarityOrder

return sheepData
