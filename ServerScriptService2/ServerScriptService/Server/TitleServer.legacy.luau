--!strict

--[[
	Tells a player when they earn a new title, so the client can show the "NEW TITLE UNLOCKED" alert.
	Nothing is sent for the title given on join.

	Location: ServerScriptService.Server.TitleServer
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local TitleHandler = require(serverScriptService.Modules.Controllers.TitleHandler)

--// Configs
local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[TitleServer] {message}`)
	end
end

network.waitUntilReadyAsync()

debugLog("network ready, listening for title changes")

TitleHandler.TitleChanged:Connect(function(player: Player, title: TitleHandler.TitleInfo, previous: TitleHandler.TitleInfo?)
	if previous == nil then
		return
	end
	debugLog(`{player.Name} title: {previous.name} -> {title.name}`)
	network.fireClient(network.RemoteEvents.TitleUnlocked, player, title.name, title.color)
end)
