--!strict

--[[
	Every tuning value of the shearing timing mini-game, in one place.

	The timing bar runs from 0 (left end) to 1 (right end). A cursor bounces along it and the player
	presses while it moves; how close it is to the sweet spot decides the accuracy tier and the damage
	done to the sheep's wool. The sweet spot moves to a new random spot after every attempt.

	Zone sizes are total widths as a fraction of the bar, centred on the sweet spot, and each zone
	contains the ones inside it (the GOOD zone includes GREAT and PERFECT).

	This lives in ReplicatedStorage so the client draws exactly the zones the server scores against.
	The server is still the only side that applies damage and pays out wool.

	Location: ReplicatedStorage.Shared.Constants.ShearTimingData
]]--

export type Tier = "PERFECT" | "GREAT" | "GOOD" | "POOR" | "MISS"

export type DamageRange = { min: number, max: number }

-- A shear's effect on the mini-game. All multipliers: 1 = the basic shear.
export type ShearStats = {
	damageMultiplier: number, -- scales every hit's damage
	zoneScale: number, -- scales the width of every zone (bigger = easier)
	cursorSpeed: number, -- scales how fast the cursor moves (bigger = faster shearing, harder timing)
}

export type RarityModifier = {
	cursorSpeed: number,
	zoneScale: number,
}

local shearTimingData = {}

--// Wool -----------------------------------------------------------------------------

--[[
	The damage values below are balanced for a sheep with this much wool. Each sheep's real wool
	health comes from SheepData.ShearHealth (100 for a Basic sheep, 250 for a Diamond one). With
	ScaleDamageToWoolHealth on, hits on woollier sheep are scaled up by (sheep wool / this), so
	every sheep takes about the same number of hits (rarer sheep are harder through RarityModifiers
	instead). Turn it off to make woollier sheep take more hits.
]]--
shearTimingData.StartingWoolHealth = 100
shearTimingData.ScaleDamageToWoolHealth = true

--// Damage per accuracy tier ------------------------------------------------------------
-- Within a tier, a press closer to the centre of the sweet spot deals closer to `max`.

shearTimingData.PerfectDamage = { min = 30, max = 40 } :: DamageRange
shearTimingData.GreatDamage = { min = 22, max = 30 } :: DamageRange
shearTimingData.GoodDamage = { min = 12, max = 22 } :: DamageRange
shearTimingData.PoorDamage = { min = 3, max = 10 } :: DamageRange
shearTimingData.MissDamage = 2 -- pressed outside every zone
shearTimingData.TimeoutDamage = 0 -- didn't press before TimeLimit ran out

--// Zones (total width, fraction of the bar) -------------------------------------------

shearTimingData.PerfectZoneSize = 0.15
shearTimingData.GreatZoneSize = 0.20
shearTimingData.GoodZoneSize = 0.34
shearTimingData.PoorZoneSize = 0.56

--// Cursor and pacing ------------------------------------------------------------------

shearTimingData.CursorSpeed = 1.1 -- bar widths per second; the cursor bounces between the two ends
shearTimingData.MinimumSweetSpotPosition = 0.15 -- the sweet spot's centre always lands between these two
shearTimingData.MaximumSweetSpotPosition = 0.85
shearTimingData.MinimumSweetSpotShift = 0.2 -- each new sweet spot lands at least this far from the previous one
shearTimingData.TimeLimit = 2.5 -- seconds per attempt before it counts as a miss
shearTimingData.CooldownBetweenAttempts = 0.03 -- pause after an attempt before the next sweet spot appears
shearTimingData.FirstAttemptDelay = 0.6 -- lets the camera swing round to the sheep first

--// Server checks ------------------------------------------------------------------------

shearTimingData.MaxShearingDistance = 14 -- studs from the pen's PlayerPos to start or keep shearing
shearTimingData.LatencyAllowance = 0.1 -- a reported press may come from up to this many seconds ago (ping)
shearTimingData.PositionTolerance = 0.03 -- how close (fraction of the bar) the cursor must really have been

--// Rarity: rarer sheep get a faster cursor and a smaller sweet spot ----------------------

shearTimingData.RarityModifiers = {
	Common = { cursorSpeed = 1.0, zoneScale = 1.0 },
	Uncommon = { cursorSpeed = 1.06, zoneScale = 0.95 },
	Rare = { cursorSpeed = 1.12, zoneScale = 0.9 },
	Epic = { cursorSpeed = 1.2, zoneScale = 0.85 },
	Legendary = { cursorSpeed = 1.28, zoneScale = 0.8 },
	Mythic = { cursorSpeed = 1.36, zoneScale = 0.75 },
} :: { [string]: RarityModifier }

-- Used when a shear has no stats of its own (per-shear stats live in ShearShopData).
shearTimingData.DefaultShearStats = { damageMultiplier = 1, zoneScale = 1, cursorSpeed = 1 } :: ShearStats

--// Feedback (client) ----------------------------------------------------------------------

shearTimingData.TierColors = {
	PERFECT = Color3.fromRGB(255, 214, 64),
	-- GREAT = Color3.fromRGB(90, 230, 120),
	-- GOOD = Color3.fromRGB(70, 175, 95),
	-- POOR = Color3.fromRGB(240, 150, 60),
	MISS = Color3.fromRGB(190, 192, 202),
} :: { [Tier]: Color3 }

-- Wool chunks that fly off the sheep for each tier.
shearTimingData.WoolChunks = { PERFECT = 9, GREAT = 6, GOOD = 3, POOR = 1, MISS = 0 } :: { [Tier]: number }

-- Image of one wool puff (an "rbxassetid://..." id) for the wool that flies to the wool counter. Empty = a plain white puff.
shearTimingData.WoolIconImage = "rbxassetid://112199646421676"

shearTimingData.ShearSoundId = ""
shearTimingData.ShearSoundVolume = 0.6
shearTimingData.TierPitch = { PERFECT = 1.25, GREAT = 1.12, GOOD = 1.0, POOR = 0.9, MISS = 0.75 } :: { [Tier]: number }

--// Wool look on the sheep (server; the sheep's Torso mesh is its wool) -------------------

shearTimingData.ShornTorsoScale = Vector3.new(0.9, 0.78, 0.78) -- Torso size at 0 wool, relative to full (X = body length)
shearTimingData.ShornColor = Color3.fromRGB(240, 212, 196) -- bare-skin colour the wool fades towards
shearTimingData.ShornColorBlend = 0.55 -- how far towards ShornColor the Torso gets at 0 wool

function shearTimingData.getRarityModifier(rarity: any): RarityModifier
	local modifier = if type(rarity) == "string" then shearTimingData.RarityModifiers[rarity] else nil
	return modifier or shearTimingData.RarityModifiers.Common
end

return shearTimingData
