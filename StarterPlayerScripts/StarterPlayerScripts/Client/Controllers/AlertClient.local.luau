--[[
	Shows the toasts the server sends through ShowAlert (purchases, gifts, badges) with the Alerts banners.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AlertClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local alerts = require(script.Parent.Parent.Modules.Alerts)

--// Configs
local KINDS = { success = true, error = true, info = true }

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShowAlert, function(text: any, kind: any)
	if type(text) == "string" then
		alerts.show(text, if KINDS[kind] then kind else "info")
	end
end)
