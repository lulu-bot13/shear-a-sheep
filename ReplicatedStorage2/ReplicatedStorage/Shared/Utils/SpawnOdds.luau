--!strict

--[[
	Spawn-roll math shared by the server's SheepData roll and the client's displays: the luck factor, Spawn Luck and Sheep Size.
	Location: ReplicatedStorage.Shared.Utils.SpawnOdds
]]--

local SpawnOdds = {}

--// Configs
SpawnOdds.LUCK_STRENGTH = 0.5 -- luck factor part from Luck = 1 + LUCK_STRENGTH * log10(1 + Luck / LUCK_SCALE)
SpawnOdds.LUCK_SCALE = 100
SpawnOdds.SPAWN_LUCK_PER_LEVEL = 0.06 -- each Spawn Luck level multiplies the luck factor by 1 + this * level
SpawnOdds.SPAWN_LUCK_BASE_CAP = 4 -- Spawn Luck levels buyable at Rebirth 0
SpawnOdds.SPAWN_LUCK_CAP_PER_REBIRTH = 2
SpawnOdds.SPAWN_LUCK_MAX_LEVEL = 30 -- however many rebirths
SpawnOdds.SIZE_SHIFT_PER_LEVEL = { Baby = -0.08, Giant = 0.04 } -- Sheep Size: per level; the adult share takes the rest (+0.04)

-- The part of the luck factor that comes from the Luck stat.
function SpawnOdds.getLuckPart(luck: number): number
	return 1 + SpawnOdds.LUCK_STRENGTH * math.log10(1 + math.max(luck, 0) / SpawnOdds.LUCK_SCALE)
end

function SpawnOdds.getSpawnLuckMultiplier(level: number): number
	return 1 + SpawnOdds.SPAWN_LUCK_PER_LEVEL * math.max(level, 0)
end

-- Spawn Luck levels a player with this many rebirths may own.
function SpawnOdds.getSpawnLuckCap(rebirths: number): number
	return math.min(SpawnOdds.SPAWN_LUCK_BASE_CAP + SpawnOdds.SPAWN_LUCK_CAP_PER_REBIRTH * math.max(rebirths, 0), SpawnOdds.SPAWN_LUCK_MAX_LEVEL)
end

-- The luck factor: rarity tier N's spawn weight is multiplied by this ^ N. The multipliers come from RebirthData / PrestigeData.
function SpawnOdds.getLuckFactor(luck: number, rebirthMultiplier: number, prestigeMultiplier: number, spawnLuckLevel: number?, boost: number?): number
	return SpawnOdds.getLuckPart(luck) * rebirthMultiplier * prestigeMultiplier * SpawnOdds.getSpawnLuckMultiplier(spawnLuckLevel or 0) * (boost or 1)
end

-- A Baby/Giant variant's share of its type's spawns at this Sheep Size level (`baseShare` is SheepData.Variants' share).
function SpawnOdds.getVariantShare(variantId: string, baseShare: number, sizeLevel: number?): number
	return math.clamp(baseShare + (SpawnOdds.SIZE_SHIFT_PER_LEVEL[variantId] or 0) * (sizeLevel or 0), 0, 1)
end

-- 1.904 -> "x1.9"
function SpawnOdds.formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- 12345 -> "1 in 12,345"
function SpawnOdds.formatOdds(odds: number): string
	local digits = tostring(math.max(math.floor(odds + 0.5), 1))
	return `1 in {(digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))}`
end

return SpawnOdds
