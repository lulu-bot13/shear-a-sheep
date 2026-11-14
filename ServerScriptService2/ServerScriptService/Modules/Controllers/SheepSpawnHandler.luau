--!strict

--[[
	Fills each player's SheepArea up to their saved capacity on join, then drops refills into it with a poof (faster for owners of the
	RobuxConveyor pass), rolled from their SheepPools pool with the rebirth sheep's pity; clears the pen with a poof on rebirth.

	Location: ServerScriptService.Modules.Controllers.SheepSpawnHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local SheepPools = require(script.Parent.Parent.Constants.SheepPools)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)
local GamePassService = require(script.Parent.GamePassService)
local MonetizationHandler = require(script.Parent.MonetizationHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Configs
local SHEEPS_FOLDER_NAME = "Sheeps" -- SheepHandler's folder in each plot
local LUCK_FACTOR_ATTRIBUTE = "LuckFactor" -- the effective spawn luck factor, for the HUD's "Luck x1.9"
local LUCK_FACTOR_KEYS = { Luck = true, Rebirths = true, Prestiges = true, SpawnLuckLevel = true }
local PREMIUM_LUCK_MULTIPLIER = 1.1 -- Roblox Premium members' +10% luck (shown by BonusesClient's HUD badge)
local REFILL_AFTER_POOF_SECONDS = 0.5 -- the rebirth poof plays on an empty pen before it refills
local FAST_REFILL_PASS = "RobuxConveyor" -- the old 2nd-conveyor pass; its owners keep their extra sheep as faster refills
local FAST_REFILL_MULTIPLIER = MonetizationData.Items.RobuxConveyor.multiplier or 3
local REVEAL_MIN_SHEARED = 3 -- the tutorial's shearing steps; the rebirth sheep's cutscene waits until they're done

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

--// Roll context --------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getMaxSheep(player: Player): number
	return math.min(getNumber(player, "MaxSheep"), FarmData.MaxSheepCap)
end

-- Seconds between refills, shortened by the player's Faster Respawn level, the weather, their podium sheep and the fast refill pass.
local function getSpawnInterval(player: Player): number
	local interval = UpgradeData.getSpawnInterval(FarmData.SpawnInterval, getNumber(player, "RespawnLevel"))
	local passMultiplier = if GamePassService.ownsPass(player, FAST_REFILL_PASS) then 1 / FAST_REFILL_MULTIPLIER else 1
	return interval * WeatherHandler.getRespawnMultiplier() * PodiumBonusHandler.getRespawnMultiplier(player) * passMultiplier
end

local function getPremiumLuckMultiplier(player: Player): number
	return if player.MembershipType == Enum.MembershipType.Premium then PREMIUM_LUCK_MULTIPLIER else 1
end

local function getLuckBoost(player: Player): number
	return WeatherHandler.getLuckMultiplier() * PodiumBonusHandler.getLuckMultiplier(player) * MonetizationHandler.getLuckMultiplier(player)
		* getPremiumLuckMultiplier(player)
end

-- Everything the player's next roll depends on: Luck, rebirths, Prestiges, boosts, Spawn Luck and their pool.
function SheepSpawnHandler.getRollContext(player: Player): SheepData.RollContext
	local rebirths, prestiges = getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	return {
		luck = getNumber(player, "Luck"),
		rebirths = rebirths,
		prestiges = prestiges,
		boost = getLuckBoost(player),
		halloween = WeatherHandler.isHalloween(),
		spawnLuck = getNumber(player, "SpawnLuckLevel"),
		pool = SheepPools.getPool(rebirths, prestiges),
		scales = SheepPools.getScales(rebirths),
	}
end

