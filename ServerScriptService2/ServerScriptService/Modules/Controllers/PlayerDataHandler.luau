--!strict

--[[
	ProfileService save for each player's farm (wool, luck, Gems, sheep capacity, upgrades, rebirths, Prestiges, shears, sheep sheared).
	Wool and Luck are mirrored to Player.Inventory IntValues and the other numbers to player attributes for the client.

	Location: ServerScriptService.Modules.Controllers.PlayerDataHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local profileService = require(script.Parent.Parent.Packages.ProfileService) :: any
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)

--// Configs
local PROFILE_STORE_NAME = "PlayerData1"
local STUDIO_PROFILE_STORE_NAME = "PlayerDataTest1"
local KEY_PREFIX = "Player_"
local INVENTORY_NAME = "Inventory"
local INVENTORY_KEYS = { Wool = true, Luck = true } -- the rest of the numbers become player attributes
local RENAMED_KEYS = { WoolGainLevel = "MoreWoolLevel" } -- old save key -> current key
local REMOVED_KEYS = { LuckLevel = true } -- dropped from older saves
-- Preferences and anything bought with Robux, not progress.
local KEPT_ON_RESET = { Settings = true, GiftedPasses = true, Boosts = true, FreeRebirths = true, PendingGifts = true, GiftOutbox = true,
	FirstJoinAt = true, SessionCount = true, StarterPackBought = true, AutoShearTrialUsed = true }

export type Data = {
	Wool: number,
	Luck: number,
	Gems: number, -- rare currency from GemHandler drops (kept through rebirths and Prestiges)
	MaxSheep: number,
	SheepCount: number?, -- sheep on the farm when the player left; nil = start with a full farm
	MoreWoolLevel: number,
	SpeedLevel: number, -- Faster Speed upgrade levels
	DamageLevel: number, -- Shear Damage upgrade levels
	RespawnLevel: number, -- Faster Respawn upgrade levels
	SpawnLuckLevel: number,
	SizeLevel: number,
	Rebirths: number,
	Prestiges: number,
	RebirthPitySpawns: number,
	GoalStep: number,
	GoalQuests: { [string]: any },
	ShearId: string,
	OwnedShears: { string },
	AbilityEquipped: string, -- AbilityData id of the ability used on E
	OwnedAbilities: { string }, -- AbilityData ids won at the Ability Shack
	AbilityPity: number, -- Ability Shack rolls in a row without an AbilityData.PityRarities ability
	SheepShearedCount: number, -- lifetime sheep shorn bare (kept through rebirths); unlocks shears
	BestFind: string, -- SheepData type key of the rarest sheep ever shorn; "" = none yet
	SheepIndex: { [string]: string }, -- Index key (sheep type, or "<mutation>:<type>", see SheepData.getIndexKey) -> "Found" | "Claimed" (kept through rebirths)
	PodiumSheep: { [string]: any }, -- podium name -> SheepHandler.SavedSheep standing on it
	CrookTutorialDone: number, -- 1 once the Shepherd's Crook tutorial has been shown (a number so it mirrors to an attribute)
	Settings: { [string]: boolean }, -- SettingsData id -> value (kept through rebirths, Prestiges and /resetdata)
	DailyStreak: number, -- daily rewards claimed in the current streak (kept through rebirths and Prestiges)
	DailyLastClaim: number, -- os.time() of the last daily reward claim; 0 = never
	DailyCycles: number, -- full 7-day daily reward loops completed
	GiftedPasses: { [string]: boolean }, -- MonetizationData game pass key -> true once another player gifted it
	Boosts: { [string]: number }, -- MonetizationData boost key -> seconds left (only counts down in game)
	FreeRebirths: number, -- Skip Rebirths bought while at max rebirths, used once a rebirth is possible again
	PendingGifts: { [string]: { userId: number, name: string } }, -- item key -> the player picked in the gift window, until its receipt arrives
	GiftOutbox: { [string]: { item: string, userId: number, name: string } }, -- PurchaseId -> paid gift not yet delivered
	FirstJoinAt: number,
	SessionCount: number,
	StarterPackBought: number,
	AutoShearTrialUsed: number,
}

local DataTemplate = {
	-- Currencies
	Wool = 100, -- starter wool: with the tutorial's first 3 sheep it pays for its 3 upgrades in one shop visit
	Luck = 0,
	Gems = 0,

	-- Farm
	MaxSheep = FarmData.StartingMaxSheep,
	SheepCount = nil,

	-- Upgrades
	MoreWoolLevel = 0,
	SpeedLevel = 0,
	DamageLevel = 0,
	RespawnLevel = 0,
	SpawnLuckLevel = 0, -- Spawn Luck upgrade levels (capped per rebirth, see SpawnOdds)
	SizeLevel = 0, -- Sheep Size upgrade levels

	-- Progression
	Rebirths = 0,
	Prestiges = 0,
	RebirthPitySpawns = 0, -- spawns rolled while hunting the rebirth sheep (RebirthHandler)

	-- Goals (GoalHandler)
	GoalStep = 0, -- milestones done, in GoalData.Milestones order
	GoalQuests = {}, -- this session's quest set: { ids = { string }, index = number, progress = number }

	-- Shears
	ShearId = ShearData.DefaultShearId,
	OwnedShears = { ShearData.DefaultShearId },

	-- Abilities
	AbilityEquipped = AbilityData.DefaultAbilityId,
	OwnedAbilities = { AbilityData.DefaultAbilityId },
	AbilityPity = 0,

	-- Index
	SheepShearedCount = 0,
	BestFind = "",
	SheepIndex = {},
	PodiumSheep = {},

	-- Tutorials
	CrookTutorialDone = 0,

	-- Settings
	Settings = {},

	-- Daily rewards
	DailyStreak = 0,
	DailyLastClaim = 0,
	DailyCycles = 0,

	-- Robux shop
	GiftedPasses = {},
	Boosts = {},
	FreeRebirths = 0,
	PendingGifts = {},
	GiftOutbox = {},

	-- Offers (OfferHandler)
	FirstJoinAt = 0, -- os.time() of the first load with offers; 0 = not set yet (older saves get it on their next load)
	SessionCount = 0, -- loads since FirstJoinAt was set
	StarterPackBought = 0, -- 1 once the Starter Pack was bought
	AutoShearTrialUsed = 0, -- 1 once the free Auto Shears trial was used
}

-- Creating a profile store (Studio saves go to a separate test store)
local profileStore = profileService.GetProfileStore(
	if runService:IsStudio() then STUDIO_PROFILE_STORE_NAME else PROFILE_STORE_NAME,
	DataTemplate
)

--// State
local profiles: { [Player]: any } = {}

local PlayerDataHandler = {}

PlayerDataHandler.Loaded = Signal.new() -- (player, data)
PlayerDataHandler.Changed = Signal.new() -- (player, key, value)

local function deepCopy(original: { [any]: any }): { [any]: any }
	local copy = {}
	for key, value in original do
		copy[key] = if type(value) == "table" then deepCopy(value) else value
	end
	return copy
end

--// Mirroring -------------------------------------------------------------------------

local function getInventory(player: Player): Folder
	local existing = player:FindFirstChild(INVENTORY_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = INVENTORY_NAME
	folder.Parent = player
	return folder
end

local function mirror(player: Player, key: string, value: any)
	if type(value) == "string" then
		player:SetAttribute(key, value)
		return
	elseif type(value) ~= "number" then
		return
	end

	if INVENTORY_KEYS[key] then
		local inventory = getInventory(player)
		local item = inventory:FindFirstChild(key) :: IntValue?
		if not item then
			local newItem = Instance.new("IntValue")
			newItem.Name = key
			newItem.Parent = inventory
			item = newItem
		end
		(item :: IntValue).Value = value
	else
		player:SetAttribute(key, value)
	end
end

--// Loading ---------------------------------------------------------------------------

-- Renames/removes old keys, fills in any field the save is missing and drops values of the wrong type.
local function reconcile(profile: any)
	local data = profile.Data
	for oldKey, newKey in RENAMED_KEYS do
		if data[oldKey] ~= nil then
			data[newKey] = data[oldKey]
			data[oldKey] = nil
		end
	end
	for key in REMOVED_KEYS do
		data[key] = nil
	end

	profile:Reconcile()

	for key, default in DataTemplate :: any do
		if type(data[key]) ~= type(default) then
			data[key] = if type(default) == "table" then deepCopy(default) else default
		end
	end

	-- Known abilities only, once each, always with the default; the equipped one must be owned (e.g. one renamed or removed).
	local ownedAbilities = { AbilityData.DefaultAbilityId }
	for _, savedId in data.OwnedAbilities do
		local id = AbilityData.RenamedAbilities[savedId] or savedId
		if AbilityData.get(id) and not table.find(ownedAbilities, id) then
			table.insert(ownedAbilities, id)
		end
	end
	data.OwnedAbilities = ownedAbilities
	data.AbilityEquipped = AbilityData.RenamedAbilities[data.AbilityEquipped] or data.AbilityEquipped
	if not table.find(ownedAbilities, data.AbilityEquipped) then
		data.AbilityEquipped = AbilityData.DefaultAbilityId
	end
end

local function loadData(player: Player)
	for key, value in profiles[player].Data do
		mirror(player, key, value)
	end

	PlayerDataHandler.Loaded:Fire(player, profiles[player].Data)
end

local function onPlayerAdded(player: Player)
	getInventory(player)

	local profile = profileStore:LoadProfileAsync(KEY_PREFIX .. player.UserId)
	if profile == nil then
		player:Kick("Your data couldn't be loaded, please rejoin.")
		return
	end

	profile:AddUserId(player.UserId)
	reconcile(profile)

	profile:ListenToRelease(function()
		profiles[player] = nil
		player:Kick("Your data was loaded on another server, please rejoin.")
	end)

	if player:IsDescendantOf(players) then
		profiles[player] = profile
		loadData(player)
	else
		profile:Release()
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:Release()
	end
end

--// Public API ------------------------------------------------------------------------

-- The player's data, or nil until it has loaded.
function PlayerDataHandler.getData(player: Player): Data?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Yields until the player's data has loaded; nil if they left first.
function PlayerDataHandler.waitForData(player: Player): Data?
	while player.Parent and not profiles[player] do
		task.wait()
	end
	return PlayerDataHandler.getData(player)
end

function PlayerDataHandler.get(player: Player, key: string): any
	local data = PlayerDataHandler.getData(player) :: any
	return if data then data[key] else nil
end

function PlayerDataHandler.set(player: Player, key: string, value: any)
	local data = PlayerDataHandler.getData(player) :: any
	if not data then
		return
	end

	data[key] = value
	mirror(player, key, value)
	PlayerDataHandler.Changed:Fire(player, key, value)
end

-- Puts every field but the KEPT_ON_RESET ones back to a brand-new player's value, firing Changed for each so other systems update.
function PlayerDataHandler.reset(player: Player)
	if not profiles[player] then
		return
	end

	for key, value in deepCopy(DataTemplate) do
		if not KEPT_ON_RESET[key] then
			PlayerDataHandler.set(player, key, value)
		end
	end
	PlayerDataHandler.set(player, "SheepCount", nil)
end

-- Adds to a number field and returns the new value (nil if the data isn't loaded).
function PlayerDataHandler.increment(player: Player, key: string, amount: number): number?
	local current = PlayerDataHandler.get(player, key)
	if type(current) ~= "number" then
		return nil
	end

	local newValue = current + amount
	PlayerDataHandler.set(player, key, newValue)
	return newValue
end

-- Takes `amount` off a number field; false (and nothing taken) if the player doesn't have enough.
function PlayerDataHandler.spend(player: Player, key: string, amount: number): boolean
	local current = PlayerDataHandler.get(player, key)
	if type(current) ~= "number" or amount < 0 or current < amount then
		return false
	end

	PlayerDataHandler.set(player, key, current - amount)
	return true
end

-- For the monetization kit's ProfileServiceStore (MonetizationWiring): the loaded profile, the ProfileStore and a player's profile key.
function PlayerDataHandler.getProfile(player: Player): any
	return profiles[player]
end

function PlayerDataHandler.getProfileStore(): any
	return profileStore
end

function PlayerDataHandler.getProfileKey(userId: number): string
	return KEY_PREFIX .. userId
end

--// Lifecycle -----------------------------------------------------------------------

function PlayerDataHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		for _, player in players:GetPlayers() do
			onPlayerRemoving(player)
		end
	end)
end

return PlayerDataHandler
