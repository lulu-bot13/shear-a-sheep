--!strict

--[[
	Connects the rebirth screen to the server rules in RebirthHandler:
		RequestRebirthState (client -> server)  "send me the current rebirth state"
		RequestRebirth      (client -> server)  "rebirth me" (the server checks everything itself)
		RebirthState        (server -> client)  the full state for drawing the screen
		RebirthResult       (server -> client)  success?, reason, new rebirth count

	The state is also pushed on its own whenever something on it changes (money, wool, pens, workers).

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

--// State
local lastSignature: { [Player]: string } = {}

-- A short fingerprint of the state, so an unchanged state is never sent twice.
local function getSignature(state: RebirthHandler.State): string
	local parts = { tostring(state.rebirths), tostring(state.money), tostring(state.canRebirth) }
	for _, requirement in state.requirements do
		table.insert(parts, tostring(requirement.current))
	end
	return table.concat(parts, "|")
end

local function pushState(player: Player, force: boolean)
	local state = RebirthHandler.getState(player)
	local signature = getSignature(state)
	if not force and lastSignature[player] == signature then
		return
	end

	lastSignature[player] = signature
	network.fireClient(network.RemoteEvents.RebirthState, player, state)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RequestRebirthState, function(player: Player)
	pushState(player, true)
end, { network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN_SECONDS) })

network.connectEvent(network.RemoteEvents.RequestRebirth, function(player: Player)
	local success, reason = RebirthHandler.rebirth(player)
	network.fireClient(network.RemoteEvents.RebirthResult, player, success, reason, RebirthHandler.getRebirths(player))
	pushState(player, true)
end, { network.Middleware.RateLimit(REBIRTH_COOLDOWN_SECONDS) })

players.PlayerRemoving:Connect(function(player: Player)
	lastSignature[player] = nil
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
