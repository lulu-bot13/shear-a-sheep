--!strict

--[[
	Daily reward tuning: the claim timings and the 7-day loop. Wool days are a multiplier of a base unit of wool (a share of
	the next rebirth's wool cost, never below a minimum) so they keep pace with progress; the day 7 big bonus is a flat amount of Gems.

	Location: ServerScriptService.Modules.Constants.DailyRewardData
]]--

--// Modules
local RebirthData = require(script.Parent.RebirthData)

export type Kind = "Wool" | "Gems"

export type Day = {
	kind: Kind,
	multiplier: number?, -- Wool days: of the base wool unit
	amount: number?, -- Gems days: a flat amount
}

export type Reward = {
	day: number,
	kind: Kind,
	amount: number,
}

--// Configs
local BASE_SHARE = 0.05 -- the base wool unit is this fraction of the next rebirth's wool cost
local MIN_BASE = 50 -- a new player's first rebirth is cheap, so the base never drops below this
local DAY_7_GEMS = 12 -- 3 Ability Shack rolls (AbilityData.RollCost 4), ~30 min of gem drops; a bit above the 10-Gem Robux pack

local dailyRewardData = {}

dailyRewardData.CLAIM_COOLDOWN_SECONDS = 20 * 60 * 60 -- a little under a day, so a player can claim at roughly the same time each day
dailyRewardData.STREAK_RESET_SECONDS = 48 * 60 * 60 -- this long without claiming starts the loop over at day 1

dailyRewardData.Days = {
	{ kind = "Wool", multiplier = 2 },
	{ kind = "Wool", multiplier = 3 },
	{ kind = "Wool", multiplier = 4 },
	{ kind = "Wool", multiplier = 5 },
	{ kind = "Wool", multiplier = 6 },
	{ kind = "Wool", multiplier = 8 },
	{ kind = "Gems", amount = DAY_7_GEMS },
} :: { Day }

dailyRewardData.DAY_COUNT = #dailyRewardData.Days

-- The wool cost of the player's next rebirth; maxed players keep the last rebirth's cost.
local function getNextRebirthCost(rebirths: number): number
	return RebirthData.getWoolCost(math.min(rebirths, RebirthData.MAX_REBIRTHS - 1)) or RebirthData.FIRST_COST
end

function dailyRewardData.getAmount(day: number, rebirths: number, _prestiges: number, _cycles: number): number
	local info = dailyRewardData.Days[day]
	if not info then
		return 0
	end
	if info.kind == "Gems" then
		return info.amount or 0
	end

	local base = math.max(getNextRebirthCost(rebirths) * BASE_SHARE, MIN_BASE)
	return math.floor(base * (info.multiplier or 0) + 0.5)
end

function dailyRewardData.getReward(day: number, rebirths: number, prestiges: number, cycles: number): Reward
	local info = dailyRewardData.Days[day]
	return {
		day = day,
		kind = info.kind,
		amount = dailyRewardData.getAmount(day, rebirths, prestiges, cycles),
	}
end

return dailyRewardData
