--!strict

--[[
	Wool upgrades: +1 sheep capacity, More Wool, Faster Speed, Shear Damage and Faster Respawn levels. Bought from the UpgradeShop UI (opened at the
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
local PlotHandler = require(script.Parent.PlotHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local PURCHASE_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local STATE_KEYS = { MaxSheep = true, MoreWoolLevel = true, SpeedLevel = true, DamageLevel = true, RespawnLevel = true, ShearId = true } -- data the cards show

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
	elseif id == "FasterRespawn" then
		return getNumber(player, "RespawnLevel")
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

-- Sets the character's walk speed from the player's Faster Speed level, times any active ability's boost.
function UpgradeHandler.applyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local boost = player:GetAttribute("AbilitySpeedMultiplier")
		humanoid.WalkSpeed = UpgradeData.getWalkSpeed(getNumber(player, "SpeedLevel")) * (if type(boost) == "number" then boost else 1)
	end
end

local applyWalkSpeed = UpgradeHandler.applyWalkSpeed

local function applyUpgrade(player: Player, id: string, level: number)
	if id == "Capacity" then
		PlayerDataHandler.increment(player, "MaxSheep", 1)
	elseif id == "MoreWool" then
		PlayerDataHandler.set(player, "MoreWoolLevel", level + 1)
	elseif id == "FasterSpeed" then
		PlayerDataHandler.set(player, "SpeedLevel", level + 1)
	elseif id == "ShearDamage" then
		PlayerDataHandler.set(player, "DamageLevel", level + 1)
	elseif id == "FasterRespawn" then
		PlayerDataHandler.set(player, "RespawnLevel", level + 1)
	end
end

--// Card state ----------------------------------------------------------------------------

local function formatSeconds(value: number): string
	return string.format("%.1fs", value)
end

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
	elseif id == "FasterRespawn" then
		local current = getNumber(player, "RespawnLevel")
		return formatSeconds(UpgradeData.getSpawnInterval(FarmData.SpawnInterval, current)),
			formatSeconds(UpgradeData.getSpawnInterval(FarmData.SpawnInterval, current + 1))
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

--// Seller ------------------------------------------------------------------------

local defaultLooks: { [Humanoid]: HumanoidDescription } = {} -- each seller's look from the place, put back when its plot frees up

local function getSeller(plot: Instance): Humanoid?
	local shack = plot:FindFirstChild(UpgradeData.ShackName)
	local seller = shack and shack:FindFirstChild(UpgradeData.SellerName)
	return seller and seller:FindFirstChildOfClass("Humanoid")
end

local function applyLook(seller: Humanoid, description: HumanoidDescription)
	local success, err = pcall(seller.ApplyDescription, seller, description)
	if not success then
		warn(`UpgradeHandler: couldn't dress the seller: {err}`)
	end
end

-- Dresses the plot's seller as its owner.
local function dressSeller(player: Player, plot: Instance)
	local seller = getSeller(plot)
	if not seller then
		return
	end

	local success, description = pcall(players.GetHumanoidDescriptionFromUserId, players, player.UserId)
	if not success then
		warn(`UpgradeHandler: no avatar for {player.Name}: {description}`)
		return
	end
	if plot:GetAttribute("Owner") == player.UserId then -- they may have left while it loaded
		applyLook(seller, description)
	end
end

local function undressSeller(_player: Player, plot: Instance)
	local seller = getSeller(plot)
	local default = seller and defaultLooks[seller]
	if seller and default then
		applyLook(seller, default)
	end
end

--// Lifecycle ---------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 5)
		applyWalkSpeed(player)
	end)
	applyWalkSpeed(player)
end

-- Tags each plot's shack prompt so the client knows it opens the UpgradeShop (plots are built from TemplatePlot by now),
-- and dresses each shack's seller as the plot's owner.
function UpgradeHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		local shack = plot:FindFirstChild(UpgradeData.ShackName)
		local prompt = shack and shack:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			collectionService:AddTag(prompt, UpgradeData.ShopPromptTag)
		elseif plot:IsA("Folder") then
			warn(`UpgradeHandler: {plot.Name} has no ProximityPrompt under {UpgradeData.ShackName}.`)
		end

		local seller = getSeller(plot)
		if seller then
			defaultLooks[seller] = seller:GetAppliedDescription()
		end
	end

	PlotHandler.PlotAssigned:Connect(dressSeller)
	PlotHandler.PlotReleased:Connect(undressSeller)

	-- Plots handed out before this ran.
	for _, player in players:GetPlayers() do
		local plot = PlotHandler.getPlayerPlot(player)
		if plot then
			task.spawn(dressSeller, player, plot)
		end
	end
end

function UpgradeHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.PurchaseUpgrade, function(player: Player, id: any)
		local success, reason = UpgradeHandler.purchase(player, id)
		local level = if success then getBoughtLevel(player, id) else nil
		network.fireClient(network.RemoteEvents.UpgradeResult, player, id, success, reason, level)
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
