--!strict

--[[
	The rebirth rules. Knows how many times each player has rebirthed (Player attribute "Rebirths", also
	shown as a leaderstat), what the next rebirth needs, what it resets, and how much their wool sells
	for because of it.

	The tuning numbers live in ReplicatedStorage.Shared.Constants.RebirthData. RebirthServer is the
	script that talks to the client; SellWoolHandler asks getMultiplier for the wool bonus.

	Location: ServerScriptService.Modules.Controllers.RebirthHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local RebirthData = require(replicatedStorage.Shared.Constants.RebirthData)
local PenSlotUnlocks = require(script.Parent.Parent.Constants.PenSlotUnlocks)
local InventoryHandler = require(script.Parent.InventoryHandler)
local PenHandler = require(script.Parent.PenHandler)
local ShearHandler = require(script.Parent.ShearHandler)

--// Configs
local REBIRTHS_ATTRIBUTE = "Rebirths"
local WOOL_ITEM = "Wool"
local LEADERSTATS_WAIT_SECONDS = 15

export type Requirement = {
	id: string,
	label: string,
	current: number,
	required: number,
	met: boolean,
}

export type State = {
	rebirths: number,
	maxRebirths: number,
	maxed: boolean,
	multiplier: number,
	nextMultiplier: number,
	money: number,
	moneyCost: number,
	requirements: { Requirement },
	canRebirth: boolean,
}

--// State
local rebirthing: { [Player]: boolean } = {}

local RebirthHandler = {}

--// Helpers -------------------------------------------------------------------

local function getMoneyValue(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

local function countWorkers(player: Player): number
	local count = 0
	for _, pen in PenHandler.getPens(player) do
		if pen.data.automated then
			count += 1
		end
	end
	return count
end

local function makeRequirement(id: string, label: string, current: number, required: number): Requirement
	return { id = id, label = label, current = current, required = required, met = current >= required }
end

-- Puts the player's farm back to the start (see RebirthData for what is reset and what is kept).
local function resetProgress(player: Player)
	local wool = InventoryHandler.getItem(player, WOOL_ITEM)
	if wool > 0 then
		InventoryHandler.removeItem(player, WOOL_ITEM, wool)
	end

	-- Only the newest pen can be removed at a time, so go from the end back to pen 2.
	local pens = PenHandler.getPens(player)
	for index = #pens, 2, -1 do
		PenHandler.removePen(player, pens[index])
	end

	local basePen = pens[1]
	if basePen then
		basePen:resetProgress()
	end

	local money = getMoneyValue(player)
	if money then
		money.Value = RebirthData.STARTING_MONEY
	end
end

--// Public API ------------------------------------------------------------------

function RebirthHandler.getRebirths(player: Player): number
	local value = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	return if type(value) == "number" then value else 0
end

-- How many times more than normal this player's wool sells for (1 = normal).
function RebirthHandler.getMultiplier(player: Player): number
	return RebirthData.getMultiplier(RebirthHandler.getRebirths(player))
end

-- Everything the client needs to draw the rebirth screen for this player.
function RebirthHandler.getState(player: Player): State
	local rebirths = RebirthHandler.getRebirths(player)
	local moneyCost = RebirthData.getMoneyCost(rebirths)
	local maxed = moneyCost == nil

	local moneyValue = getMoneyValue(player)
	local money = if moneyValue then moneyValue.Value else 0

	local requirements: { Requirement } = {}
	local canRebirth = false

	if moneyCost then
		local woolHeld = InventoryHandler.getItem(player, WOOL_ITEM)
		local slotLimit = PenSlotUnlocks.getSlotLimit(rebirths)
		local pensRequired = math.min(RebirthData.getPensRequired(rebirths), slotLimit)
		local workersRequired = math.min(RebirthData.getWorkersRequired(rebirths), slotLimit)

		table.insert(requirements, makeRequirement("Wool", "Wool", woolHeld, RebirthData.getWoolRequired(rebirths)))
		table.insert(requirements, makeRequirement("Pens", "Pens", #PenHandler.getPens(player), pensRequired))
		table.insert(requirements, makeRequirement("Workers", "Workers", countWorkers(player), workersRequired))

		canRebirth = money >= moneyCost
		for _, requirement in requirements do
			if not requirement.met then
				canRebirth = false
			end
		end
	end

	return {
		rebirths = rebirths,
		maxRebirths = RebirthData.MAX_REBIRTHS,
		maxed = maxed,
		multiplier = RebirthData.getMultiplier(rebirths),
		nextMultiplier = RebirthData.getMultiplier(math.min(rebirths + 1, RebirthData.MAX_REBIRTHS)),
		money = money,
		moneyCost = moneyCost or 0,
		requirements = requirements,
		canRebirth = canRebirth,
	}
end

--[[
	Tries to rebirth the player. Returns true on success, or false plus a reason the client can show
	("Busy", "Shearing", "MaxRebirths" or "NotReady"). Everything is checked here, on the server.
]]
function RebirthHandler.rebirth(player: Player): (boolean, string?)
	if rebirthing[player] then
		return false, "Busy"
	end
	if ShearHandler.isShearing(player) then
		return false, "Shearing"
	end

	local state = RebirthHandler.getState(player)
	if state.maxed then
		return false, "MaxRebirths"
	end
	if not state.canRebirth then
		return false, "NotReady"
	end

	rebirthing[player] = true

	-- The rebirth is counted first, so a problem while resetting can never cost the player progress for nothing.
	player:SetAttribute(REBIRTHS_ATTRIBUTE, state.rebirths + 1)

	local success, err = pcall(resetProgress, player)
	if not success then
		warn(`RebirthHandler: resetting {player.Name}'s farm failed: {err}`)
	end

	rebirthing[player] = nil
	print(`{player.Name} rebirthed (now {state.rebirths + 1}).`)
	return true, nil
end

--// Lifecycle ---------------------------------------------------------------------

-- Gives the player their Rebirths attribute and mirrors it as a leaderstat once the leaderstats folder exists.
local function onPlayerAdded(player: Player)
	if player:GetAttribute(REBIRTHS_ATTRIBUTE) == nil then
		player:SetAttribute(REBIRTHS_ATTRIBUTE, 0)
	end

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", LEADERSTATS_WAIT_SECONDS)
		if not leaderstats then
			return
		end

		local display = Instance.new("IntValue")
		display.Name = "Rebirths"
		display.Value = RebirthHandler.getRebirths(player)
		display.Parent = leaderstats

		player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(function()
			display.Value = RebirthHandler.getRebirths(player)
		end)
	end)
end

function RebirthHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		rebirthing[player] = nil
	end)

	for _, player in players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return RebirthHandler
