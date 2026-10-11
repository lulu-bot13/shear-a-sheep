--!strict

--[[
	Central economy tuning shared by pen purchase/upgrade/sell/worker-hire
	flows, so every server script prices pens the same way.

	Location: ServerScriptService.Modules.Constants.EconomyData
]]--

local SheepData = require(script.Parent.SheepData)

local ecomonyData = {}

ecomonyData.PEN_BASE_PRICE = 100
ecomonyData.PEN_PRICE_MULTIPLIER = 3
ecomonyData.MAX_PENS = 6

-- Price to buy pen N (the base pen, N=1, is free/already owned). Matches the original curve.
function ecomonyData.getPenPrice(penNumber: number): number
	return math.round(ecomonyData.PEN_BASE_PRICE * ecomonyData.PEN_PRICE_MULTIPLIER ^ (penNumber - 2))
end

-- First upgrade costs what UPGRADE_START_SHEEP basic sheep sell for; each level after adds START * LOG_SCALE * ln(level).
ecomonyData.UPGRADE_START_SHEEP = 2
ecomonyData.UPGRADE_LOG_SCALE = 4

-- Cost to upgrade a pen FROM the given level to level+1 (scaled by the owner's sell multiplier); nil once at max level.
function ecomonyData.getPenUpgradeCost(currentLevel: number, sellMultiplier: number?): number?
	if currentLevel >= SheepData.MaxPenLevel then
		return nil
	end

	local startCost = ecomonyData.UPGRADE_START_SHEEP * SheepData.Basic.WoolAmount * ecomonyData.WOOL_SELL_PRICE * (sellMultiplier or 1)
	return math.round(startCost * (1 + ecomonyData.UPGRADE_LOG_SCALE * math.log(currentLevel)))
end

-- Selling a pen refunds a fraction of what it originally cost to buy.
ecomonyData.PEN_SELL_REFUND_RATIO = 0.5

function ecomonyData.getPenSellValue(penNumber: number): number
	return math.floor(ecomonyData.getPenPrice(penNumber) * ecomonyData.PEN_SELL_REFUND_RATIO)
end

-- Money paid per wool when selling (also used for the worker's estimated income).
ecomonyData.WOOL_SELL_PRICE = 0.5

-- Cost of the first auto-shearing worker; each worker already hired multiplies the next price by WORKER_COST_GROWTH.
ecomonyData.WORKER_HIRE_COST = 750
ecomonyData.WORKER_COST_GROWTH = 2

function ecomonyData.getWorkerHireCost(workersHired: number): number
	return math.floor(ecomonyData.WORKER_HIRE_COST * ecomonyData.WORKER_COST_GROWTH ^ workersHired)
end

return ecomonyData