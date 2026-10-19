--!strict

--[[
	Rebirth tuning: the wool each rebirth costs, the permanent wool multiplier it gives and the Luck it grants.

	Location: ServerScriptService.Modules.Constants.RebirthData
]]--

local rebirthData = {}

rebirthData.MAX_REBIRTHS = 25
rebirthData.COST_BASE = 1500 -- wool for the first rebirth
rebirthData.COST_GROWTH = 3 -- each rebirth costs this many times the one before
rebirthData.MULTIPLIER_GROWTH = 1.5 -- wool multiplier = this ^ rebirths

--[[
	Luck reward. A rebirth wipes Luck, then sets it to the total of every rebirth reward earned so far,
	so the farm restarts luckier each time. Rebirth 1 grants about half the Luck a first run earns from sheep,
	and each reward is LUCK_GROWTH times the last; every LUCK_MILESTONE-th rebirth pays LUCK_MILESTONE_BONUS times.
	Rebirth:   1   2    3    4    5     10     15      20      25
	Reward:    50  72   105  152  442   2.8k   18k     116k    746k
	(Luck feeds a log10 odds curve in SheepData, so these big late numbers stay sane.)
]]
rebirthData.LUCK_BASE = 50
rebirthData.LUCK_GROWTH = 1.45
rebirthData.LUCK_MILESTONE = 5
rebirthData.LUCK_MILESTONE_BONUS = 2

-- Wool needed for the next rebirth; nil once the player has reached the maximum.
function rebirthData.getWoolCost(rebirths: number): number?
	if rebirths >= rebirthData.MAX_REBIRTHS then
		return nil
	end
	return math.floor(rebirthData.COST_BASE * rebirthData.COST_GROWTH ^ rebirths)
end

function rebirthData.getMultiplier(rebirths: number): number
	return rebirthData.MULTIPLIER_GROWTH ^ math.clamp(rebirths, 0, rebirthData.MAX_REBIRTHS)
end

function rebirthData.isMilestone(rebirth: number): boolean
	return rebirth > 0 and rebirth % rebirthData.LUCK_MILESTONE == 0
end

-- Luck granted by the `rebirth`-th rebirth (1 = the first); 0 outside 1..MAX_REBIRTHS.
function rebirthData.getLuckReward(rebirth: number): number
	if rebirth < 1 or rebirth > rebirthData.MAX_REBIRTHS then
		return 0
	end
	local reward = rebirthData.LUCK_BASE * rebirthData.LUCK_GROWTH ^ (rebirth - 1)
	if rebirthData.isMilestone(rebirth) then
		reward *= rebirthData.LUCK_MILESTONE_BONUS
	end
	return math.floor(reward)
end

-- Luck a farm starts with after `rebirths` rebirths: every reward earned so far.
function rebirthData.getStartingLuck(rebirths: number): number
	local total = 0
	for rebirth = 1, math.min(rebirths, rebirthData.MAX_REBIRTHS) do
		total += rebirthData.getLuckReward(rebirth)
	end
	return total
end

return rebirthData
