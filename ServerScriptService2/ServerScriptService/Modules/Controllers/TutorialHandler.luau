--!strict

--[[
	Drops the tutorial's first sheep (the only one shearable while it's out; asked for again if it's lost), then the next step's sheep;
	saves the Crook tutorial. Before the first rebirth, forces the rebirth sheep into the pen once TUTORIAL_PITY_SHEARS sheep are sheared.
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
-- Nothing forced: type, size and mutation roll like any sheep entering the pen (a forced spawn still skips pity and charge).
local NORMAL_ROLL: SheepHandler.ForcedSpawn = {}
local TUTORIAL_SHEEP_HEALTH = 40 -- two swings of the default shears
local TUTORIAL_ATTRIBUTE = "TutorialSheep" -- TutorialClient leads the player to the sheep with this
local FOLLOW_UP_SHEEP = 2 -- TutorialClient's "Shear 2 Sheep" step; dropped straight into the pen once the first sheep is bare
local SPAWN_ATTEMPTS = 15 -- the farm may still be starting when the client asks
local RETRY_SECONDS = 1
local CROOK_TUTORIAL_KEY = "CrookTutorialDone" -- PlayerDataHandler field, 1 once CrookTutorialClient has run
local CROOK_DONE_COOLDOWN = 1
local REQUEST_COOLDOWN = 1 -- TutorialClient asks again every few seconds while it has no tutorial sheep to lead to
local TUTORIAL_PITY_SHEARS = 5 -- lifetime sheep sheared before the first rebirth's sheep is guaranteed in the pen

--// State
local spawning: { [Player]: boolean } = {}
local firstShearDone: { [Player]: boolean } = {} -- the tutorial sheep was sheared this session (Studio saves aren't "new", so this stops a second one)
local tutorialSheep: { [Player]: Model } = {}
local pitySpawning: { [Player]: boolean } = {}

local TutorialHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function isNewPlayer(player: Player): boolean
	return getNumber(player, "SheepShearedCount") == 0 and getNumber(player, "Rebirths") == 0 and getNumber(player, "Prestiges") == 0
end

-- Pooled sheep keep their attributes, so the mark comes off as soon as the sheep is done with.
local function clearTutorialSheep(player: Player)
	local sheep = tutorialSheep[player]
	tutorialSheep[player] = nil
	if sheep then
		sheep:SetAttribute(TUTORIAL_ATTRIBUTE, nil)
	end
end

local function spawnTutorialSheep(player: Player)
	for _ = 1, SPAWN_ATTEMPTS do
		if not player.Parent then
			return
		end
		local sheep = SheepSpawnHandler.spawnForced(player, NORMAL_ROLL)
		if sheep then
			sheep:SetAttribute("MaxShearHealth", TUTORIAL_SHEEP_HEALTH)
			sheep:SetAttribute("ShearHealth", TUTORIAL_SHEEP_HEALTH)
			sheep:SetAttribute(TUTORIAL_ATTRIBUTE, true)
			tutorialSheep[player] = sheep
			network.fireAllClients(network.RemoteEvents.SheepPoof, { sheep:GetPivot().Position })
			return
		end
		task.wait(RETRY_SECONDS)
	end
end

-- The sheep the next tutorial step needs, dropped straight into the pen.
local function spawnFollowUpSheep(player: Player)
	local positions: { Vector3 } = {}
	for _ = 1, FOLLOW_UP_SHEEP do
		local sheep = SheepSpawnHandler.spawnForced(player, NORMAL_ROLL)
		if sheep then
			table.insert(positions, sheep:GetPivot().Position)
		end
	end
	if #positions > 0 then
		network.fireAllClients(network.RemoteEvents.SheepPoof, positions)
	end
end

-- True while one of the player's sheep of this adult type (any variant) is on their farm.
local function hasSheepOfType(player: Player, adultType: string): boolean
	for _, sheep in SheepHandler.getAllSheep() do
		if sheep:GetAttribute("OwnerId") == player.UserId and sheep:GetAttribute("AdultType") == adultType then
			return true
		end
	end
	return false
end

--[[
	Tutorial pity: before the first rebirth (and any Prestige), once TUTORIAL_PITY_SHEARS sheep are sheared and the rebirth sheep is
	still unfound, it's dropped into the pen unless one is already there. Checked on every shear, so a lost one comes back.
	SheepSpawnHandler plays its cutscene and resets the spawn pity.
]]
local function checkTutorialPity(player: Player)
	if pitySpawning[player] or getNumber(player, "Rebirths") > 0 or getNumber(player, "Prestiges") > 0
		or getNumber(player, "SheepShearedCount") < TUTORIAL_PITY_SHEARS
	then
		return
	end
	local required, found = RebirthHandler.getRequirement(player)
	if not required or found or hasSheepOfType(player, required) then
		return
	end

	pitySpawning[player] = true
	local sheep = SheepSpawnHandler.spawnForced(player, { sheepType = required, size = "Normal" })
	if sheep then
		network.fireAllClients(network.RemoteEvents.SheepPoof, { sheep:GetPivot().Position })
	end
	pitySpawning[player] = nil
end

-- Repeat asks are fine: nothing drops while the player's tutorial sheep is still out, or once it has been sheared.
local function onRequest(player: Player)
	if spawning[player] or firstShearDone[player] or not PlayerDataHandler.waitForData(player) then
		return
	end
	if (not runService:IsStudio() and not isNewPlayer(player)) or TutorialHandler.getSheep(player) then
		return
	end
	spawning[player] = true
	spawnTutorialSheep(player)
	spawning[player] = nil
end

-- The Crook tutorial is shown once per save, so it's marked done as soon as the client finishes it.
local function onCrookTutorialDone(player: Player)
	if getNumber(player, CROOK_TUTORIAL_KEY) ~= 1 then
		PlayerDataHandler.set(player, CROOK_TUTORIAL_KEY, 1)
	end
end

--// Public API ----------------------------------------------------------------------

-- The player's tutorial sheep while it's still on their farm; ShearHandler only lets that one be sheared until it's bare.
function TutorialHandler.getSheep(player: Player): Model?
	local sheep = tutorialSheep[player]
	if not sheep then
		return nil
	end
	local id = sheep:GetAttribute("id")
	if type(id) == "number" and SheepHandler.getSheep(id) == sheep and sheep:GetAttribute(TUTORIAL_ATTRIBUTE) then
		return sheep
	end
	clearTutorialSheep(player)
	return nil
end

--// Lifecycle -----------------------------------------------------------------------

function TutorialHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RequestTutorialSheep, onRequest, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})
	network.connectEvent(network.RemoteEvents.CrookTutorialDone, onCrookTutorialDone, {
		network.Middleware.RateLimit(CROOK_DONE_COOLDOWN),
	})

	SheepHandler.Sheared:Connect(function(player: Player, sheep: Model)
		if tutorialSheep[player] == sheep then
			firstShearDone[player] = true
			clearTutorialSheep(player)
			spawnFollowUpSheep(player)
		end
	end)

	-- After the count goes up (Sheared fires before it does), so the 5th shear is the one that brings the rebirth sheep.
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "SheepShearedCount" then
			task.defer(checkTutorialPity, player)
		end
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		spawning[player] = nil
		firstShearDone[player] = nil
		pitySpawning[player] = nil
		clearTutorialSheep(player)
	end)
end

return TutorialHandler
