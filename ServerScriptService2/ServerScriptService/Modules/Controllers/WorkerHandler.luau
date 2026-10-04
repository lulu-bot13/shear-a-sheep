--!strict

--[[
	Worker rules for a player's whole plot. Workers are bought from the Hire Workers screen into a pool
	(Player attribute "WorkersOwned": how many are owned out of how many are allowed - the allowance grows
	with rebirths - and each one bought makes the next dearer). A pen's menu then puts an unused worker from
	that pool onto the pen for free, and taking one off returns it to the pool.

	Location: ServerScriptService.Modules.Controllers.WorkerHandler
]]--

--// Modules
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local EconomyData = require(script.Parent.Parent.Constants.EconomyData)
local PenHandler = require(script.Parent.PenHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Configs
local OWNED_ATTRIBUTE = "WorkersOwned" -- RebirthHandler resets this on a rebirth

export type State = {
	owned: number, -- bought so far
	assigned: number, -- of those, standing at a pen
	available: number, -- bought but not at a pen yet
	max: number,
	cost: number, -- price of the next one
	canAfford: boolean,
	canBuy: boolean, -- another worker can be bought right now (below the cap and enough money)
}

local WorkerHandler = {}

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

-- Workers standing at a pen.
function WorkerHandler.getAssigned(player: Player): number
	local count = 0
	for _, pen in PenHandler.getPens(player) do
		if pen.data.automated then
			count += 1
		end
	end
	return count
end

function WorkerHandler.getOwned(player: Player): number
	local value = player:GetAttribute(OWNED_ATTRIBUTE)
	local owned = if type(value) == "number" then value else 0
	return math.max(owned, WorkerHandler.getAssigned(player))
end

function WorkerHandler.getMax(player: Player): number
	return RebirthData.getMaxWorkers(RebirthHandler.getRebirths(player))
end

function WorkerHandler.getAvailable(player: Player): number
	return WorkerHandler.getOwned(player) - WorkerHandler.getAssigned(player)
end

function WorkerHandler.getState(player: Player): State
	local owned = WorkerHandler.getOwned(player)
	local assigned = WorkerHandler.getAssigned(player)
	local max = WorkerHandler.getMax(player)
	local cost = EconomyData.getWorkerHireCost(owned)
	local money = getMoney(player)
	local canAfford = money ~= nil and money.Value >= cost

	return {
		owned = owned,
		assigned = assigned,
		available = owned - assigned,
		max = max,
		cost = cost,
		canAfford = canAfford,
		canBuy = owned < max and canAfford,
	}
end

--[[
	Buys one worker into the pool and charges for it. Returns true, or false plus why ("Full" or "NoMoney").
]]
function WorkerHandler.buy(player: Player): (boolean, string?)
	local owned = WorkerHandler.getOwned(player)
	if owned >= WorkerHandler.getMax(player) then
		return false, "Full"
	end

	local cost = EconomyData.getWorkerHireCost(owned)
	local money = getMoney(player)
	if not money or money.Value < cost then
		return false, "NoMoney"
	end

	money.Value -= cost
	player:SetAttribute(OWNED_ATTRIBUTE, owned + 1)
	return true, nil
end

-- Puts an unused worker on `pen` (free). Returns true, or false plus why ("NoWorkers" or "Busy").
function WorkerHandler.assign(player: Player, pen: any): (boolean, string?)
	if pen.destroyed or pen.data.automated then
		return false, "Busy"
	end
	if WorkerHandler.getAvailable(player) <= 0 then
		return false, "NoWorkers"
	end

	if not pen:hireWorker() then
		return false, "Busy"
	end
	return true, nil
end

return WorkerHandler
