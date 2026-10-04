--!strict

--[[
	Rebirth tuning, used only by the server (RebirthHandler decides everything). RebirthClient only
	displays what the server sends.

	A rebirth costs money AND asks for a few other things (pens owned, workers hired).
	Every requirement gets tougher with each rebirth. In return the player's wool sells for more
	(see getMultiplier), and their farm starts over.

	What a rebirth RESETS: money, wool, every pen except pen 1, pen 1's level and worker.
	What it KEEPS: bought shears and the pens/skins in the inventory.

	Location: ServerScriptService.Modules.Constants.RebirthData
]]--

local EconomyData = require(script.Parent.EconomyData)

local rebirthData = {}

rebirthData.MAX_REBIRTHS = 20

--// Money requirement: BASE * GROWTH ^ rebirths
rebirthData.MONEY_COST_BASE = 300
rebirthData.MONEY_COST_GROWTH = 2.25

--// Pens owned / workers hired: BASE + rebirths, never more than PENS_CAP
rebirthData.PENS_CAP = EconomyData.MAX_PENS
rebirthData.PENS_REQUIRED_BASE = 2
rebirthData.WORKERS_REQUIRED_BASE = 1

--// Most workers a plot may have hired at once: BASE + rebirths, never more than PENS_CAP
rebirthData.MAX_WORKERS_BASE = 2

--// Reward: wool sells for (1 + MULTIPLIER_PER_REBIRTH * rebirths) times its normal price
rebirthData.MULTIPLIER_PER_REBIRTH = 0.5

--// Money a player has right after a rebirth (same as a brand new player in PlayerSetup)
rebirthData.STARTING_MONEY = 1000

-- Money needed for the next rebirth; nil once the player has reached the maximum.
function rebirthData.getMoneyCost(rebirths: number): number?
	if rebirths >= rebirthData.MAX_REBIRTHS then
		return nil
	end

	return math.floor(rebirthData.MONEY_COST_BASE * rebirthData.MONEY_COST_GROWTH ^ rebirths)
end

function rebirthData.getPensRequired(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.PENS_REQUIRED_BASE + rebirths)
end

function rebirthData.getWorkersRequired(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.WORKERS_REQUIRED_BASE + rebirths)
end

function rebirthData.getMaxWorkers(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.MAX_WORKERS_BASE + rebirths)
end

-- How much more a player's wool sells for after this many rebirths (1 = normal price).
function rebirthData.getMultiplier(rebirths: number): number
	return 1 + rebirthData.MULTIPLIER_PER_REBIRTH * rebirths
end

return rebirthData
