--!strict

--[[
	Prestige rules: after enough rebirths, reset wool, rebirths, Luck, capacity and upgrades for a permanent wool and luck boost.
	Shears and the Index are kept. Requirements and rewards live in PrestigeData.

	Location: ServerScriptService.Modules.Controllers.PrestigeHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local PrestigeData = require(script.Parent.Parent.Constants.PrestigeData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local IndexHandler = require(script.Parent.IndexHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
local LEADERSTATS_WAIT_SECONDS = 15

export type State = {
	prestiges: number,
	rebirths: number,
	requiredRebirths: number,
	canPrestige: boolean,
	multiplier: number, -- Prestige wool multiplier right now
	nextMultiplier: number, -- Prestige wool multiplier straight after the next Prestige
	luckFactor: number, -- the odds multiplier right now
	nextLuckFactor: number, -- the odds multiplier straight after the next Prestige (Luck back to Index Luck)
	nextLuckBonus: number, -- the permanent luck-factor multiplier the next Prestige brings
}

--// State
local prestiging: { [Player]: boolean } = {}

local PrestigeHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

-- Puts the save back to the start (shears and the Index are kept, and Luck goes back to the claimed Index Luck).
local function resetProgress(player: Player)
	PlayerDataHandler.set(player, "Wool", 0)
	PlayerDataHandler.set(player, "Rebirths", 0)
	PlayerDataHandler.set(player, "Luck", IndexHandler.getClaimedLuck(player))
	PlayerDataHandler.set(player, "MaxSheep", FarmData.StartingMaxSheep)
	PlayerDataHandler.set(player, "MoreWoolLevel", 0)
	PlayerDataHandler.set(player, "SpeedLevel", 0)
	PlayerDataHandler.set(player, "DamageLevel", 0)
	PlayerDataHandler.set(player, "RespawnLevel", 0)
end

--// Public API ------------------------------------------------------------------

function PrestigeHandler.getPrestiges(player: Player): number
	return getNumber(player, "Prestiges")
end

-- Everything the client needs to draw the Prestige screen for this player.
function PrestigeHandler.getState(player: Player): State
	local prestiges = PrestigeHandler.getPrestiges(player)
	local rebirths = getNumber(player, "Rebirths")

	return {
		prestiges = prestiges,
		rebirths = rebirths,
		requiredRebirths = PrestigeData.REQUIRED_REBIRTHS,
		canPrestige = rebirths >= PrestigeData.REQUIRED_REBIRTHS,
		multiplier = PrestigeData.getWoolMultiplier(prestiges),
		nextMultiplier = PrestigeData.getWoolMultiplier(prestiges + 1),
		luckFactor = SheepData.getLuckFactor(getNumber(player, "Luck"), rebirths, prestiges),
		nextLuckFactor = SheepData.getLuckFactor(IndexHandler.getClaimedLuck(player), 0, prestiges + 1),
		nextLuckBonus = PrestigeData.getLuckMultiplier(prestiges + 1),
	}
end

--[[
	Tries to prestige the player. Returns true on success, or false plus a reason the client can show
	("Busy" or "NotReady"). Everything is checked here, on the server.
	`beforeFarmReset` runs (and may yield) after the save is reset but before the sheep are, so the caller can cover the screen first.
]]
function PrestigeHandler.prestige(player: Player, beforeFarmReset: ((prestiges: number) -> ())?): (boolean, string?)
	if prestiging[player] or not PlayerDataHandler.getData(player) then
		return false, "Busy"
	end

	local state = PrestigeHandler.getState(player)
	if not state.canPrestige then
		return false, "NotReady"
	end

	prestiging[player] = true

	-- The Prestige is counted first, so a problem while resetting can never cost the player progress for nothing.
	PlayerDataHandler.set(player, "Prestiges", state.prestiges + 1)

	-- The save is reset straight away, so leaving mid-Prestige can't keep the old progress.
	local success, err = pcall(resetProgress, player)
	if not success then
		warn(`PrestigeHandler: resetting {player.Name}'s save failed: {err}`)
	end

	success, err = pcall(function()
		if beforeFarmReset then
			beforeFarmReset(state.prestiges + 1)
		end
		if player.Parent then
			SheepSpawnHandler.resetFarm(player)
		end
	end)
	if not success then
		warn(`PrestigeHandler: resetting {player.Name}'s farm failed: {err}`)
	end

	prestiging[player] = nil
	return true, nil
end

--// Lifecycle ---------------------------------------------------------------------

-- Mirrors Prestiges as a leaderstat, placed after Rebirths.
local function onPlayerAdded(player: Player)
	if not PlayerDataHandler.waitForData(player) then
		return
	end

	local leaderstats = player:WaitForChild("leaderstats", LEADERSTATS_WAIT_SECONDS)
	if not leaderstats then
		return
	end
	leaderstats:WaitForChild("Rebirths", LEADERSTATS_WAIT_SECONDS)

	local display = Instance.new("IntValue")
	display.Name = "Prestige"
	display.Value = PrestigeHandler.getPrestiges(player)
	display.Parent = leaderstats

	player:GetAttributeChangedSignal("Prestiges"):Connect(function()
		display.Value = PrestigeHandler.getPrestiges(player)
	end)
end

function PrestigeHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		prestiging[player] = nil
	end)

	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PrestigeHandler
