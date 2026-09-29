--[[
	Shearing tuning: tool stats, the weak points on a sheep that the shearing
	mini-game spawns circles on, and how hard each rarity is to shear.

	Location: ServerScriptService.Modules.Constants.ShearData
]]--

local shearData = {}

-- Worker (automation) damage per tick. Manual shearing uses HitDamage below instead.
shearData.Default = {
	name = "Basic Shear",
	damage = 25,
}

--// Mini-game rules -----------------------------------------------------------

-- Damage of a x1.0 weak point. Each point multiplies this by its own multiplier.
shearData.HitDamage = 8

-- Popping every circle of a wave inside the rarity's critWindow multiplies that
-- wave's total damage by this (the extra damage is applied when the last circle pops).
shearData.CritMultiplier = 2.5

-- How many circles pop up at once.
shearData.WaveSize = 3

-- Pause between one wave being finished/expired and the next one appearing.
shearData.WaveGapSeconds = 0.45

-- Delay before the first wave so the camera has time to swing round to the sheep.
shearData.FirstWaveDelaySeconds = 1

-- Extra time (latency allowance) the server still accepts a hit after a circle's lifetime.
shearData.HitGraceSeconds = 0.35

-- Circles on the same wave must be at least this far apart on the sheep (studs).
shearData.MinPointSeparation = 1.2

--[[
	Weak points, in the sheep's HumanoidRootPart space:
	+X = the flank the camera looks at, -Z = towards the head, +Y = up.
	multiplier = damage multiplier, weight = how often it gets picked.
]]--
shearData.WeakPoints = {
	{ id = "Head",     offset = Vector3.new(0.3, 1.3, -1.95),  multiplier = 2.0,  weight = 1 },
	{ id = "Shoulder", offset = Vector3.new(1.0, 0.65, -1.0),  multiplier = 1.25, weight = 2 },
	{ id = "Back",     offset = Vector3.new(0.7, 1.15, 0.45),  multiplier = 1.0,  weight = 3 },
	{ id = "Flank",    offset = Vector3.new(1.1, -0.1, -0.25), multiplier = 1.0,  weight = 3 },
	{ id = "Rump",     offset = Vector3.new(1.0, 0.6, 1.5),    multiplier = 1.5,  weight = 2 },
	{ id = "Belly",    offset = Vector3.new(0.9, -0.9, 0.4),   multiplier = 1.25, weight = 2 },
	{ id = "Tail",     offset = Vector3.new(0.3, -0.2, 2.2),   multiplier = 1.5,  weight = 1.5 },
}

--[[
	Difficulty per sheep rarity (keys match SheepData rarity names). Rarer sheep also
	have more ShearHealth (see SheepData), so they take longer on top of this.

	lifetime   seconds a circle stays up before it's a miss
	critWindow seconds the whole wave must be popped within for a critical
	sizeScale  circle size multiplier (smaller = harder to hit)
	missHeal   fraction of the sheep's max health it regrows per missed circle
]]--
shearData.RarityDifficulty = {
	Common    = { lifetime = 2.6,  critWindow = 1.4,  sizeScale = 1.0,  missHeal = 0 },
	Uncommon  = { lifetime = 2.3,  critWindow = 1.25, sizeScale = 0.93, missHeal = 0 },
	Rare      = { lifetime = 2.0,  critWindow = 1.1,  sizeScale = 0.86, missHeal = 0.02 },
	Epic      = { lifetime = 1.7,  critWindow = 0.95, sizeScale = 0.8,  missHeal = 0.03 },
	Legendary = { lifetime = 1.45, critWindow = 0.8,  sizeScale = 0.74, missHeal = 0.04 },
	Mythic    = { lifetime = 1.2,  critWindow = 0.7,  sizeScale = 0.68, missHeal = 0.05 },
}

function shearData.getDifficulty(rarity: string?)
	return shearData.RarityDifficulty[rarity or "Common"] or shearData.RarityDifficulty.Common
end

return shearData
