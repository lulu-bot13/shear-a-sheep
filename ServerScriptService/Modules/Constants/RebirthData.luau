--!strict

--[[
	Tuning and formulas for the rebirth (prestige) system. See docs/RebirthPlan.md for the reasoning.

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
RebirthData.M0 = 50000 -- placeholder: money for the first rebirth, set from measured income
RebirthData.COST_GROWTH = 1.8
RebirthData.WOOL_RATIO = 0.4

RebirthData.BASE_STARTING_MONEY = 1000
RebirthData.STARTING_MONEY_PER_REBIRTH = 500
RebirthData.WOOL_BONUS_PER_REBIRTH = 0.5
RebirthData.LUCK_BONUS_PER_REBIRTH = 0.05
RebirthData.MAX_LUCK_BONUS = 0.5

RebirthData.RarityLadder = { "Rare", "Epic", "Epic", "Legendary", "Legendary", "Legendary", "Legendary", "Legendary", "Legendary", "Mythic" }

--[[
	Gets where a rarity sits in SheepData.RarityOrder.

	@param rarity The rarity name, e.g. "Rare"

	@return The position (1 = Common), or 0 if the rarity is unknown
]]--
function RebirthData.getRarityRank(rarity: any): number
	if type(rarity) ~= "string" then
		return 0
	end
	return table.find(SheepData.RarityOrder, rarity) or 0
end

--[[
	Gets what a player needs to complete a rebirth.

	@param n The rebirth being attempted (1 for the first)

	@return The money, wool and minimum sheep rarity required
]]--
function RebirthData.getRequirements(n: number): Requirements
	local money = math.round(RebirthData.M0 * RebirthData.COST_GROWTH ^ (n - 1))
	return {
		rebirth = n,
		money = money,
		wool = math.round(money * RebirthData.WOOL_RATIO),
		minRarity = RebirthData.RarityLadder[math.min(n, #RebirthData.RarityLadder)],
	}
end

--[[
	Checks whether a sheep's rarity is good enough for a rebirth.

	@param rarity The sheep's rarity name
	@param n The rebirth being attempted

	@return True if the rarity meets the minimum
]]--
function RebirthData.meetsRarity(rarity: any, n: number): boolean
	local needed = RebirthData.getRarityRank(RebirthData.getRequirements(n).minRarity)
	return RebirthData.getRarityRank(rarity) >= needed
end

--[[
	Gets the multiplier applied to wool sell prices.

	@param count How many rebirths the player has completed

	@return The multiplier, 1 with no rebirths
]]--
function RebirthData.getWoolMultiplier(count: number): number
	return 1 + RebirthData.WOOL_BONUS_PER_REBIRTH * count
end

--[[
	Gets the money a player starts a run with.

	@param count How many rebirths the player has completed

	@return The starting money
]]--
function RebirthData.getStartingMoney(count: number): number
	return RebirthData.BASE_STARTING_MONEY + RebirthData.STARTING_MONEY_PER_REBIRTH * count
end

--[[
	Gets the extra spawn weight given to Rare and better sheep.

	@param count How many rebirths the player has completed

	@return The bonus as a fraction (0.1 = 10% more likely), capped at MAX_LUCK_BONUS
]]--
function RebirthData.getLuckBonus(count: number): number
	return math.min(RebirthData.LUCK_BONUS_PER_REBIRTH * count, RebirthData.MAX_LUCK_BONUS)
end

return RebirthData
