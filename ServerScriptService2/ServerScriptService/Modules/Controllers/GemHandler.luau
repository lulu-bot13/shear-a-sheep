--!strict

--[[
	Gems, the rare currency: rolls the GemData drop for each sheep shorn bare and tells the finder (GemClient shows the popup).
	Gems are mirrored as a leaderstat, placed after Prestige.

	Location: ServerScriptService.Modules.Controllers.GemHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local GemData = require(script.Parent.Parent.Constants.GemData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local LEADERSTATS_WAIT_SECONDS = 15

--// State
local random = Random.new()

local GemHandler = {}

local function getGems(player: Player): number
	local value = PlayerDataHandler.get(player, "Gems")
	return if type(value) == "number" then value else 0
end

--// Public API ------------------------------------------------------------------

-- Adds Gems and fires GemFound to the player; returns the new total (nil if the data isn't loaded).
function GemHandler.give(player: Player, amount: number): number?
	local newGems = PlayerDataHandler.increment(player, "Gems", amount)
	if newGems then
		network.fireClient(network.RemoteEvents.GemFound, player, amount)
	end
	return newGems
end

-- Called once for every sheep shorn bare.
function GemHandler.rollSheepDrop(player: Player)
	if random:NextNumber() < GemData.SheepDropChance then
		GemHandler.give(player, GemData.SheepDropAmount)
	end
end

--// Lifecycle ---------------------------------------------------------------------

-- Mirrors Gems as a leaderstat, placed after Prestige.
local function onPlayerAdded(player: Player)
	if not PlayerDataHandler.waitForData(player) then
		return
	end

	local leaderstats = player:WaitForChild("leaderstats", LEADERSTATS_WAIT_SECONDS)
	if not leaderstats then
		return
	end
	leaderstats:WaitForChild("Prestige", LEADERSTATS_WAIT_SECONDS)

	local display = Instance.new("IntValue")
	display.Name = "Gems"
	display.Value = getGems(player)
	display.Parent = leaderstats

	player:GetAttributeChangedSignal("Gems"):Connect(function()
		display.Value = getGems(player)
	end)
end

function GemHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return GemHandler
