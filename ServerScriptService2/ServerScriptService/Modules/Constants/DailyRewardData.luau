--!strict

--[[
	Daily reward tuning: the claim timings and the 7-day loop of Wool, each day a multiplier of a base unit of wool.
	The base is a share of the next rebirth's wool cost (never below a minimum), so rewards keep pace with the player's progress.

	Location: ServerScriptService.Modules.Constants.DailyRewardData
]]--

--// Modules
local RebirthData = require(script.Parent.RebirthData)

export type Kind = "Wool"

export type Day = {
	kind: Kind,
	multiplier: number, -- of the base wool unit
}

export type Reward = {
	day: number,
	kind: Kind,
	amount: number,
	multiplier: number,
}

--// Configs
local BASE_SHARE = 0.05 -- the base wool unit is this fraction of the next rebirth's wool cost
local MIN_BASE = 50 -- a new player's first rebirth is cheap, so the base never drops below this

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
	{ kind = "Wool", multiplier = 12 },
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

	local base = math.max(getNextRebirthCost(rebirths) * BASE_SHARE, MIN_BASE)
	return math.floor(base * info.multiplier + 0.5)
end

function dailyRewardData.getReward(day: number, rebirths: number, prestiges: number, cycles: number): Reward
	local info = dailyRewardData.Days[day]
	return {
		day = day,
		kind = info.kind,
		amount = dailyRewardData.getAmount(day, rebirths, prestiges, cycles),
		multiplier = info.multiplier,
	}
end

return dailyRewardData
