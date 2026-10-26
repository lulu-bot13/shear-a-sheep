--!strict

--[[
	Connects the rebirth screen to RebirthHandler: answers state and rebirth requests,
	and pushes fresh state on its own whenever the player's wool, luck, rebirths or Prestiges change.

	Location: ServerScriptService.Server.RebirthServer
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local RebirthHandler = require(serverScriptService.Modules.Controllers.RebirthHandler)

--// Configs
local POLL_SECONDS = 0.5
local REBIRTH_COOLDOWN_SECONDS = 1.5
local STATE_REQUEST_COOLDOWN_SECONDS = 0.5
local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[RebirthServer] {message}`)
	end
end

--// State
local lastSignature: { [Player]: string } = {}
local selectedAmount: { [Player]: RebirthHandler.Amount } = {} -- the amount the screen last asked about, so pushes keep using it

-- A short fingerprint of the state, so an unchanged state is never sent twice.
local function getSignature(state: RebirthHandler.State): string
	return `{state.rebirths}|{state.prestiges}|{state.wool}|{state.canRebirth}|{state.luck}|{state.amount}`
end

local function pushState(player: Player, force: boolean)
	local state = RebirthHandler.getState(player, selectedAmount[player])
	local signature = getSignature(state)
	if not force and lastSignature[player] == signature then
		return
	end

	lastSignature[player] = signature
	network.fireClient(network.RemoteEvents.RebirthState, player, state)
end

network.waitUntilReadyAsync()

debugLog("network ready, listening for rebirth requests")

network.connectEvent(network.RemoteEvents.RequestRebirthState, function(player: Player, amount: any)
	selectedAmount[player] = RebirthHandler.parseAmount(amount)
	debugLog(`{player.Name} asked for their rebirth state (amount {selectedAmount[player]})`)
	pushState(player, true)
end, { network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN_SECONDS) })

network.connectEvent(network.RemoteEvents.RequestRebirth, function(player: Player, amount: any)
	selectedAmount[player] = RebirthHandler.parseAmount(amount)
	local before = RebirthHandler.getState(player, selectedAmount[player])
	local success, reason, count = RebirthHandler.rebirth(player, selectedAmount[player])
	debugLog(`{player.Name} rebirth x{before.amount}: success {success}, reason {reason}, count {count}, wool {before.wool}/{before.amountCost}, rebirths {before.rebirths}`)
	network.fireClient(network.RemoteEvents.RebirthResult, player, success, reason, RebirthHandler.getRebirths(player), count)
	pushState(player, true)
end, { network.Middleware.RateLimit(REBIRTH_COOLDOWN_SECONDS) })

players.PlayerRemoving:Connect(function(player: Player)
	lastSignature[player] = nil
	selectedAmount[player] = nil
end)

players.PlayerAdded:Connect(function(player: Player)
	pushState(player, false)
end)

task.spawn(function()
	while true do
		task.wait(POLL_SECONDS)
		for _, player in players:GetPlayers() do
			local success, err = pcall(pushState, player, false)
			if not success then
				warn(`RebirthServer: {err}`)
			end
		end
	end
end)
