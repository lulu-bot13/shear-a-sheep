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
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

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

-- Also mirrors the numbers onto PenCount/PenMax attributes for the Main HUD's SheepPenCount label.
local function updateCapacityLabel(player: Player)
	local plot = activePlots[player]
	local maxSheep = PlayerDataHandler.get(player, "MaxSheep")
	if plot and type(maxSheep) == "number" then
		local count = SheepHandler.getSheepCount(player)
		setCapacityText(plot, count, maxSheep)
		player:SetAttribute("PenCount", count)
		player:SetAttribute("PenMax", maxSheep)
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

-- Seconds between refills, shortened by the player's Faster Respawn level, the weather and their podium sheep.
local function getSpawnInterval(player: Player): number
	local interval = UpgradeData.getSpawnInterval(FarmData.SpawnInterval, getNumber(player, "RespawnLevel"))
	return interval * WeatherHandler.getRespawnMultiplier() * PodiumBonusHandler.getRespawnMultiplier(player)
end

-- Pooled models keep their attributes, so Charged is always rewritten (true or cleared).
local function applyCharge(sheep: Model)
	local charged = WeatherHandler.rollCharged()
	sheep:SetAttribute(WeatherData.ChargedAttribute, if charged then true else nil)

	local woolAmount = sheep:GetAttribute("WoolAmount")
	if charged and type(woolAmount) == "number" then
		sheep:SetAttribute("WoolAmount", woolAmount * WeatherData.ChargedWoolMultiplier)
	end
end

local function spawnSheep(player: Player, forced: SheepHandler.ForcedSpawn?): Model?
	local plot = activePlots[player]
	local position = plot and SheepWanderHandler.getSpawnPosition(plot)
	if not position then
		return nil
	end

	local sheep = SheepHandler.spawnSheep(
		player,
		position,
		getNumber(player, "Luck"),
		getNumber(player, "Rebirths"),
		getNumber(player, "Prestiges"),
		WeatherHandler.getLuckMultiplier() * PodiumBonusHandler.getLuckMultiplier(player),
		WeatherHandler.isHalloween(),
		forced
	)
	if sheep and not forced then
		applyCharge(sheep)
	end
	return sheep
end

local function spawnOne(player: Player): boolean
	return spawnSheep(player) ~= nil
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

-- Drops one extra sheep with the given type / size on the player's farm, even past capacity; nil until their farm is running.
function SheepSpawnHandler.spawnForced(player: Player, forced: SheepHandler.ForcedSpawn): Model?
	return spawnSheep(player, forced)
end

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
