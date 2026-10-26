--!strict

--[[
	Connects the Prestige screen to PrestigeHandler: answers state and Prestige requests, times the white screen
	around the farm reset, and pushes fresh state whenever the player's rebirths, Prestiges or Luck change.

	Location: ServerScriptService.Server.PrestigeServer
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PrestigeHandler = require(serverScriptService.Modules.Controllers.PrestigeHandler)

--// Configs
local POLL_SECONDS = 0.5
local PRESTIGE_COOLDOWN_SECONDS = 3
local STATE_REQUEST_COOLDOWN_SECONDS = 0.5
local FADE_IN_SECONDS = 0.6 -- a little longer than PrestigeClient's 0.5s fade to white, so the farm resets unseen
local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[PrestigeServer] {message}`)
	end
end

--// State
local lastSignature: { [Player]: string } = {} -- only players whose PrestigeClient has asked, so nothing queues before it listens

-- A short fingerprint of the state, so an unchanged state is never sent twice.
local function getSignature(state: PrestigeHandler.State): string
	return `{state.prestiges}|{state.rebirths}|{state.luckFactor}|{state.nextLuckFactor}`
end

local function pushState(player: Player, force: boolean)
	local state = PrestigeHandler.getState(player)
	local signature = getSignature(state)
	if not force and lastSignature[player] == signature then
		return
	end

	lastSignature[player] = signature
	network.fireClient(network.RemoteEvents.PrestigeState, player, state)
end

network.waitUntilReadyAsync()

debugLog("network ready, listening for Prestige requests")

network.connectEvent(network.RemoteEvents.RequestPrestigeState, function(player: Player)
	pushState(player, true)
end, { network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN_SECONDS) })

-- PrestigeResult starts the client's fade to white; PrestigeFinished, sent once the farm is reset, fades it back out.
network.connectEvent(network.RemoteEvents.RequestPrestige, function(player: Player)
	local success, reason = PrestigeHandler.prestige(player, function(prestiges: number)
		network.fireClient(network.RemoteEvents.PrestigeResult, player, true, nil, prestiges)
		task.wait(FADE_IN_SECONDS)
	end)
	debugLog(`{player.Name} Prestige: success {success}, reason {reason}`)
	if not player.Parent then
		return
	end

	if success then
		network.fireClient(network.RemoteEvents.PrestigeFinished, player, PrestigeHandler.getPrestiges(player))
	else
		network.fireClient(network.RemoteEvents.PrestigeResult, player, false, reason, PrestigeHandler.getPrestiges(player))
	end
	pushState(player, true)
end, { network.Middleware.RateLimit(PRESTIGE_COOLDOWN_SECONDS) })

players.PlayerRemoving:Connect(function(player: Player)
	lastSignature[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(POLL_SECONDS)
		for player in lastSignature do
			local success, err = pcall(pushState, player, false)
			if not success then
				warn(`PrestigeServer: {err}`)
			end
		end
	end
end)
