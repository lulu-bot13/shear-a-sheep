--!strict

--[[
	Temporary DataStore save for each player's farm (wool, luck, Gems, sheep capacity, upgrades, rebirths, Prestiges, shears, sheep sheared).
	Wool and Luck are mirrored to Player.Inventory IntValues and the other numbers to player attributes for the client.

	Location: ServerScriptService.Modules.Controllers.PlayerDataHandler
]]--

--// Services
local dataStoreService = game:GetService("DataStoreService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)

--// Configs
local DATASTORE_NAME = "PlayerData_Temp_v2"
local KEY_PREFIX = "Player_"
local LOAD_ATTEMPTS = 3
local RETRY_SECONDS = 1
local AUTOSAVE_SECONDS = 120
local INVENTORY_NAME = "Inventory"
local INVENTORY_KEYS = { Wool = true, Luck = true } -- the rest of the numbers become player attributes
local RENAMED_KEYS = { WoolGainLevel = "MoreWoolLevel" } -- old save key -> current key
local REMOVED_KEYS = { LuckLevel = true } -- dropped from older saves

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
	Rebirths: number,
	Prestiges: number,
	ShearId: string,
	OwnedShears: { string },
	AbilityEquipped: string, -- AbilityData id of the ability used on E
	OwnedAbilities: { string }, -- AbilityData ids won at the Ability Shack
	AbilityPity: number, -- Ability Shack rolls in a row without an AbilityData.PityRarities ability
	SheepShearedCount: number, -- lifetime sheep shorn bare (kept through rebirths); unlocks shears
	BestFind: string, -- SheepData type key of the rarest sheep ever shorn; "" = none yet
	SheepIndex: { [string]: string }, -- sheep type -> "Found" | "Claimed" (kept through rebirths)
	PodiumSheep: { [string]: any }, -- podium name -> SheepHandler.SavedSheep standing on it
}

local function getDefaultData(): Data
	return {
		Wool = 100, -- starter wool: after the tutorial's More Wool upgrade it covers ~85% of the first rebirth
		Luck = 0,
		Gems = 0,
		MaxSheep = FarmData.StartingMaxSheep,
		SheepCount = nil,
		MoreWoolLevel = 0,
		SpeedLevel = 0,
		DamageLevel = 0,
		RespawnLevel = 0,
		Rebirths = 0,
		Prestiges = 0,
		ShearId = ShearData.DefaultShearId,
		OwnedShears = { ShearData.DefaultShearId },
		AbilityEquipped = AbilityData.DefaultAbilityId,
		OwnedAbilities = { AbilityData.DefaultAbilityId },
		AbilityPity = 0,
		SheepShearedCount = 0,
		BestFind = "",
		SheepIndex = {},
		PodiumSheep = {},
	}
end

--// State
local dataStore: DataStore? = nil
local profiles: { [Player]: Data } = {}
local canSave: { [Player]: boolean } = {} -- false when loading failed, so defaults never overwrite a real save

local PlayerDataHandler = {}

PlayerDataHandler.Loaded = Signal.new() -- (player, data)
PlayerDataHandler.Changed = Signal.new() -- (player, key, value)

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

--// Loading and saving ------------------------------------------------------------------

local function getKey(player: Player): string
	return KEY_PREFIX .. player.UserId
end

-- Fills in any field the save is missing (e.g. one added after the player last played).
local function reconcile(saved: any): Data
	local data = getDefaultData() :: any
	if type(saved) == "table" then
		for oldKey, value in saved do
			local key = RENAMED_KEYS[oldKey] or oldKey
			if REMOVED_KEYS[key] then
				continue
			end
			if data[key] == nil or type(data[key]) == type(value) then
				data[key] = value
			end
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
	return data :: Data
end

local function loadData(player: Player): (Data, boolean)
	if not dataStore then
		return getDefaultData(), false
	end

	for attempt = 1, LOAD_ATTEMPTS do
		local success, result = pcall(function()
			return (dataStore :: DataStore):GetAsync(getKey(player))
		end)
		if success then
			return reconcile(result), true
		end
		warn(`PlayerDataHandler: loading {player.Name} failed (attempt {attempt}): {result}`)
		task.wait(RETRY_SECONDS)
	end

	return getDefaultData(), false
end

local function saveData(player: Player)
	local data = profiles[player]
	if not data or not canSave[player] or not dataStore then
		return
	end

	local success, err = pcall(function()
		(dataStore :: DataStore):SetAsync(getKey(player), data, { player.UserId })
	end)
	if not success then
		warn(`PlayerDataHandler: saving {player.Name} failed: {err}`)
	end
end

local function onPlayerAdded(player: Player)
	getInventory(player)

	local data, loaded = loadData(player)
	if not player.Parent then
		return
	end

	profiles[player] = data
	canSave[player] = loaded

	for key, value in data :: any do
		mirror(player, key, value)
	end

	PlayerDataHandler.Loaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	saveData(player)
	profiles[player] = nil
	canSave[player] = nil
end

--// Public API ------------------------------------------------------------------------

-- The player's data, or nil until it has loaded.
function PlayerDataHandler.getData(player: Player): Data?
	return profiles[player]
end

-- Yields until the player's data has loaded; nil if they left first.
function PlayerDataHandler.waitForData(player: Player): Data?
	while player.Parent and not profiles[player] do
		task.wait()
	end
	return profiles[player]
end

function PlayerDataHandler.get(player: Player, key: string): any
	local data = profiles[player] :: any
	return if data then data[key] else nil
end

function PlayerDataHandler.set(player: Player, key: string, value: any)
	local data = profiles[player] :: any
	if not data then
		return
	end

	data[key] = value
	mirror(player, key, value)
	PlayerDataHandler.Changed:Fire(player, key, value)
end

-- Puts every field back to a brand-new player's value, firing Changed for each so other systems update.
function PlayerDataHandler.reset(player: Player)
	if not profiles[player] then
		return
	end

	for key, value in getDefaultData() :: any do
		PlayerDataHandler.set(player, key, value)
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

--// Lifecycle -----------------------------------------------------------------------

function PlayerDataHandler.Setup()
	local success, result = pcall(function()
		return dataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if success then
		dataStore = result
	else
		warn(`PlayerDataHandler: DataStores unavailable, progress won't save ({result}).`)
	end

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in profiles do
				task.spawn(saveData, player)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveData(player)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return PlayerDataHandler
