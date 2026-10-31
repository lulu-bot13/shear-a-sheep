--!strict

--[[
	Drops the tutorial's first sheep when TutorialClient asks: a Huge Basic Sheep whose health is cut right down after it spawns,
	so the player's first shear is quick. Only for players who haven't sheared yet (or anyone in Studio), once per session.
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
local TUTORIAL_SHEEP = { sheepType = "Basic", size = "Huge", noMutation = true }
local TUTORIAL_SHEEP_HEALTH = 40 -- two swings of the default shears (a normal Huge Basic has 220)
local TUTORIAL_ATTRIBUTE = "TutorialSheep" -- TutorialClient leads the player to the sheep with this
local SPAWN_ATTEMPTS = 15 -- the farm may still be starting when the client asks
local RETRY_SECONDS = 1

--// State
local requested: { [Player]: boolean } = {}

local TutorialHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function isNewPlayer(player: Player): boolean
	return getNumber(player, "SheepShearedCount") == 0 and getNumber(player, "Rebirths") == 0 and getNumber(player, "Prestiges") == 0
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
			return
		end
		task.wait(RETRY_SECONDS)
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

function TutorialHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RequestTutorialSheep, onRequest)

	players.PlayerRemoving:Connect(function(player: Player)
		requested[player] = nil
	end)
end

return TutorialHandler
