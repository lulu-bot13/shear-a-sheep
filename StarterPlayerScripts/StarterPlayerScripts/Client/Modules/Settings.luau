--!strict

--[[
	The player's settings (SettingsData): loads the saved values, applies music, sound and Hide Other Players itself,
	and hands the rest to other scripts through get() and changed. Changes apply at once and are saved in the background.

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Settings
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SettingsData = require(replicatedStorage.Shared.Constants.SettingsData)
local backgroundMusic = require(script.Parent.BackgroundMusic)

--// Instances
local localPlayer = players.LocalPlayer

--// Configs
local SAVE_SPACING = 0.25 -- seconds between ChangeSetting sends, just over SettingsHandler's rate limit so none are dropped
local LOAD_TIMEOUT = 15 -- the defaults are applied if the saved settings haven't arrived by then
local LOW_GRAPHICS_EFFECTS = 0.35 -- particle and chunk counts are multiplied by this while Low Graphics is on
local SOUND_GROUP_WAIT = 10
local SOUND_GROUPS: { [string]: { string } } = { -- setting -> the SoundService SoundGroups it mutes
	SoundEffects = { "Sheep", "AbilitySounds", "Weather" },
	UISounds = { "UISounds" },
}
local PLAYER_HUD_NAME = "PlayerHUD" -- the name tag PlayerHUD.server puts on every character
local EFFECT_CLASSES = { "ParticleEmitter", "Trail", "Beam", "Light" } -- LocalTransparencyModifier doesn't hide these

--// State
local values = SettingsData.withDefaults(nil)
local loaded = false
local touched: { [string]: boolean } = {} -- changed before the saved settings arrived, so the saved value doesn't undo it
local pendingSaves: { [string]: boolean } = {}
local saving = false
local mutedGroups: { [string]: { SoundGroup } } = {} -- setting -> the groups it sets to 0
local groupVolumes: { [SoundGroup]: number } = {} -- each group's own volume, put back when unmuted
local hiddenEffects: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- effects switched off on hidden characters -> whether they were on

local changedEvent = Instance.new("BindableEvent")

local Settings = {}
Settings.changed = changedEvent.Event -- (id, value) whenever a setting changes, including when the saved ones load

--// Sound -----------------------------------------------------------------------

local function applySound(id: string)
	for _, group in mutedGroups[id] or {} do
		group.Volume = if values[id] then groupVolumes[group] else 0
	end
end

--[[
	A sound only plays through a SoundGroup when its SoundGroup property says so; sitting under one isn't enough.
	Sounds under a muted group that aren't routed anywhere go through a client-made group at volume 1, so the mix doesn't change.
]]
local function routeSound(instance: Instance, routeGroup: SoundGroup)
	if instance:IsA("Sound") and instance.SoundGroup == nil then
		instance.SoundGroup = routeGroup
	end
end

local function watchSoundGroups(id: string, names: { string })
	local routeGroup = Instance.new("SoundGroup")
	routeGroup.Name = `{id}Setting`
	routeGroup.Volume = 1
	routeGroup.Parent = soundService
	groupVolumes[routeGroup] = 1
	mutedGroups[id] = { routeGroup }
	applySound(id)

	for _, name in names do
		local group = soundService:WaitForChild(name, SOUND_GROUP_WAIT)
		if not group or not group:IsA("SoundGroup") then
			warn(`[Settings] SoundService.{name} isn't a SoundGroup, so the {id} setting can't mute it`)
			continue
		end
		groupVolumes[group] = group.Volume
		table.insert(mutedGroups[id], group)
		for _, descendant in group:GetDescendants() do
			routeSound(descendant, routeGroup)
		end
		group.DescendantAdded:Connect(function(descendant: Instance)
			routeSound(descendant, routeGroup)
		end)
		applySound(id)
	end
end

-- Music waits for the saved settings, so a player who turned it off doesn't hear it start on join.
local function applyMusic()
	backgroundMusic.setEnabled(loaded and values.Music)
end

--// Hide Other Players ----------------------------------------------------------

local function isEffect(instance: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function applyHidden(instance: Instance, hidden: boolean)
	if instance:IsA("BasePart") or instance:IsA("Decal") then
		(instance :: any).LocalTransparencyModifier = if hidden then 1 else 0
	elseif instance:IsA("BillboardGui") and instance.Name == PLAYER_HUD_NAME then
		instance.Enabled = not hidden
	elseif isEffect(instance) then
		local effect = instance :: any
		if hidden then
			if hiddenEffects[instance] == nil then
				hiddenEffects[instance] = effect.Enabled
			end
			effect.Enabled = false
		elseif hiddenEffects[instance] ~= nil then
			effect.Enabled = hiddenEffects[instance]
			hiddenEffects[instance] = nil
		end
	end
end

local function applyHideOthers()
	for _, other in players:GetPlayers() do
		if other ~= localPlayer and other.Character then
			for _, descendant in other.Character:GetDescendants() do
				applyHidden(descendant, values.HideOtherPlayers)
			end
		end
	end
end

-- Respawns, late-loading accessories and re-equipped tools are caught as they're added.
local function watchCharacter(character: Model)
	character.DescendantAdded:Connect(function(descendant: Instance)
		applyHidden(descendant, values.HideOtherPlayers)
	end)
	if values.HideOtherPlayers then
		for _, descendant in character:GetDescendants() do
			applyHidden(descendant, true)
		end
	end
end

local function watchPlayer(other: Player)
	if other == localPlayer then
		return
	end
	other.CharacterAdded:Connect(watchCharacter)
	if other.Character then
		watchCharacter(other.Character)
	end
end

--// Applying and saving -------------------------------------------------------------

local APPLIERS: { [string]: () -> () } = {
	Music = applyMusic,
	SoundEffects = function()
		applySound("SoundEffects")
	end,
	UISounds = function()
		applySound("UISounds")
	end,
	HideOtherPlayers = applyHideOthers,
}

local function setValue(id: string, value: boolean)
	if values[id] == value then
		return
	end
	values[id] = value
	local apply = APPLIERS[id]
	if apply then
		apply()
	end
	changedEvent:Fire(id, value)
end

-- Sends the changed settings one at a time, spaced past the server's rate limit; the latest value of each is what's sent.
local function flushSaves()
	if saving then
		return
	end
	saving = true
	network.waitUntilReadyAsync()
	while true do
		local id = next(pendingSaves)
		if not id then
			break
		end
		pendingSaves[id] = nil
		network.fireServer(network.RemoteEvents.ChangeSetting, id, values[id])
		task.wait(SAVE_SPACING)
	end
	saving = false
end

local function onSettingsState(saved: any)
	if type(saved) ~= "table" then
		return
	end

	local merged = SettingsData.withDefaults(saved)
	for _, setting in SettingsData.List do
		if not touched[setting.id] then
			setValue(setting.id, merged[setting.id])
		end
	end
	if not loaded then
		loaded = true
		applyMusic()
	end
end

--// Public API ------------------------------------------------------------------

function Settings.get(id: string): boolean
	return values[id] == true
end

-- Applies the setting straight away and saves it.
function Settings.set(id: string, value: boolean)
	if not SettingsData.get(id) or type(value) ~= "boolean" then
		return
	end
	if not loaded then
		touched[id] = true
	end
	setValue(id, value)
	pendingSaves[id] = true
	task.spawn(flushSaves)
end

-- `count` cut down while Low Graphics is on (a non-zero count never drops to 0), for particle bursts and debris.
function Settings.effectCount(count: number): number
	if count <= 0 or not values.LowGraphics then
		return count
	end
	return math.max(math.floor(count * LOW_GRAPHICS_EFFECTS + 0.5), 1)
end

--// Setup -------------------------------------------------------------------------------

applyMusic()

for id, names in SOUND_GROUPS do
	task.spawn(watchSoundGroups, id, names)
end

players.PlayerAdded:Connect(watchPlayer)
for _, other in players:GetPlayers() do
	watchPlayer(other)
end

task.spawn(function()
	network.waitUntilReadyAsync()
	network.connectEvent(network.RemoteEvents.SettingsState, onSettingsState)
	network.fireServer(network.RemoteEvents.RequestSettings)
end)

task.delay(LOAD_TIMEOUT, function()
	if not loaded then
		warn("[Settings] the saved settings didn't arrive, so the defaults are used")
		loaded = true
		applyMusic()
	end
end)

return Settings
