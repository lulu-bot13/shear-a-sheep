--!strict

--[[
	Sheep size tiers rolled on every spawn: model scale, wool health and wool multipliers, and the weight range in kg.

	Location: ServerScriptService.Modules.Constants.SheepSizeData
]]--

export type SizeInfo = {
	id: string,
	prefix: string?, -- shown before the sheep's name; nil = plain name
	color: Color3?, -- name colour on the billboards; nil = the card's own colour
	chance: number, -- spawn weight
	scale: number, -- times the model's built scale
	health: number, -- ShearHealth multiplier
	wool: number, -- WoolAmount multiplier; grows faster than health so bigger sheep pay more per swing
	minWeight: number, -- kg
	maxWeight: number,
}

local sheepSizeData = {}

--[[
	Average wool per sheep is ~1.04x a Normal one, so spawn-capped farms earn a bit more.
	Odds: Tiny 1 in 7, Normal 80%, Huge 1 in 20. SheepSizeClient mirrors the announced ids.
]]
sheepSizeData.Tiers = {
	{ id = "Tiny",   chance = 1500, scale = 0.7, health = 0.7, wool = 0.6, minWeight = 15,  maxWeight = 40,
		prefix = "Tiny", color = Color3.fromRGB(125, 211, 252) },
	{ id = "Normal", chance = 8000, scale = 1,   health = 1,   wool = 1,   minWeight = 40,  maxWeight = 60 },
	{ id = "Huge",   chance = 500,  scale = 1.6, health = 2.2, wool = 3,   minWeight = 110, maxWeight = 250,
		prefix = "Huge", color = Color3.fromRGB(250, 204, 21) },
} :: { SizeInfo }

-- Saved sheep from the old five tiers load as their nearest new one.
local LEGACY_IDS = { Big = "Normal", Giant = "Huge", Colossal = "Huge" }

sheepSizeData.WeightWoolSpread = 0.1 -- the heaviest sheep in a tier gives this much more wool, the lightest this much less

local byId: { [string]: SizeInfo } = {}
local totalChance = 0
for _, tier in sheepSizeData.Tiers do
	byId[tier.id] = tier
	totalChance += tier.chance
end

function sheepSizeData.get(id: any): SizeInfo?
	return if type(id) == "string" then byId[LEGACY_IDS[id] or id] else nil
end

function sheepSizeData.roll(random: Random): SizeInfo
	local roll = random:NextNumber() * totalChance
	local cumulative = 0
	for _, tier in sheepSizeData.Tiers do
		cumulative += tier.chance
		if roll <= cumulative then
			return tier
		end
	end
	return sheepSizeData.Tiers[1]
end

--[[
	A weight inside the tier's range times `scale` (a Baby/Giant variant's weight; whole kg) and its wool factor:
	1 - spread at the lightest, 1 + spread at the heaviest.
]]
function sheepSizeData.rollWeight(tier: SizeInfo, scale: number, random: Random): (number, number)
	local t = random:NextNumber()
	local weight = (tier.minWeight + (tier.maxWeight - tier.minWeight) * t) * scale
	return math.max(math.floor(weight + 0.5), 1), 1 + sheepSizeData.WeightWoolSpread * (t * 2 - 1)
end

return sheepSizeData
