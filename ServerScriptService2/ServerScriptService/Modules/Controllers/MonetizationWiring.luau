--!strict

--[[
	Plugs the monetization kit (ReceiptProcessor, GamePassService, GiftService, BadgeAwarder) into Shear A Sheep: its item config, its save data
	through PlayerDataHandler and ProfileServiceStore, and its toasts. The kit modules read everything game-specific from here.

	Location: ServerScriptService.Modules.Controllers.MonetizationWiring
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local ProfileServiceStore = require(script.Parent.Parent.Utils.ProfileServiceStore)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

export type Item = MonetizationData.Item

return {
	config = MonetizationData,

	-- get/set go through PlayerDataHandler so its attribute mirroring and Changed signal still run.
	store = ProfileServiceStore.new({
		profileStore = PlayerDataHandler.getProfileStore(),
		profileKey = PlayerDataHandler.getProfileKey,
		getProfile = PlayerDataHandler.getProfile,
		loaded = PlayerDataHandler.Loaded,
		changed = PlayerDataHandler.Changed,
		get = PlayerDataHandler.get,
		set = PlayerDataHandler.set,
	}),

	-- A toast for one player (AlertClient shows it with the Alerts banners).
	notify = function(player: Player, text: string, kind: "success" | "error" | "info")
		network.fireClient(network.RemoteEvents.ShowAlert, player, text, kind)
	end,
}
