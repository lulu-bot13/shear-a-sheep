--!strict

--[[
	The Ability Shack: rolls a weighted ability for RollCost Gems at workspace.Base.CenterPlaza.AbilityShack.Podium
	(with pity and duplicate refunds) and equips owned ones; the client only requests and displays.
	Location: ServerScriptService.Modules.Controllers.AbilityShackHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Configs
local SHACK_NAME = "AbilityShack"
local PODIUM_NAME = "Podium"
local MISSING_WARN_SECONDS = 15
local ROLL_RANGE = 30 -- studs from the podium the server accepts a roll
local SPECTATOR_RANGE = 90 -- other players this close see a light version of the roll
local BATCH_ROLLS = 5 -- the only count besides 1 a roll request may use
local ROLL_COOLDOWN = 0.4
local EQUIP_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs

export type AbilityEntry = {
	id: string,
	name: string,
	description: string,
	rarity: string,
	color: Color3,
	cooldown: number,
	duration: number,
	chance: number, -- 0-1 chance per roll right now; 0 = can't be rolled
	halloween: boolean, -- only rollable during Halloween
	owned: boolean,
}

export type State = {
	equipped: string,
	abilities: { AbilityEntry }, -- AbilityData.Order
	cost: number,
	pity: number, -- rolls in a row without a pity rarity
	pityRolls: number,
	pityLabel: string,
}

export type RollEntry = {
	id: string,
	isNew: boolean,
	refund: number, -- Gems given back for a duplicate
	guaranteed: boolean, -- the pity roll
}

export type RollResult = {
	success: boolean,
	reason: string?, -- "TooFar", "Closed" or "NoGems" when not successful
	results: { RollEntry }?, -- one per roll, in order
	roller: Player?, -- set only on the light copy sent to players nearby
}

--// State
local random = Random.new()
local podiumPart: BasePart? = nil

local AbilityShackHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getOwned(player: Player): { string }
	local owned = PlayerDataHandler.get(player, "OwnedAbilities")
	return if type(owned) == "table" then owned else { AbilityData.DefaultAbilityId }
end

local function isOwned(player: Player, id: string): boolean
	return id == AbilityData.DefaultAbilityId or table.find(getOwned(player), id) ~= nil
end

local function isNearPodium(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local podium = podiumPart
	if not rootPart or not humanoid or humanoid.Health <= 0 or not podium or not podium:IsDescendantOf(workspace) then
		return false
	end
	return (rootPart.Position - podium.Position).Magnitude <= ROLL_RANGE
end

-- The entry with the lowest chance (at Halloween odds, so a Halloween ability ranks by its own rarity), which spectators see.
local function getRarestEntry(entries: { RollEntry }?): RollEntry?
	local best: RollEntry? = nil
	local bestChance = math.huge
	for _, entry in (entries or {}) :: { RollEntry } do
		local chance = AbilityData.getChance(entry.id, true)
		if not best or chance < bestChance then
			best = entry
			bestChance = chance
		end
	end
	return best
end

--// Public API ------------------------------------------------------------------------

function AbilityShackHandler.getState(player: Player): State
	local abilities: { AbilityEntry } = {}
	local halloween = WeatherHandler.isHalloween()
	for _, id in AbilityData.Order do
		local info = AbilityData.Abilities[id]
		table.insert(abilities, {
			id = id,
			name = info.name,
			description = info.description,
			rarity = info.rarity,
			color = SheepData.RarityColors[info.rarity] or SheepData.RarityColors.Common,
			cooldown = info.cooldown,
			duration = info.duration,
			chance = AbilityData.getChance(id, halloween),
			halloween = info.halloween == true,
			owned = isOwned(player, id),
		})
	end

	local equipped = PlayerDataHandler.get(player, "AbilityEquipped")
	return {
		equipped = if type(equipped) == "string" then equipped else AbilityData.DefaultAbilityId,
		abilities = abilities,
		cost = AbilityData.RollCost,
		pity = getNumber(player, "AbilityPity"),
		pityRolls = AbilityData.PityRolls,
		pityLabel = AbilityData.PityLabel,
	}
end

-- Spends RollCost per roll (count is 1 or 5) and rolls abilities: a new one is added to OwnedAbilities, a duplicate refunds part of the cost.
function AbilityShackHandler.roll(player: Player, count: any?): RollResult
	local rolls = if count == BATCH_ROLLS then BATCH_ROLLS else 1
	if not PlayerDataHandler.getData(player) then
		return { success = false, reason = "Closed" }
	elseif not podiumPart then
		return { success = false, reason = "Closed" }
	elseif not isNearPodium(player) then
		return { success = false, reason = "TooFar" }
	elseif not PlayerDataHandler.spend(player, "Gems", AbilityData.RollCost * rolls) then
		return { success = false, reason = "NoGems" }
	end

	local pity = getNumber(player, "AbilityPity")
	local owned = table.clone(getOwned(player))
	local ownedSet: { [string]: boolean } = { [AbilityData.DefaultAbilityId] = true }
	for _, id in owned do
		ownedSet[id] = true
	end

	local results: { RollEntry } = {}
	local totalRefund = 0
	local gainedAny = false
	local halloween = WeatherHandler.isHalloween()
	for _ = 1, rolls do
		local guaranteed = pity + 1 >= AbilityData.PityRolls
		local ability = AbilityData.roll(random, guaranteed, halloween)
		local isNew = not ownedSet[ability.id]
		local refund = 0

		if isNew then
			ownedSet[ability.id] = true
			table.insert(owned, ability.id)
			gainedAny = true
		else
			refund = math.floor(AbilityData.RollCost * (AbilityData.DuplicateRefund[ability.rarity] or 0))
			totalRefund += refund
		end
		pity = if AbilityData.PityRarities[ability.rarity] then 0 else pity + 1

		table.insert(results, { id = ability.id, isNew = isNew, refund = refund, guaranteed = guaranteed })
	end

	if gainedAny then
		PlayerDataHandler.set(player, "OwnedAbilities", owned)
	end
	if totalRefund > 0 then
		PlayerDataHandler.increment(player, "Gems", totalRefund)
	end
	PlayerDataHandler.set(player, "AbilityPity", pity)
	Analytics.abilityRolled(player, AbilityData.RollCost * rolls, totalRefund, results)

	return { success = true, results = results }
end

-- Adds an ability to OwnedAbilities without a roll (the admin hook). Returns false for unknown or already owned ids.
function AbilityShackHandler.grant(player: Player, id: string): boolean
	if not AbilityData.get(id) or not PlayerDataHandler.getData(player) or isOwned(player, id) then
		return false
	end
	local owned = table.clone(getOwned(player))
	table.insert(owned, id)
	PlayerDataHandler.set(player, "OwnedAbilities", owned)
	return true
end

-- Returns nil on success, or "Unknown", "NotOwned" or "Active" (can't swap while an ability is running).
function AbilityShackHandler.equip(player: Player, id: any): string?
	local ability = AbilityData.get(id)
	if not ability or not PlayerDataHandler.getData(player) then
		return "Unknown"
	elseif not isOwned(player, ability.id) then
		return "NotOwned"
	elseif player:GetAttribute(ACTIVE_ATTRIBUTE) ~= nil then
		return "Active"
	end

	if PlayerDataHandler.get(player, "AbilityEquipped") ~= ability.id then
		PlayerDataHandler.set(player, "AbilityEquipped", ability.id)
		Analytics.abilityEquipped(player, ability.id)
	end
	return nil
end

--// Podium ------------------------------------------------------------------------------

-- Like WaitForChild, but warns once in our own words instead of an infinite-yield warning.
local function waitForChildQuietly(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end

	local thread = coroutine.running()
	local warnThread = task.delay(MISSING_WARN_SECONDS, function()
		warn(`AbilityShackHandler: waiting for {parent:GetFullName()}.{name} (build it in Studio; see the Ability Shack notes).`)
	end)
	local connection: RBXScriptConnection
	connection = parent.ChildAdded:Connect(function(added: Instance)
		if added.Name == name then
			connection:Disconnect()
			task.spawn(thread, added)
		end
	end)
	local found = coroutine.yield()
	task.cancel(warnThread)
	return found
end

local function getPodiumPart(podium: Instance): BasePart?
	if podium:IsA("BasePart") then
		return podium
	elseif podium:IsA("Model") then
		return podium.PrimaryPart or podium:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function watchPodium()
	local shack = waitForChildQuietly(workspace.Base.CenterPlaza, SHACK_NAME)
	while true do
		local podium = waitForChildQuietly(shack, PODIUM_NAME)
		local part = getPodiumPart(podium)
		if part then
			podiumPart = part
		else
			warn(`AbilityShackHandler: {podium:GetFullName()} must be a BasePart or a Model with a PrimaryPart.`)
		end

		-- Rebuilt in Studio or replaced at runtime: find the new one.
		while podium.Parent == shack do
			podium.AncestryChanged:Wait()
		end
		podiumPart = nil
	end
end

--// Lifecycle ---------------------------------------------------------------------

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.AbilityState, player, AbilityShackHandler.getState(player))
	end
end

function AbilityShackHandler.Start()
	task.spawn(watchPodium)
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RollAbility, function(player: Player, count: any)
		local result = AbilityShackHandler.roll(player, count)
		network.fireClient(network.RemoteEvents.AbilityRollResult, player, result)

		local podium = podiumPart
		local best = getRarestEntry(result.results)
		if result.success and podium and best then
			network.fireClientsInRangeExcept(
				network.RemoteEvents.AbilityRollResult,
				podium.Position,
				SPECTATOR_RANGE,
				{ player },
				{ success = true, results = { best }, roller = player } :: RollResult
			)
		end
	end, { network.Middleware.RateLimit(ROLL_COOLDOWN) })

	-- An equip that changes AbilityEquipped is answered by the AbilityState its Changed pushes; anything else sends it here, with the refusal's reason.
	network.connectEvent(network.RemoteEvents.EquipAbility, function(player: Player, id: any)
		local before = PlayerDataHandler.get(player, "AbilityEquipped")
		local reason = AbilityShackHandler.equip(player, id)
		if reason or before == id then
			network.fireClient(network.RemoteEvents.AbilityState, player, AbilityShackHandler.getState(player), reason)
		end
	end, { network.Middleware.RateLimit(EQUIP_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestAbilityState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(pushState)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "OwnedAbilities" or key == "AbilityEquipped" or key == "AbilityPity" then
			pushState(player)
		end
	end)

	-- Halloween abilities join or leave the roll chances.
	WeatherHandler.HalloweenChanged:Connect(function()
		for _, player in players:GetPlayers() do
			task.spawn(pushState, player)
		end
	end)

	for _, player in players:GetPlayers() do
		task.spawn(pushState, player)
	end
end

return AbilityShackHandler
