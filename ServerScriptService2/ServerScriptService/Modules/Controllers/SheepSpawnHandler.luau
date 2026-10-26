--!strict

--[[
	Fills each player's SheepArea with sheep up to their saved capacity, refills it over time
	and keeps the plot's Center.SheepCapacity label showing current/max.

	Location: ServerScriptService.Modules.Controllers.SheepSpawnHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// State
local activePlots: { [Player]: Folder } = {} -- the plot each running farm belongs to

local SheepSpawnHandler = {}

--// Capacity label ----------------------------------------------------------------------

local function getCapacityLabel(plot: Instance): TextLabel?
	local center = plot:FindFirstChild(FarmData.CenterName)
	local gui = center and center:FindFirstChild(FarmData.CapacityGuiName)
	local label = gui and gui:FindFirstChild("TextLabel")
	return if label and label:IsA("TextLabel") then label else nil
end

local function setCapacityText(plot: Instance, current: number, maximum: number)
	local label = getCapacityLabel(plot)
	if label then
		label.Text = `{current}/{maximum}`
	end
end

local function updateCapacityLabel(player: Player)
	local plot = activePlots[player]
	local maxSheep = PlayerDataHandler.get(player, "MaxSheep")
	if plot and type(maxSheep) == "number" then
		setCapacityText(plot, SheepHandler.getSheepCount(player), maxSheep)
	end
end

--// Spawning -----------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getMaxSheep(player: Player): number
	return math.min(getNumber(player, "MaxSheep"), FarmData.MaxSheepCap)
end

-- Seconds between refills, shortened by the player's Faster Respawn level.
local function getSpawnInterval(player: Player): number
	return UpgradeData.getSpawnInterval(FarmData.SpawnInterval, getNumber(player, "RespawnLevel"))
end

local function spawnOne(player: Player): boolean
	local plot = activePlots[player]
	local position = plot and SheepWanderHandler.getSpawnPosition(plot)
	if not position then
		return false
	end

	local sheep = SheepHandler.spawnSheep(
		player,
		position,
		getNumber(player, "Luck"),
		getNumber(player, "Rebirths"),
		getNumber(player, "Prestiges")
	)
	return sheep ~= nil
end

-- Spawns sheep until the farm holds `target` (capped at the player's capacity).
local function spawnUpTo(player: Player, target: number)
	local goal = math.min(target, getMaxSheep(player))
	while activePlots[player] and SheepHandler.getSheepCount(player) < goal do
		if not spawnOne(player) then
			return
		end
	end
end

local function runFarm(player: Player)
	local data = PlayerDataHandler.waitForData(player)
	local plot = PlotHandler.waitForPlot(player)
	if not data or not plot or not player.Parent then
		return
	end

	activePlots[player] = plot
	spawnUpTo(player, data.SheepCount or data.MaxSheep)
	updateCapacityLabel(player)

	while activePlots[player] do
		task.wait(getSpawnInterval(player))
		if activePlots[player] and SheepHandler.getSheepCount(player) < getMaxSheep(player) then
			spawnOne(player)
		end
	end
end

local function stopFarm(player: Player)
	local plot = activePlots[player]
	activePlots[player] = nil
	SheepHandler.clearSheep(player)
	if plot then
		setCapacityText(plot, 0, 0)
	end
end

--// Public API ------------------------------------------------------------------------

-- Clears the player's sheep and fills the farm back to full capacity (used after a Prestige).
function SheepSpawnHandler.resetFarm(player: Player)
	SheepHandler.clearSheep(player)
	spawnUpTo(player, getMaxSheep(player))
	updateCapacityLabel(player)
end

--// Lifecycle -----------------------------------------------------------------------

function SheepSpawnHandler.Start()
	SheepHandler.CountChanged:Connect(function(player: Player, count: number)
		if activePlots[player] then
			PlayerDataHandler.set(player, "SheepCount", count)
			updateCapacityLabel(player)
		end
	end)

	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "MaxSheep" then
			updateCapacityLabel(player)
		end
	end)

	players.PlayerRemoving:Connect(stopFarm)
	players.PlayerAdded:Connect(runFarm)
	for _, player in players:GetPlayers() do
		task.spawn(runFarm, player)
	end
end

return SheepSpawnHandler
