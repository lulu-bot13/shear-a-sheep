--[[
	Shows StarterGui.Alerts.Main.TitleAlert with the new title's name in its color when the server says one was earned.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.TitleClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local announcements = require(script.Parent.Parent.Modules.Announcements)

local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[TitleClient] {message}`)
	end
end

--// Helpers -------------------------------------------------------------------------

local function escapeRichText(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

--// Setup -------------------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.TitleUnlocked, function(name: string, color: Color3)
	debugLog(`new title: {name}`)
	announcements.show("TitleAlert", `NEW TITLE UNLOCKED: <font color="#{color:ToHex()}">{escapeRichText(name)}</font>`, true)
end)
