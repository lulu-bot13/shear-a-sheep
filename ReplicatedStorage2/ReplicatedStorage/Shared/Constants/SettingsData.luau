--!strict

--[[
	Every player setting, in the order the Settings window lists them, with its default.

	Location: ReplicatedStorage.Shared.Constants.SettingsData
]]--

export type Setting = {
	id: string, -- the key saved in PlayerDataHandler's Settings and read with the client's Settings.get
	title: string,
	description: string,
	default: boolean,
}

local settingsData = {}

settingsData.List = {
	{
		id = "Music",
		title = "Music",
		description = "Play the background music.",
		default = true,
	},
	{
		id = "SoundEffects",
		title = "Sound Effects",
		description = "Sheep, ability and weather sounds.",
		default = true,
	},
	{
		id = "UISounds",
		title = "UI Sounds",
		description = "Button clicks, rewards and other menu sounds.",
		default = true,
	},
	{
		id = "LowGraphics",
		title = "Low Graphics",
		description = "Fewer particles, less rain and lighter effects for a smoother game.",
		default = false,
	},
	{
		id = "ScreenShake",
		title = "Screen Shake",
		description = "Shake the camera on big hits and rare sheep.",
		default = true,
	},
	{
		id = "HideOtherPlayers",
		title = "Hide Other Players",
		description = "Hide other players' characters and name tags.",
		default = false,
	},
	{
		id = "OtherAbilityEffects",
		title = "Other Players' Abilities",
		description = "Show the effects of abilities other players use.",
		default = true,
	},
	{
		id = "Announcements",
		title = "Server Announcements",
		description = "Show other players' rare finds, rebirths, Prestiges and gifts.",
		default = true,
	},
} :: { Setting }

local byId: { [string]: Setting } = {}
for _, setting in settingsData.List do
	byId[setting.id] = setting
end

function settingsData.get(id: any): Setting?
	return if type(id) == "string" then byId[id] else nil
end

-- Every known setting's saved value, or its default when the save doesn't have one; unknown ids are dropped.
function settingsData.withDefaults(saved: { [any]: any }?): { [string]: boolean }
	local values: { [string]: boolean } = {}
	for _, setting in settingsData.List do
		local value = if saved then saved[setting.id] else nil
		values[setting.id] = if type(value) == "boolean" then value else setting.default
	end
	return values
end

return settingsData
