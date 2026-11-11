--!strict

--[[
	Drops the tutorial's first sheep (a Huge Fluffy with its health cut down) and only lets it be sheared while it's out,
	then the next step's sheep straight into the pen. Also saves that the Crook tutorial has been shown.
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
local TUTORIAL_SHEEP = { sheepType = "Fluffy", size = "Huge", noMutation = true } -- Fluffy is also the first rebirth's required sheep
local TUTORIAL_SHEEP_HEALTH = 40 -- two swings of the default shears
local TUTORIAL_ATTRIBUTE = "TutorialSheep" -- TutorialClient leads the player to the sheep with this
local FOLLOW_UP_SHEEP = 2 -- TutorialClient's "Shear 2 Sheep" step; dropped straight into the pen once the first sheep is bare
local FOLLOW_UP_SPAWN = { size = "Normal", noMutation = true } -- type still rolled; a Normal size skips the Huge windup
local SPAWN_ATTEMPTS = 15 -- the farm may still be starting when the client asks
local RETRY_SECONDS = 1
local CROOK_TUTORIAL_KEY = "CrookTutorialDone" -- PlayerDataHandler field, 1 once CrookTutorialClient has run
local CROOK_DONE_COOLDOWN = 1

--// State
local requested: { [Player]: boolean } = {}
local tutorialSheep: { [Player]: Model } = {}

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
		local sheep = SheepSpawnHandler.spawnForced(player, TUTORIAL_SHEEP)
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

-- The sheep the next tutorial step needs, dropped inside the pen (not on the conveyor, where they'd bolt off first).
local function spawnFollowUpSheep(player: Player)
	local positions: { Vector3 } = {}
	for _ = 1, FOLLOW_UP_SHEEP do
		local sheep = SheepSpawnHandler.spawnForced(player, FOLLOW_UP_SPAWN)
		if sheep then
			table.insert(positions, sheep:GetPivot().Position)
		end
	end
	if #positions > 0 then
		network.fireAllClients(network.RemoteEvents.SheepPoof, positions)
	end
end

local function onRequest(player: Player)
	if requested[player] or not PlayerDataHandler.waitForData(player) then
		return
	end
	if not runService:IsStudio() and not isNewPlayer(player) then
		return
	end
	requested[player] = true
	spawnTutorialSheep(player)
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

	network.connectEvent(network.RemoteEvents.RequestTutorialSheep, onRequest)
	network.connectEvent(network.RemoteEvents.CrookTutorialDone, onCrookTutorialDone, {
		network.Middleware.RateLimit(CROOK_DONE_COOLDOWN),
	})

	SheepHandler.Sheared:Connect(function(player: Player, sheep: Model)
		if tutorialSheep[player] == sheep then
			clearTutorialSheep(player)
			spawnFollowUpSheep(player)
		end
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		requested[player] = nil
		clearTutorialSheep(player)
	end)
end

return TutorialHandler