-- Mirrors the effective luck factor (the roll's own formula, boosts included) to the LuckFactor attribute, rounded to 0.01.
local function updateLuckFactor(player: Player)
	if not PlayerDataHandler.getData(player) then
		return
	end
	local factor = SheepData.getLuckFactor(getNumber(player, "Luck"), getNumber(player, "Rebirths"), getNumber(player, "Prestiges"),
		getLuckBoost(player), getNumber(player, "SpawnLuckLevel"))
	local rounded = math.floor(factor * 100 + 0.5) / 100
	if player:GetAttribute(LUCK_FACTOR_ATTRIBUTE) ~= rounded then
		player:SetAttribute(LUCK_FACTOR_ATTRIBUTE, rounded)
	end
end

--// Spawning -----------------------------------------------------------------------------

-- Pooled models keep their attributes, so Charged is always rewritten (true or cleared).
local function applyCharge(sheep: Model)
	local charged = WeatherHandler.rollCharged()
	sheep:SetAttribute(WeatherData.ChargedAttribute, if charged then true else nil)

	local woolAmount = sheep:GetAttribute("WoolAmount")
	if charged and type(woolAmount) == "number" then
		sheep:SetAttribute("WoolAmount", woolAmount * WeatherData.ChargedWoolMultiplier)
	end
end

-- A normal roll counts towards the rebirth sheep's pity; when it's due, that roll is forced to the rebirth sheep (variant still rolled).
local function getPityForce(player: Player): SheepHandler.ForcedSpawn?
	local forcedType = RebirthHandler.rollPity(player)
	return if forcedType then { sheepType = SheepData.rollVariant(forcedType) } else nil
end

--[[
	The rebirth sheep the player still needs just landed (rolled or forced): its pity starts over and, when `reveal` is set, the owner's
	RebirthSheepClient flies the camera to it. Not before REVEAL_MIN_SHEARED, so the tutorial's first shears aren't interrupted.
]]
local function onRebirthSheepCheck(player: Player, sheep: Model, reveal: boolean)
	local adultType = sheep:GetAttribute("AdultType")
	local required, found = RebirthHandler.getRequirement(player)
	if type(adultType) ~= "string" or adultType ~= required or found then
		return
	end
	RebirthHandler.noteSpawn(player, adultType)
	if reveal and getNumber(player, "SheepShearedCount") >= REVEAL_MIN_SHEARED then
		network.fireClient(network.RemoteEvents.RebirthSheepSpawned, player, sheep:GetAttribute("id"), sheep:GetPivot().Position)
	end
end

--[[
	Straight into the pen (join fill, resets and forced spawns like the Reaper raid); Halloween spawns rise from a pit.
	`forced` spawns skip the pity and charge. `reveal` plays the rebirth sheep's cutscene if that's what landed (not for the join / rebirth fills).
]]
local function spawnSheep(player: Player, forced: SheepHandler.ForcedSpawn?, reveal: boolean): Model?
	local plot = activePlots[player]
	local position = plot and SheepWanderHandler.getSpawnPosition(plot)
	if not position then
		return nil
	end

	local context = SheepSpawnHandler.getRollContext(player)
	local roll = forced or getPityForce(player)
	local sheep = SheepHandler.spawnSheep(player, position, context, roll)
	if sheep then
		if not forced then
			applyCharge(sheep)
		end
		onRebirthSheepCheck(player, sheep, reveal)
	end
	return sheep
end

local function spawnOne(player: Player): boolean
	return spawnSheep(player, nil, false) ~= nil
end

-- A refill pops into the pen with a poof so the player sees it arrive.
local function spawnRefill(player: Player)
	local sheep = spawnSheep(player, nil, true)
	if sheep then
		network.fireAllClients(network.RemoteEvents.SheepPoof, { sheep:GetPivot().Position })
	end
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
	updateLuckFactor(player)

	while activePlots[player] do
		local interval = getSpawnInterval(player)
		task.wait(interval)
		if not activePlots[player] then
			break
		end
		updateLuckFactor(player) -- weather, podium and Robux boosts change without a data change
		if SheepHandler.getSheepCount(player) < getMaxSheep(player) then
			spawnRefill(player)
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

-- Rebirth: every sheep in the pen goes up in a poof (PoofAttachment, played by RebirthClient), then the pen refills from the new pool.
local function onRebirthed(player: Player)
	local plot = activePlots[player]
	if not plot then
		return
	end

	local positions: { Vector3 } = {}
	local folder = plot:FindFirstChild(SHEEPS_FOLDER_NAME)
	for _, sheep in (if folder then folder:GetChildren() else {}) do
		if sheep:IsA("Model") and sheep:GetAttribute("OwnerId") == player.UserId then
			table.insert(positions, sheep:GetPivot().Position)
		end
	end

	SheepHandler.clearSheep(player)
	updateCapacityLabel(player)
	if #positions > 0 then
		network.fireAllClients(network.RemoteEvents.SheepPoof, positions)
	end

	task.delay(REFILL_AFTER_POOF_SECONDS, function()
		if activePlots[player] == plot then
			spawnUpTo(player, getMaxSheep(player))
			updateCapacityLabel(player)
		end
	end)
end

--// Public API ------------------------------------------------------------------------

-- Drops one extra sheep with the given type / size on the player's farm, even past capacity; nil until their farm is running.
function SheepSpawnHandler.spawnForced(player: Player, forced: SheepHandler.ForcedSpawn): Model?
	return spawnSheep(player, forced, true)
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
		if LUCK_FACTOR_KEYS[key] then
			updateLuckFactor(player)
		end
	end)

	RebirthHandler.Rebirthed:Connect(onRebirthed)

	players.PlayerMembershipChanged:Connect(updateLuckFactor)
	GamePassService.onChanged(function(player: Player)
		updateLuckFactor(player)
	end)
	players.PlayerRemoving:Connect(stopFarm)
	players.PlayerAdded:Connect(runFarm)
	for _, player in players:GetPlayers() do
		task.spawn(runFarm, player)
	end
end

return SheepSpawnHandler
