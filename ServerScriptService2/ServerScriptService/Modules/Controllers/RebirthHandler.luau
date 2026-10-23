--!strict

--[[
	Rebirth rules: spend wool to reset the farm (wool, Luck, capacity, upgrades) for a permanent wool multiplier
	and a Luck reward the new farm starts with. Shears are kept. Costs, multipliers and rewards live in RebirthData.

	Location: ServerScriptService.Modules.Controllers.RebirthHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local IndexHandler = require(script.Parent.IndexHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
local LEADERSTATS_WAIT_SECONDS = 15

export type State = {
	rebirths: number,
	maxRebirths: number,
	maxed: boolean,
	multiplier: number,
	nextMultiplier: number,
	wool: number,
	woolCost: number,
	canRebirth: boolean,
	luckReward: number, -- Luck the next rebirth grants (0 when maxed)
	luckMilestone: boolean, -- the next rebirth is a milestone (bonus Luck)
	luck: number, -- Luck right now
	luckFactor: number, -- the odds multiplier that Luck gives
	nextLuck: number, -- Luck the farm starts with after the next rebirth (same as luck when maxed)
	nextLuckFactor: number,
}

--// State
local rebirthing: { [Player]: boolean } = {}

local RebirthHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

-- Luck a farm starts with after `rebirths` rebirths: every rebirth reward plus the player's claimed Index Luck.
local function getStartingLuck(player: Player, rebirths: number): number
	return RebirthData.getStartingLuck(rebirths) + IndexHandler.getClaimedLuck(player)
end

-- Puts the farm back to the start (shears and the Index are kept).
local function resetProgress(player: Player, rebirths: number)
	PlayerDataHandler.set(player, "Wool", 0)
	PlayerDataHandler.set(player, "Luck", getStartingLuck(player, rebirths))
	PlayerDataHandler.set(player, "MaxSheep", FarmData.StartingMaxSheep)
	PlayerDataHandler.set(player, "MoreWoolLevel", 0)
	PlayerDataHandler.set(player, "SpeedLevel", 0)
	PlayerDataHandler.set(player, "DamageLevel", 0)
	PlayerDataHandler.set(player, "RespawnLevel", 0)
	SheepSpawnHandler.resetFarm(player)
end

--// Public API ------------------------------------------------------------------

function RebirthHandler.getRebirths(player: Player): number
	return getNumber(player, "Rebirths")
end

-- Everything the client needs to draw the rebirth screen for this player.
function RebirthHandler.getState(player: Player): State
	local rebirths = RebirthHandler.getRebirths(player)
	local woolCost = RebirthData.getWoolCost(rebirths)
	local wool = getNumber(player, "Wool")
	local luck = getNumber(player, "Luck")
	local nextLuck = if woolCost == nil then luck else getStartingLuck(player, rebirths + 1)

	return {
		rebirths = rebirths,
		maxRebirths = RebirthData.MAX_REBIRTHS,
		maxed = woolCost == nil,
		multiplier = RebirthData.getMultiplier(rebirths),
		nextMultiplier = RebirthData.getMultiplier(rebirths + 1),
		wool = wool,
		woolCost = woolCost or 0,
		canRebirth = woolCost ~= nil and wool >= woolCost,
		luckReward = RebirthData.getLuckReward(rebirths + 1),
		luckMilestone = RebirthData.isMilestone(rebirths + 1),
		luck = luck,
		luckFactor = SheepData.getLuckFactor(luck),
		nextLuck = nextLuck,
		nextLuckFactor = SheepData.getLuckFactor(nextLuck),
	}
end

--[[
	Tries to rebirth the player. Returns true on success, or false plus a reason the client can show
	("Busy", "MaxRebirths" or "NotReady"). Everything is checked here, on the server.
]]
function RebirthHandler.rebirth(player: Player): (boolean, string?)
	if rebirthing[player] or not PlayerDataHandler.getData(player) then
		return false, "Busy"
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
	PlayerDataHandler.set(player, "Rebirths", state.rebirths + 1)

	local success, err = pcall(function()
		resetProgress(player, state.rebirths + 1)
	end)
	if not success then
		warn(`RebirthHandler: resetting {player.Name}'s farm failed: {err}`)
	end

	rebirthing[player] = nil
	return true, nil
end

--// Lifecycle ---------------------------------------------------------------------

-- Mirrors Rebirths as a leaderstat once the leaderstats folder exists.
local function onPlayerAdded(player: Player)
	if not PlayerDataHandler.waitForData(player) then
		return
	end

	local leaderstats = player:WaitForChild("leaderstats", LEADERSTATS_WAIT_SECONDS)
	if not leaderstats then
		return
	end

	local display = Instance.new("IntValue")
	display.Name = "Rebirths"
	display.Value = RebirthHandler.getRebirths(player)
	display.Parent = leaderstats

	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		display.Value = RebirthHandler.getRebirths(player)
	end)
end

function RebirthHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		rebirthing[player] = nil
	end)

	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RebirthHandler
