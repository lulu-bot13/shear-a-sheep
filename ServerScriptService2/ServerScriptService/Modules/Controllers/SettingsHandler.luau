--!strict

--[[
	Saves each player's settings (SettingsData) and sends them back on join; the client applies them itself.
	Only known ids with boolean values are kept, and saved settings are merged with the defaults so new ones get theirs.

	Location: ServerScriptService.Modules.Controllers.SettingsHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SettingsData = require(replicatedStorage.Shared.Constants.SettingsData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local SETTINGS_KEY = "Settings"
local CHANGE_COOLDOWN = 0.2 -- the client spaces its saves wider than this, so none are dropped
local REQUEST_COOLDOWN = 1

local SettingsHandler = {}

function SettingsHandler.getSettings(player: Player): { [string]: boolean }
	local saved = PlayerDataHandler.get(player, SETTINGS_KEY)
	return SettingsData.withDefaults(if type(saved) == "table" then saved else nil)
end

local function sendSettings(player: Player)
	if PlayerDataHandler.waitForData(player) then
		network.fireClient(network.RemoteEvents.SettingsState, player, SettingsHandler.getSettings(player))
	end
end

local function onChangeSetting(player: Player, id: any, value: any)
	if not SettingsData.get(id) or type(value) ~= "boolean" or not PlayerDataHandler.getData(player) then
		return
	end

	local settings = SettingsHandler.getSettings(player)
	if settings[id] == value then
		return
	end
	settings[id] = value
	PlayerDataHandler.set(player, SETTINGS_KEY, settings)
end

--// Lifecycle ---------------------------------------------------------------------

function SettingsHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RequestSettings, sendSettings, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})
	network.connectEvent(network.RemoteEvents.ChangeSetting, onChangeSetting, {
		network.Middleware.RateLimit(CHANGE_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(sendSettings)
	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) then
			task.spawn(sendSettings, player)
		end
	end
end

return SettingsHandler
