--!strict

--[[
	Central economy tuning shared by pen purchase/upgrade/sell/worker-hire
	flows, so every server script prices pens the same way.

	Location: ServerScriptService.Modules.Constants.EconomyData
]]--

local ecomonyData = {}

ecomonyData.PEN_BASE_PRICE = 100
ecomonyData.PEN_PRICE_MULTIPLIER = 3
ecomonyData.MAX_PENS = 6

-- Price to buy pen N (the base pen, N=1, is free/already owned). Matches the original curve.
function ecomonyData.getPenPrice(penNumber: number): number
	return math.round(ecomonyData.PEN_BASE_PRICE * ecomonyData.PEN_PRICE_MULTIPLIER ^ (penNumber - 2))
end

-- Cost to upgrade a pen FROM the given level to level+1; nil once already at max level.
ecomonyData.PEN_UPGRADE_COSTS = { [1] = 500, [2] = 2000, [3] = 8000, [4] = 32000 }

function ecomonyData.getPenUpgradeCost(currentLevel: number): number?
	return ecomonyData.PEN_UPGRADE_COSTS[currentLevel]
end

-- Selling a pen refunds a fraction of what it originally cost to buy.
ecomonyData.PEN_SELL_REFUND_RATIO = 0.5

function ecomonyData.getPenSellValue(penNumber: number): number
	return math.floor(ecomonyData.getPenPrice(penNumber) * ecomonyData.PEN_SELL_REFUND_RATIO)
end

-- Money paid per wool when selling (also used for the worker's estimated income).
ecomonyData.WOOL_SELL_PRICE = 0.5

-- One-time cost to hire an auto-shearing worker for a pen.
ecomonyData.WORKER_HIRE_COST = 750

return ecomonyData