--[[
	Tells the server's Analytics module each time a window opens, for the Upgrades, Rebirth, Shear Shop, Ability Shack and Index funnels.
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

network.waitUntilReadyAsync()

windowsManager.opened:Connect(function(name: string)
	network.fireServer(network.RemoteEvents.AnalyticsEvent, "Window", name)
end)
