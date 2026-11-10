--!strict

--[[
	Which sheep types can spawn at each rebirth tier (and Prestige), and the sheep each tier needs found to rebirth.
	Location: ServerScriptService.Modules.Constants.SheepPools
]]--

export type Tier = {
	minRebirths: number,
	adds: { string }, -- adult SheepData keys (their Baby/Giant variants follow them)
	drops: { string },
	required: string?, -- found in the Index (any variant or mutation) before rebirthing out of this tier
	huntScale: number?, -- the required sheep's spawn weight multiplier while in this tier
	pity: number?, -- spawns until the required sheep is forced, while it's still unfound
}

export type PrestigeTier = {
	minPrestiges: number,
	adds: { string },
	drops: { string },
}

local sheepPools = {}

--[[
	Hunt tuning (active play, max Spawn Luck for the tier, typical Luck): Halloween types keep their Night gating.
	         rolls/min  0 SL odds    max SL odds   mean find   pity (~10 min)
	Fluffy   ~20        1 in 34      1 in 23       ~0.6 min    15 (kept short for the tutorial's rebirth)
	Golden   ~35        1 in 645     1 in 307      ~6 min      350
	Spotted  ~50        1 in 1,456   1 in 436      ~6 min      500
	Diamond  ~65        1 in 3,250   1 in 533      ~5.8 min    650
	Obsidian ~80        1 in 5,503   1 in 869      ~6.5 min    800
]]
sheepPools.Tiers = {
	{ minRebirths = 0, adds = { "Basic", "Grey", "Brown", "Black", "Fluffy", "Mustache", "Pumpkin" }, drops = {}, required = "Fluffy", pity = 15 },
	{ minRebirths = 1, adds = { "Ice", "CottonCandy", "Golden", "Cactus" }, drops = {}, required = "Golden", huntScale = 0.1, pity = 350 },
	{ minRebirths = 3, adds = { "Emerald", "Lucky", "Spotted", "Stone", "Mummy" }, drops = { "Basic" }, required = "Spotted", huntScale = 0.15, pity = 500 },
	{ minRebirths = 5, adds = { "Ruby", "Robot", "Diamond", "Square", "Ninja" }, drops = { "Grey" }, required = "Diamond", huntScale = 0.06, pity = 650 },
	{ minRebirths = 8, adds = { "Wizard", "Rainbow", "Obsidian", "Vampire" }, drops = { "Brown" }, required = "Obsidian", huntScale = 0.025, pity = 800 },
} :: { Tier }

sheepPools.PrestigeTiers = {
	{ minPrestiges = 1, adds = { "Alien", "Princess" }, drops = { "Black" } },
} :: { PrestigeTier }

-- Rebirths past this (Prestige's requirement) keep the last tier's pool and need no sheep: only a Prestige is left to do.
sheepPools.REQUIREMENT_ENDS_AT = 10

-- The tier a player with this many rebirths is in.
function sheepPools.getTier(rebirths: number): Tier
	local current = sheepPools.Tiers[1]
	for _, tier in sheepPools.Tiers do
		if rebirths >= tier.minRebirths then
			current = tier
		end
	end
	return current
end

-- Adult type keys that can spawn: { [key]: true }.
function sheepPools.getPool(rebirths: number, prestiges: number): { [string]: boolean }
	local pool: { [string]: boolean } = {}
	local function apply(adds: { string }, drops: { string })
		for _, key in adds do
			pool[key] = true
		end
		for _, key in drops do
			pool[key] = nil
		end
	end
	for _, tier in sheepPools.Tiers do
		if rebirths >= tier.minRebirths then
			apply(tier.adds, tier.drops)
		end
	end
	for _, tier in sheepPools.PrestigeTiers do
		if prestiges >= tier.minPrestiges then
			apply(tier.adds, tier.drops)
		end
	end
	return pool
end

-- Adult key -> spawn weight multiplier for this tier (the required sheep's hunt scale).
function sheepPools.getScales(rebirths: number): { [string]: number }
	local tier = sheepPools.getTier(rebirths)
	return if tier.required and tier.huntScale then { [tier.required] = tier.huntScale } else {}
end

-- The sheep that must be found before rebirth number `rebirths + 1`, and its pity; nil when none is needed.
function sheepPools.getRequirement(rebirths: number): (string?, number)
	if rebirths >= sheepPools.REQUIREMENT_ENDS_AT then
		return nil, 0
	end
	local tier = sheepPools.getTier(rebirths)
	return tier.required, tier.pity or 0
end

return sheepPools
