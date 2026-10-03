--!strict

--[[
	Tuning and formulas for the rebirth (prestige) system. Pure data and functions, no side effects.
	See docs/RebirthPlan.md for the reasoning behind these numbers.

	`n` is the rebirth being attempted (1 for the first), `count` is how many the player has completed.

	Location: ServerScriptService.Modules.Constants.RebirthData
]]--

local SheepData = require(script.Parent.SheepData)

export type Requirements = {
	rebirth: number,
	money: number,
	wool: number,
	minRarity: string,
}

local RebirthData = {}

--// Tuning
RebirthData.MAX_REBIRTHS = 15
RebirthData.M0 = 50000 -- PLACEHOLDER: money for the first rebirth. Set from measured end-of-tycoon income (see plan).
RebirthData.COST_GROWTH = 1.8
RebirthData.WOOL_RATIO = 0.4 -- wool needed per money needed

RebirthData.BASE_STARTING_MONEY = 1000
RebirthData.STARTING_MONEY_PER_REBIRTH = 500
RebirthData.WOOL_BONUS_PER_REBIRTH = 0.5
RebirthData.LUCK_BONUS_PER_REBIRTH = 0.05
RebirthData.MAX_LUCK_BONUS = 0.5

-- Rarity of sheep that must be in a pen, by rebirth number. Later rebirths keep the last entry.
RebirthData.RarityLadder = { "Rare", "Epic", "Epic", "Legendary", "Legendary", "Legendary", "Legendary", "Legendary", "Legendary", "Mythic" }

-- Position of a rarity in SheepData.RarityOrder (1 = Common); 0 if unknown.
function RebirthData.getRarityRank(rarity: any): number
	if type(rarity) ~= "string" then
		return 0
	end
	return table.find(SheepData.RarityOrder, rarity) or 0
end

function RebirthData.getRequirements(n: number): Requirements
	local money = math.round(RebirthData.M0 * RebirthData.COST_GROWTH ^ (n - 1))
	return {
		rebirth = n,
		money = money,
		wool = math.round(money * RebirthData.WOOL_RATIO),
		minRarity = RebirthData.RarityLadder[math.min(n, #RebirthData.RarityLadder)],
	}
end

-- True if a sheep of this rarity is good enough for rebirth n.
function RebirthData.meetsRarity(rarity: any, n: number): boolean
	local needed = RebirthData.getRarityRank(RebirthData.getRequirements(n).minRarity)
	return RebirthData.getRarityRank(rarity) >= needed
end

function RebirthData.getWoolMultiplier(count: number): number
	return 1 + RebirthData.WOOL_BONUS_PER_REBIRTH * count
end

function RebirthData.getStartingMoney(count: number): number
	return RebirthData.BASE_STARTING_MONEY + RebirthData.STARTING_MONEY_PER_REBIRTH * count
end

-- Fraction added to the spawn weight of Rare+ sheep (0.1 = 10% more likely).
function RebirthData.getLuckBonus(count: number): number
	return math.min(RebirthData.LUCK_BONUS_PER_REBIRTH * count, RebirthData.MAX_LUCK_BONUS)
end

return RebirthData
