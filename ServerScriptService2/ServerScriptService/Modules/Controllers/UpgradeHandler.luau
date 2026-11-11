--!strict

--[[
	Wool upgrades: More Wool, capacity, Shear Damage, Faster Respawn and Spawn Luck (capped per rebirth). Bought from the
	UpgradeShop UI (opened at the plot's UpgradePlotShack or the HUD button) through the PurchaseUpgrade remote; each card's state is pushed with UpgradeState.

	Location: ServerScriptService.Modules.Controllers.UpgradeHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SpawnOdds = require(replicatedStorage.Shared.Utils.SpawnOdds)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local SheepPools = require(script.Parent.Parent.Constants.SheepPools)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local PURCHASE_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local STATE_KEYS = { MaxSheep = true, MoreWoolLevel = true, DamageLevel = true, RespawnLevel = true, ShearId = true,
	SpawnLuckLevel = true, Rebirths = true, Prestiges = true, SheepIndex = true } -- data the cards show
local LEVEL_KEYS = { MoreWool = "MoreWoolLevel", ShearDamage = "DamageLevel", FasterRespawn = "RespawnLevel",
	SpawnLuck = "SpawnLuckLevel" } -- data key of each upgrade's level (Capacity counts MaxSheep instead)
local MAX_LEVELS_PER_PURCHASE = 100 -- caps MAX on upgrades with no limit; costs grow x1.4+ a level, so 100 is past any wool total

-- One more level of an upgrade: its price and the value once it's bought.
export type Step = {
	cost: number,
	after: string,
}

-- One card in the UpgradeShop. `after` and `cost` are nil (and `steps` empty) once the upgrade is maxed.
export type CardState = {
	id: string,
	title: string,
	icon: string,
	level: number, -- levels bought so far
	maxLevel: number?, -- levels there are to buy; nil = no limit
	before: string,
	after: string?,
	cost: number?,
	steps: { Step }, -- the next levels in order, so the client can preview MAX against its wool as it changes
	note: string?, -- shown instead of "(MAX)" when the cap isn't final (Spawn Luck's per-rebirth cap)
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
	end
	local key = LEVEL_KEYS[id]
	return if key then getNumber(player, key) else 0
end

-- The most levels the player may own right now: Spawn Luck is capped by their rebirths as well as its maxLevel.
local function getLevelCap(player: Player, id: string): number
	local info = UpgradeData.Upgrades[id]
	local cap = info and info.maxLevel or math.huge
	if id == "SpawnLuck" then
		cap = math.min(cap, SpawnOdds.getSpawnLuckCap(getNumber(player, "Rebirths")))
	end
	return cap
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
	return if level < getLevelCap(player, id) then level else nil
end

-- Levels still to buy, at most MAX_LEVELS_PER_PURCHASE (Capacity stops at FarmData.MaxSheepCap, the rest at their cap).
local function getLevelsLeft(player: Player, id: string): number
	local left = if id == "Capacity"
		then FarmData.MaxSheepCap - getNumber(player, "MaxSheep")
		else getLevelCap(player, id) - getBoughtLevel(player, id)
	return math.clamp(left, 0, MAX_LEVELS_PER_PURCHASE)
end

--// Spawn odds ------------------------------------------------------------------------------

-- The player's roll context without temporary boosts (weather, Robux), at this Spawn Luck level.
local function getRollContext(player: Player, spawnLuck: number): SheepData.RollContext
	local rebirths, prestiges = getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	return {
		luck = getNumber(player, "Luck"),
		rebirths = rebirths,
		prestiges = prestiges,
		spawnLuck = spawnLuck,
		pool = SheepPools.getPool(rebirths, prestiges),
		scales = SheepPools.getScales(rebirths),
	}
end

-- The sheep Spawn Luck's card quotes odds for: the rebirth sheep while it's unfound, else the rarest (non-Halloween) one in the pool.
local function getLuckTarget(player: Player): string?
	local required, found = RebirthHandler.getRequirement(player)
	if required and not found then
		return required
	end
	local context = getRollContext(player, getNumber(player, "SpawnLuckLevel"))
	local rarest, rarestOdds = nil, 0
	for key in context.pool or {} do
		local odds = if SheepData.Sheep[key].halloween then nil else SheepData.getTypeOddsWith(key, context)
		if odds and odds > rarestOdds then
			rarest, rarestOdds = key, odds
		end
	end
	return rarest
end

-- Spawn Luck's per-rebirth cap explained once it's reached (nil when the cap is the final one).
local function getCapNote(player: Player, id: string): string?
	if id ~= "SpawnLuck" or getLevel(player, id) or getBoughtLevel(player, id) >= SpawnOdds.SPAWN_LUCK_MAX_LEVEL then
		return nil
	end
	local rebirths = getNumber(player, "Rebirths")
	local required, found = RebirthHandler.getRequirement(player)
	local info = if required and not found then SheepData.Sheep[required] else nil
	return if info
		then `Max for Rebirth {rebirths}. Find the {info.name} to rebirth.`
		else `Max for Rebirth {rebirths}. Rebirth to raise it.`
end

-- Base damage of the player's equipped shear.
local function getShearBaseDamage(player: Player): number
	local shear = ShearData.get(PlayerDataHandler.get(player, "ShearId")) or ShearData.Shears[1]
	return shear.damage
end

-- Sets the character's walk speed: the base speed times any active ability's boost.
function UpgradeHandler.applyWalkSpeed(player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local boost = player:GetAttribute("AbilitySpeedMultiplier")
		humanoid.WalkSpeed = UpgradeData.BaseWalkSpeed * (if type(boost) == "number" then boost else 1)
	end
end

local applyWalkSpeed = UpgradeHandler.applyWalkSpeed

local function applyUpgrade(player: Player, id: string, level: number, count: number)
	if id == "Capacity" then
		PlayerDataHandler.increment(player, "MaxSheep", count)
	elseif LEVEL_KEYS[id] then
		PlayerDataHandler.set(player, LEVEL_KEYS[id], level + count)
	end
end

--// Card state ----------------------------------------------------------------------------

-- 1.35 -> "1.35s", 0.6 -> "0.6s"
local function formatSeconds(value: number): string
	return (string.format("%.2f", value):gsub("%.?0+$", "")) .. "s"
end

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- The value the upgrade changes, `extra` levels past what the player has now (0 = their current value).
local function getValue(player: Player, id: string, extra: number): string
	if id == "Capacity" then
		return tostring(getNumber(player, "MaxSheep") + extra)
	elseif id == "MoreWool" then
		return formatMultiplier(UpgradeData.getMoreWoolMultiplier(getNumber(player, "MoreWoolLevel") + extra))
	elseif id == "ShearDamage" then
		return tostring(UpgradeData.getShearDamage(getShearBaseDamage(player), getNumber(player, "DamageLevel") + extra))
	elseif id == "FasterRespawn" then
		return formatSeconds(UpgradeData.getSpawnInterval(FarmData.SpawnInterval, getNumber(player, "RespawnLevel") + extra))
	elseif id == "SpawnLuck" then
		-- "Golden Sheep: 1 in 400" now, then "1 in 310" for each level after (the same odds the spawn roll uses).
		local target = getLuckTarget(player)
		local odds = if target then SheepData.getTypeOddsWith(target, getRollContext(player, getNumber(player, "SpawnLuckLevel") + extra)) else nil
		local oddsText = if odds then SpawnOdds.formatOdds(odds) else SpawnOdds.formatMultiplier(SpawnOdds.getSpawnLuckMultiplier(getNumber(player, "SpawnLuckLevel") + extra))
		return if extra == 0 and target then `{SheepData.Sheep[target].name}: {oddsText}` else oddsText
	end
	return ""
end

-- The price and resulting value of each level still to buy, in order, up to MAX_LEVELS_PER_PURCHASE.
local function getSteps(player: Player, id: string, level: number?): { Step }
	local steps: { Step } = {}
	if not level then
		return steps
	end
	for extra = 1, getLevelsLeft(player, id) do
		local cost = UpgradeData.getCost(id, level + extra - 1)
		if not cost then
			break
		end
		table.insert(steps, { cost = cost, after = getValue(player, id, extra) })
	end
	return steps
end

-- How many of the next levels `wool` covers (at most `limit`) and what they cost together.
local function getAffordable(steps: { Step }, wool: number, limit: number): (number, number)
	local count, total = 0, 0
	for index = 1, math.min(#steps, limit) do
		local nextTotal = total + steps[index].cost
		if nextTotal > wool then
			break
		end
		count, total = index, nextTotal
	end
	return count, total
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

		local steps = getSteps(player, id, getLevel(player, id))
		local nextStep = steps[1]

		table.insert(state, {
			id = id,
			title = info.displayName,
			icon = info.icon,
			level = getBoughtLevel(player, id),
			maxLevel = if id == "Capacity" then FarmData.MaxSheepCap - FarmData.StartingMaxSheep
				elseif id == "SpawnLuck" then getLevelCap(player, id)
				else info.maxLevel,
			before = getValue(player, id, 0),
			after = if nextStep then nextStep.after else nil,
			cost = if nextStep then nextStep.cost else nil,
			steps = steps,
			note = getCapNote(player, id),
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
	Buys one level of an upgrade with wool, or with `amount` "max" as many as the player can afford, paid in one go.
	Returns true and the levels bought, or false plus a reason ("NotLoaded", "Unknown", "Maxed", "Capped" (for this rebirth) or "NoWool").
	Works from anywhere: the HUD button opens the shop too.
]]
function UpgradeHandler.purchase(player: Player, id: any, amount: any): (boolean, string?, number?)
	if not PlayerDataHandler.getData(player) then
		return false, "NotLoaded", nil
	end
	if type(id) ~= "string" or not UpgradeData.Upgrades[id] then
		return false, "Unknown", nil
	end

	local level = getLevel(player, id)
	local steps = getSteps(player, id, level)
	if not level or #steps == 0 then
		return false, if getCapNote(player, id) then "Capped" else "Maxed", nil
	end

	-- Anything but "max" (the client's to send) buys a single level.
	local count, cost = getAffordable(steps, getNumber(player, "Wool"), if amount == "max" then #steps else 1)
	if count == 0 or not PlayerDataHandler.spend(player, "Wool", cost) then
		return false, "NoWool", nil
	end

	applyUpgrade(player, id, level, count)
	Analytics.upgraded(player, id, level + count, count, cost)
	return true, nil, count
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

	network.connectEvent(network.RemoteEvents.PurchaseUpgrade, function(player: Player, id: any, amount: any)
		local success, reason, count = UpgradeHandler.purchase(player, id, amount)
		local level = if success then getBoughtLevel(player, id) else nil
		network.fireClient(network.RemoteEvents.UpgradeResult, player, id, success, reason, level, count)
	end, { network.Middleware.RateLimit(PURCHASE_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestUpgradeState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(function(player: Player)
		applyWalkSpeed(player)
		pushState(player)
	end)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
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
