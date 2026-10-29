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
	Average wool per sheep is ~1.16x a Normal one (wool per swing ~1.05x), so spawn-capped farms earn a bit more.
	Odds: Normal 82%, Big 1 in 8, Huge 1 in 22, Giant 1 in 83, Colossal 1 in 333. SheepSizeClient mirrors the announced ids.
]]
sheepSizeData.Tiers = {
	{ id = "Normal",   chance = 8200, scale = 1,    health = 1,    wool = 1,   minWeight = 40,  maxWeight = 60 },
	{ id = "Big",      chance = 1200, scale = 1.2,  health = 1.35, wool = 1.5, minWeight = 60,  maxWeight = 110,
		prefix = "Big", color = Color3.fromRGB(125, 211, 252) },
	{ id = "Huge",     chance = 450,  scale = 1.45, health = 1.9,  wool = 2.3, minWeight = 110, maxWeight = 200,
		prefix = "Huge", color = Color3.fromRGB(74, 222, 128) },
	{ id = "Giant",    chance = 120,  scale = 1.75, health = 2.8,  wool = 3.6, minWeight = 200, maxWeight = 400,
		prefix = "Giant", color = Color3.fromRGB(250, 204, 21) },
	{ id = "Colossal", chance = 30,   scale = 2.1,  health = 4.2,  wool = 6,   minWeight = 400, maxWeight = 800,
		prefix = "Colossal", color = Color3.fromRGB(244, 63, 94) },
} :: { SizeInfo }

sheepSizeData.BabyWeightScale = 0.4 -- babies weigh this fraction of the tier's range
sheepSizeData.WeightWoolSpread = 0.1 -- the heaviest sheep in a tier gives this much more wool, the lightest this much less

local byId: { [string]: SizeInfo } = {}
local totalChance = 0
for _, tier in sheepSizeData.Tiers do
	byId[tier.id] = tier
	totalChance += tier.chance
end

function sheepSizeData.get(id: any): SizeInfo?
	return if type(id) == "string" then byId[id] else nil
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
	A weight inside the tier's range (whole kg) and its wool factor: 1 - spread at the lightest, 1 + spread at the heaviest.
]]
function sheepSizeData.rollWeight(tier: SizeInfo, baby: boolean, random: Random): (number, number)
	local t = random:NextNumber()
	local weight = tier.minWeight + (tier.maxWeight - tier.minWeight) * t
	if baby then
		weight *= sheepSizeData.BabyWeightScale
	end
	return math.max(math.floor(weight + 0.5), 1), 1 + sheepSizeData.WeightWoolSpread * (t * 2 - 1)
end

return sheepSizeData
