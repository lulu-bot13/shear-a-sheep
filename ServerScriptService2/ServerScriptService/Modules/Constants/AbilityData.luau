--!strict

--[[
	Every ability's cooldown, duration, Ability Shack roll odds and tuning stats.
	Location: ServerScriptService.Modules.Constants.AbilityData
]]--

export type AbilityInfo = {
	id: string, -- matches its module in Modules.Abilities, client Modules.Abilities and the Animation in Assets.Animations.Abilities
	name: string,
	description: string,
	rarity: string, -- SheepData.RarityColors key
	chance: number, -- Ability Shack roll weight; 0 = can't be rolled
	halloween: boolean?, -- only rollable during Halloween (owners keep and use it any time)
	duration: number, -- seconds the ability lasts
	cooldown: number, -- seconds from the ability ending until it can be used again
	stats: { [string]: number }, -- read by the ability's own module
}

local abilityData = {}

abilityData.DefaultAbilityId = "Spin"
abilityData.RollCost = 4 -- Gems per Ability Shack roll: ~160 sheep shorn bare at GemData's 1/40 drop, so ~10 min of play

abilityData.Abilities = {
	Spin = {
		id = "Spin",
		name = "Spin",
		description = "Spin with a shear in each hand, shearing everything around you.",
		rarity = "Common",
		chance = 0,
		duration = 3,
		cooldown = 10,
		stats = {
			speedMultiplier = 1.75, -- walk speed while spinning
			hitInterval = 0.1, -- seconds between hits on every sheep in range
			rangeMultiplier = 1.5, -- times the equipped shear's range
			damageMultiplier = 1, -- times the equipped shear's damage, per hit
		},
	},
	Smash = {
		id = "Smash",
		name = "Smash",
		description = "Slam the ground, bursting it upward and shearing every sheep nearby.",
		rarity = "Rare",
		chance = 45,
		duration = 1.2,
		cooldown = 12,
		stats = {
			impactDelay = 0.55, -- seconds into the animation the fist hits the ground
			radius = 22, -- studs
			damageMultiplier = 4, -- times the shear's damage
			woolPercent = 0.2, -- plus this fraction of each sheep's full wool, so it keeps up with big sheep
			walkSpeedMultiplier = 0, -- the player stands planted while slamming
		},
	},
	Clone = {
		id = "Clone",
		name = "Clone",
		description = "Three clones of you run to the nearest sheep and shear them.",
		rarity = "Epic",
		chance = 30,
		duration = 12,
		cooldown = 30,
		stats = {
			count = 3,
			swingInterval = 0.35, -- seconds between each clone's swings (and target updates)
			damageMultiplier = 1, -- times the player's shear damage, per swing, with the shear's range
			walkSpeed = 20,
			spawnRadius = 4, -- studs from the player the clones appear
		},
	},
	BatOverhaul = {
		id = "BatOverhaul",
		name = "Bat Overhaul",
		description = "A swarm of bats covers your plot while your shears fly at every sheep; when the bats leave, they're all bare.",
		rarity = "Legendary",
		chance = 18,
		halloween = true,
		duration = 4.4, -- covers the 0.2s start lead + arrive + swarm + leave
		cooldown = 45,
		stats = {
			arriveSeconds = 0.8, -- the bats sweep in and cover the plot
			swarmSeconds = 2.4, -- the shears snip the wool off in snipPulses bursts over this
			leaveSeconds = 0.9, -- the bats fly off, then every sheep is sheared bare
			snipPulses = 4,
			maxSheep = 40, -- FarmData.MaxSheepCap
		},
	},
	Gravity = {
		id = "Gravity",
		name = "Gravity",
		description = "Lift every sheep on your plot into the sky and shake all of their wool out.",
		rarity = "Mythic",
		chance = 7,
		duration = 3.6, -- covers the 0.2s start lead + rise + hang + fall
		cooldown = 60,
		stats = {
			riseSeconds = 1.4,
			hangSeconds = 1.2, -- the wool is shaken out in shakePulses bursts over this
			fallSeconds = 0.55,
			height = 18, -- studs the sheep float up; wool drops only find the ground within ~22 studs below them
			shakePulses = 3,
			maxSheep = 40, -- FarmData.MaxSheepCap
		},
	},
} :: { [string]: AbilityInfo }

function abilityData.get(id: any): AbilityInfo?
	return if type(id) == "string" then abilityData.Abilities[id] else nil
end

--// Ability Shack ---------------------------------------------------------------

abilityData.Order = { "Spin", "Smash", "Clone", "BatOverhaul", "Gravity" } -- commonest first, for the UI
abilityData.RenamedAbilities = { PumpkinSplash = "BatOverhaul" } :: { [string]: string } -- old ids still in saved data, and what they became
abilityData.PityRolls = 10 -- this many rolls in a row without a pity rarity makes the last one a guaranteed pity rarity
abilityData.PityRarities = { Legendary = true, Mythic = true }
abilityData.PityLabel = "Legendary+"
abilityData.DuplicateRefund = { -- fraction of RollCost given back as Gems (rounded down) for rolling one already owned
	Rare = 0.25,
	Epic = 0.4,
	Legendary = 0.6,
	Mythic = 1,
}

-- Halloween abilities weigh 0 unless `halloween` is true.
local function getWeight(ability: AbilityInfo, pityOnly: boolean, halloween: boolean?): number
	if (pityOnly and not abilityData.PityRarities[ability.rarity]) or (ability.halloween and not halloween) then
		return 0
	end
	return math.max(ability.chance, 0)
end

local function getTotalWeight(pityOnly: boolean, halloween: boolean?): number
	local total = 0
	for _, id in abilityData.Order do
		total += getWeight(abilityData.Abilities[id], pityOnly, halloween)
	end
	return total
end

-- 0-1 chance a normal roll lands on this ability; Halloween abilities are 0 unless `halloween` is true.
function abilityData.getChance(id: string, halloween: boolean?): number
	local ability = abilityData.get(id)
	local total = getTotalWeight(false, halloween)
	return if ability and total > 0 then getWeight(ability, false, halloween) / total else 0
end

-- A weighted pick from every rollable ability, or only the pity rarities when `pityOnly`. Halloween abilities need `halloween`.
function abilityData.roll(random: Random, pityOnly: boolean, halloween: boolean?): AbilityInfo
	local total = getTotalWeight(pityOnly, halloween)
	if total <= 0 then
		return if pityOnly then abilityData.roll(random, false, halloween) else abilityData.Abilities[abilityData.DefaultAbilityId]
	end

	local pick = random:NextNumber() * total
	local last = abilityData.Abilities[abilityData.DefaultAbilityId]
	for _, id in abilityData.Order do
		local ability = abilityData.Abilities[id]
		local weight = getWeight(ability, pityOnly, halloween)
		if weight > 0 then
			last = ability
			pick -= weight
			if pick <= 0 then
				return ability
			end
		end
	end
	return last
end

return abilityData
