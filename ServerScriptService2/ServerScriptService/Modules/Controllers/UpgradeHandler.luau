--!strict

--[[
	Wool upgrades: +1 sheep capacity, More Wool, Faster Speed and Shear Damage levels. Bought from the UpgradeShop UI (opened at the
	plot's UpgradePlotShack or the HUD button) through the PurchaseUpgrade remote; each card's state is pushed with UpgradeState.

	Location: ServerScriptService.Modules.Controllers.UpgradeHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local PURCHASE_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local STATE_KEYS = { MaxSheep = true, MoreWoolLevel = true, SpeedLevel = true, DamageLevel = true, ShearId = true } -- data the cards show

-- One card in the UpgradeShop. `after` and `cost` are nil once the upgrade is maxed.
export type CardState = {
	id: string,
	title: string,
	icon: string,
	level: number, -- levels bought so far
	before: string,
	after: string?,
	cost: number?,
}

local UpgradeHandler = {}

--// Levels ------------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

-- How many times the upgrade has been bought, maxed or not.
local function getBoughtLevel(player: Player, id: string): number
	if id == "Capacity" then
		return getNumber(player, "MaxSheep") - FarmData.StartingMaxSheep
	elseif id == "MoreWool" then
		return getNumber(player, "MoreWoolLevel")
	elseif id == "FasterSpeed" then
		return getNumber(player, "SpeedLevel")
	elseif id == "ShearDamage" then
		return getNumber(player, "DamageLevel")
	end
	return 0
end

-- How many times the upgrade has been bought, or nil if it can't be bought any more.
local function getLevel(player: Player, id: string): number?
	local info = UpgradeData.Upgrades[id]
	if not info then
		return nil
	end

	local level = getBoughtLevel(player, id)
	if id == "Capacity" then
		return if getNumber(player, "MaxSheep") < FarmData.MaxSheepCap then level else nil
	end
	return if level < (info.maxLevel or math.huge) then level else nil
end

-- Base damage of the player's equipped shear.
local function getShearBaseDamage(player: Player): number
	local shear = ShearData.get(PlayerDataHandler.get(player, "ShearId")) or ShearData.Shears[1]
	return shear.damage
end

-- Sets the character's walk speed from the player's Faster Speed level.
local function applyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = UpgradeData.getWalkSpeed(getNumber(player, "SpeedLevel"))
	end
end

local function applyUpgrade(player: Player, id: string, level: number)
	if id == "Capacity" then
		PlayerDataHandler.increment(player, "MaxSheep", 1)
	elseif id == "MoreWool" then
		PlayerDataHandler.set(player, "MoreWoolLevel", level + 1)
	elseif id == "FasterSpeed" then
		PlayerDataHandler.set(player, "SpeedLevel", level + 1)
	elseif id == "ShearDamage" then
		PlayerDataHandler.set(player, "DamageLevel", level + 1)
	end
end

--// Card state ----------------------------------------------------------------------------

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- The value the upgrade changes, now and after one more level (nil when maxed).
local function getValues(player: Player, id: string, level: number?): (string, string?)
	if id == "Capacity" then
		local maxSheep = getNumber(player, "MaxSheep")
		return tostring(maxSheep), if level then tostring(maxSheep + 1) else nil
	elseif id == "MoreWool" then
		local current = getNumber(player, "MoreWoolLevel")
		return formatMultiplier(UpgradeData.getMoreWoolMultiplier(current)),
			formatMultiplier(UpgradeData.getMoreWoolMultiplier(current + 1))
	elseif id == "ShearDamage" then
		local current = getNumber(player, "DamageLevel")
		local baseDamage = getShearBaseDamage(player)
		return tostring(UpgradeData.getShearDamage(baseDamage, current)),
			tostring(UpgradeData.getShearDamage(baseDamage, current + 1))
	else
		local current = getNumber(player, "SpeedLevel")
		return tostring(UpgradeData.getWalkSpeed(current)), tostring(UpgradeData.getWalkSpeed(current + 1))
	end
end

-- Every card's title, before -> after values and next price, in shop order.
function UpgradeHandler.getState(player: Player): { CardState }
	local state: { CardState } = {}
	for _, id in UpgradeData.Order do
		local info = UpgradeData.Upgrades[id]
		if not info then
			warn(`UpgradeHandler: "{id}" is in UpgradeData.Order but not in UpgradeData.Upgrades.`)
			continue
		end

		local level = getLevel(player, id)
		local before, after = getValues(player, id, level)

		table.insert(state, {
			id = id,
			title = info.displayName,
			icon = info.icon,
			level = getBoughtLevel(player, id),
			before = before,
			after = if level then after else nil,
			cost = if level then UpgradeData.getCost(id, level) else nil,
		})
	end
	return state
end

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.UpgradeState, player, UpgradeHandler.getState(player))
	end
end

--// Purchasing ------------------------------------------------------------------------------

--[[
	Buys one level of an upgrade with wool. Returns true on success, or false plus a reason
	("NotLoaded", "Unknown", "Maxed" or "NoWool"). Works from anywhere: the HUD button opens the shop too.
]]
function UpgradeHandler.purchase(player: Player, id: any): (boolean, string?)
	if not PlayerDataHandler.getData(player) then
		return false, "NotLoaded"
	end
	if type(id) ~= "string" or not UpgradeData.Upgrades[id] then
		return false, "Unknown"
	end

	local level = getLevel(player, id)
	local cost = level and UpgradeData.getCost(id, level)
	if not level or not cost then
		return false, "Maxed"
	end
	if not PlayerDataHandler.spend(player, "Wool", cost) then
		return false, "NoWool"
	end

	applyUpgrade(player, id, level)
	return true, nil
end

--// Lifecycle ---------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 5)
		applyWalkSpeed(player)
	end)
	applyWalkSpeed(player)
end

-- Tags each plot's shack prompt so the client knows it opens the UpgradeShop (plots are built from TemplatePlot by now).
function UpgradeHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		local shack = plot:FindFirstChild(UpgradeData.ShackName)
		local prompt = shack and shack:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			collectionService:AddTag(prompt, UpgradeData.ShopPromptTag)
		elseif plot:IsA("Folder") then
			warn(`UpgradeHandler: {plot.Name} has no ProximityPrompt under {UpgradeData.ShackName}.`)
		end
	end
end

function UpgradeHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.PurchaseUpgrade, function(player: Player, id: any)
		local success, reason = UpgradeHandler.purchase(player, id)
		network.fireClient(network.RemoteEvents.UpgradeResult, player, id, success, reason)
	end, { network.Middleware.RateLimit(PURCHASE_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestUpgradeState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(function(player: Player)
		applyWalkSpeed(player)
		pushState(player)
	end)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "SpeedLevel" then
			applyWalkSpeed(player)
		end
		if STATE_KEYS[key] then
			pushState(player)
		end
	end)

	players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
		task.spawn(pushState, player)
	end
end

return UpgradeHandler
