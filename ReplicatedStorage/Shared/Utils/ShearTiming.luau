--!strict

--[[
	The maths of the shearing timing bar. Shared so the client draws and predicts exactly what the
	server scores. Positions run from 0 (left end of the bar) to 1 (right end).

	Location: ReplicatedStorage.Shared.Utils.ShearTiming
]]--

local ShearTimingData = require(script.Parent.Parent.Constants.ShearTimingData)

export type Tier = ShearTimingData.Tier

-- Half-widths: a press this close to the sweet spot (or closer) lands in that zone.
export type Zones = {
	perfect: number,
	great: number,
	good: number,
	poor: number,
}

export type Attempt = {
	id: number,
	sweetSpot: number,
	zones: Zones,
	cursorStart: number, -- 0 = starts at the left end moving right, 1 = starts at the right end moving left
	cursorSpeed: number, -- bar widths per second
	lifetime: number, -- seconds before the attempt times out
}

-- How finely wasPositionReachable walks along the cursor's path (seconds).
local REACH_SAMPLE_SECONDS = 1 / 120

local ShearTiming = {}

-- Where the cursor is `elapsed` seconds into an attempt. It bounces between the two ends of the bar.
function ShearTiming.getCursorPosition(cursorStart: number, cursorSpeed: number, elapsed: number): number
	local travelled = (cursorStart + cursorSpeed * math.max(elapsed, 0)) % 2
	return if travelled <= 1 then travelled else 2 - travelled
end

-- Zone half-widths for a zone size multiplier (shear upgrades and sheep rarity).
function ShearTiming.buildZones(zoneScale: number): Zones
	local function half(size: number): number
		return math.clamp(size * zoneScale, 0.01, 1) / 2
	end

	return {
		perfect = half(ShearTimingData.PerfectZoneSize),
		great = half(ShearTimingData.GreatZoneSize),
		good = half(ShearTimingData.GoodZoneSize),
		poor = half(ShearTimingData.PoorZoneSize),
	}
end

-- The accuracy tier of a press `distance` (fraction of the bar) away from the sweet spot's centre.
function ShearTiming.classify(distance: number, zones: Zones): Tier
	if distance <= zones.perfect then
		return "PERFECT"
	elseif distance <= zones.great then
		return "GREAT"
	elseif distance <= zones.good then
		return "GOOD"
	elseif distance <= zones.poor then
		return "POOR"
	end
	return "MISS"
end

-- Damage of a press before shear / wool scaling. The closer to the centre within its tier, the more.
function ShearTiming.getTierDamage(tier: Tier, distance: number, zones: Zones): number
	local range: ShearTimingData.DamageRange
	local inner: number
	local outer: number

	if tier == "PERFECT" then
		range, inner, outer = ShearTimingData.PerfectDamage, 0, zones.perfect
	elseif tier == "GREAT" then
		range, inner, outer = ShearTimingData.GreatDamage, zones.perfect, zones.great
	elseif tier == "GOOD" then
		range, inner, outer = ShearTimingData.GoodDamage, zones.great, zones.good
	elseif tier == "POOR" then
		range, inner, outer = ShearTimingData.PoorDamage, zones.good, zones.poor
	else
		return ShearTimingData.MissDamage
	end

	local width = outer - inner
	local depth = if width > 0 then math.clamp((distance - inner) / width, 0, 1) else 0
	return range.max + (range.min - range.max) * depth
end

-- A new sweet spot inside the playable range, at least MinimumSweetSpotShift away from the last one.
function ShearTiming.pickSweetSpot(previous: number?, random: Random): number
	local low = ShearTimingData.MinimumSweetSpotPosition
	local high = ShearTimingData.MaximumSweetSpotPosition
	local spot = random:NextNumber(low, high)

	if previous then
		for _ = 1, 12 do
			if math.abs(spot - previous) >= ShearTimingData.MinimumSweetSpotShift then
				break
			end
			spot = random:NextNumber(low, high)
		end
	end

	return spot
end

-- Whether the cursor really came within PositionTolerance of `position` between two moments of the attempt.
function ShearTiming.wasPositionReachable(attempt: Attempt, position: number, fromElapsed: number, toElapsed: number): boolean
	local from = math.max(fromElapsed, 0)
	local to = math.max(toElapsed, from)
	local elapsed = from

	while true do
		local cursor = ShearTiming.getCursorPosition(attempt.cursorStart, attempt.cursorSpeed, elapsed)
		if math.abs(cursor - position) <= ShearTimingData.PositionTolerance then
			return true
		end
		if elapsed >= to then
			return false
		end
		elapsed = math.min(elapsed + REACH_SAMPLE_SECONDS, to)
	end
end

return ShearTiming
