--!strict

--[[
	Rebirth tuning: the wool each rebirth costs, and the luck-factor boost it gives until the next Prestige.
	Rebirths give no wool multiplier (More Wool covers that), so costs grow gently: a rebirth every ~2-6 minutes of
	active play, with the 10th (the first Prestige) around minute 33.

	Location: ServerScriptService.Modules.Constants.RebirthData
]]--

local rebirthData = {}

rebirthData.MAX_REBIRTHS = 25
rebirthData.FIRST_COST = 120 -- the tutorial's rebirth: 100 starter wool left after More Wool, then the 5th sheep sheared covers it
rebirthData.COST_BASE = 1250 -- rebirth N (N >= 2) costs COST_BASE * COST_GROWTH ^ (N - 1)
rebirthData.COST_GROWTH = 1.4
rebirthData.REBIRTH_LUCK_PER = 0.04 -- luck factor is multiplied by 1 + this * rebirths

-- Wool needed for the next rebirth; nil once the player has reached the maximum.
function rebirthData.getWoolCost(rebirths: number): number?
	if rebirths >= rebirthData.MAX_REBIRTHS then
		return nil
	elseif rebirths == 0 then
		return rebirthData.FIRST_COST
	end
	return math.floor(rebirthData.COST_BASE * rebirthData.COST_GROWTH ^ rebirths)
end

-- Wool needed for `count` rebirths in a row starting at `rebirths`; nil if that would go past the maximum.
function rebirthData.getTotalWoolCost(rebirths: number, count: number): number?
	local total = 0
	for step = rebirths, rebirths + count - 1 do
		local cost = rebirthData.getWoolCost(step)
		if not cost then
			return nil
		end
		total += cost
	end
	return total
end

-- The most rebirths in a row `wool` can pay for, and their total cost.
function rebirthData.getMaxAffordable(rebirths: number, wool: number): (number, number)
	local count, total = 0, 0
	while true do
		local cost = rebirthData.getWoolCost(rebirths + count)
		if not cost or total + cost > wool then
			return count, total
		end
		count += 1
		total += cost
	end
end

function rebirthData.getLuckMultiplier(rebirths: number): number
	return 1 + rebirthData.REBIRTH_LUCK_PER * math.clamp(rebirths, 0, rebirthData.MAX_REBIRTHS)
end

return rebirthData
