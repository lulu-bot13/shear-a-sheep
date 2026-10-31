--!strict

--[[
	Sends the game's funnels, progression, economy and custom events to Roblox Analytics (Creator Hub > Analytics).
	Handlers call its functions where things happen; the client reports tutorial steps and window opens through AnalyticsEvent.
]]--

--// Services
local analyticsService = game:GetService("AnalyticsService")
local httpService = game:GetService("HttpService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local MutationData = require(script.Parent.Parent.Constants.MutationData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local ENABLED = false -- off: nothing is sent to Roblox Analytics
local FLUSH_SECONDS = 60 -- wool, Luck and sheep shorn are summed and sent this often, so busy shearing stays under the event limits
local CLIENT_EVENT_BUDGET = 10 -- tutorial steps and window opens a client may report per window
local CLIENT_EVENT_WINDOW = 10
local RARE_RARITIES = { Epic = true, Legendary = true, Mythic = true } -- shearing one of these bare is its own event
local FIELD_1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local FIELD_2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name
local FIELD_3 = Enum.AnalyticsCustomFieldKeys.CustomField03.Name

-- The first-play funnel, in order; Roblox keeps each step once per player.
local ONBOARDING_STEPS = {
	"Joined Game",
	"Equipped Shears",
	"Reached a Sheep",
	"Sheared First Sheep",
	"Sheared 3 Sheep",
	"Opened Upgrades",
	"Bought First Upgrade",
	"Finished Tutorial Upgrades",
	"Opened Rebirth",
	"First Rebirth",
}
local ONBOARDING_STEP: { [string]: number } = {}
for index, name in ONBOARDING_STEPS do
	ONBOARDING_STEP[name] = index
end
local TUTORIAL_STAGE_STEPS = { GoToSheep = "Equipped Shears", FirstShear = "Reached a Sheep", CloseUpgrades = "Finished Tutorial Upgrades" }
local WINDOW_OPEN_STEPS = { UpgradeShop = "Opened Upgrades", Rebirth = "Opened Rebirth" }

-- Funnels that start each time their window is opened; each step after the first is logged once per opening.
local WINDOW_FUNNELS: { [string]: { name: string, steps: { string } } } = {
	UpgradeShop = { name = "Upgrades", steps = { "Opened Upgrades", "Bought Upgrade" } },
	Rebirth = { name = "Rebirth", steps = { "Opened Rebirth", "Rebirthed" } },
	ShearShop = { name = "Shear Shop", steps = { "Opened Shear Shop", "Bought Shears" } },
	AbilityShack = { name = "Ability Shack", steps = { "Opened Ability Shack", "Rolled Ability", "Equipped Ability" } },
	Index = { name = "Index", steps = { "Opened Index", "Claimed Reward" } },
}

type Pending = {
	wool: { [string]: number }, -- source -> wool earned since the last flush
	luck: number,
	sheared: number,
}

type FunnelSession = {
	id: string,
	logged: { [number]: boolean },
}

--// State
local onboarding: { [Player]: { [number]: boolean } } = {} -- steps logged this session; nil for players past the tutorial
local pending: { [Player]: Pending } = {}
local funnelSessions: { [Player]: { [string]: FunnelSession } } = {}
local clientBudgets: { [Player]: { since: number, count: number } } = {}

local Analytics = {}

--// Helpers -------------------------------------------------------------------------

-- Analytics calls can error in Studio or when throttled; that must never break gameplay.
local function safeCall(method: string, ...: any)
	if not ENABLED then
		return
	end
	local success, err = pcall((analyticsService :: any)[method], analyticsService, ...)
	if not success then
		warn(`Analytics: {method} failed: {err}`)
	end
end

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function fields(first: any?, second: any?, third: any?): { [string]: string }
	return {
		[FIELD_1] = if first ~= nil then tostring(first) else nil,
		[FIELD_2] = if second ~= nil then tostring(second) else nil,
		[FIELD_3] = if third ~= nil then tostring(third) else nil,
	} :: any
end

local function logCustom(player: Player, eventName: string, value: number?, customFields: { [string]: string }?)
	safeCall("LogCustomEvent", player, eventName, value or 1, customFields)
end

local function logEconomy(player: Player, flow: Enum.AnalyticsEconomyFlowType, currency: string, amount: number,
	transaction: Enum.AnalyticsEconomyTransactionType, sku: string)
	if amount <= 0 then
		return
	end
	safeCall("LogEconomyEvent", player, flow, currency, amount, getNumber(player, currency), transaction.Name, sku)
end

-- Logs an onboarding step once; steps for players who are past the tutorial are skipped.
local function logOnboarding(player: Player, stepName: string)
	local logged = onboarding[player]
	local step = ONBOARDING_STEP[stepName]
	if not logged or not step or logged[step] then
		return
	end
	logged[step] = true
	safeCall("LogOnboardingFunnelStepEvent", player, step, stepName)
end

-- Logs `step` of the window's funnel once for its current opening; step 1 starts a new opening.
local function logWindowFunnel(player: Player, windowName: string, step: number)
	local funnel = WINDOW_FUNNELS[windowName]
	local sessions = funnelSessions[player]
	if not funnel or not sessions or not funnel.steps[step] then
		return
	end

	if step == 1 then
		sessions[windowName] = { id = httpService:GenerateGUID(false), logged = {} }
	end
	local session = sessions[windowName]
	if not session or session.logged[step] then
		return
	end
	session.logged[step] = true
	safeCall("LogFunnelStepEvent", player, funnel.name, session.id, step, funnel.steps[step])
end

local function getPending(player: Player): Pending?
	return pending[player]
end

-- Sends the wool, Luck and sheep shorn summed up since the last flush.
local function flush(player: Player)
	local totals = pending[player]
	if not totals then
		return
	end

	for source, wool in totals.wool do
		logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, "Wool", wool, Enum.AnalyticsEconomyTransactionType.Gameplay, source)
	end
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, "Luck", totals.luck, Enum.AnalyticsEconomyTransactionType.Gameplay, "Shearing")
	if totals.sheared > 0 then
		logCustom(player, "Sheared a Sheep", totals.sheared)
	end

	pending[player] = { wool = {}, luck = 0, sheared = 0 }
end

--// Gameplay events -------------------------------------------------------------------

-- Wool earned from `source` ("Shearing", "Podium"); summed and sent with the next flush.
function Analytics.woolEarned(player: Player, amount: number, source: string)
	local totals = getPending(player)
	if totals and amount > 0 then
		totals.wool[source] = (totals.wool[source] or 0) + amount
	end
end

function Analytics.luckEarned(player: Player, amount: number)
	local totals = getPending(player)
	if totals and amount > 0 then
		totals.luck += amount
	end
end

-- A sheep shorn bare. Rare and mutated ones are sent straight away, the rest are counted.
function Analytics.sheepSheared(player: Player, sheep: Model)
	local totals = getPending(player)
	if totals then
		totals.sheared += 1
	end

	local sheared = getNumber(player, "SheepShearedCount")
	if sheared >= 1 then
		logOnboarding(player, "Sheared First Sheep")
	end
	if sheared >= 3 then
		logOnboarding(player, "Sheared 3 Sheep")
	end

	local sheepType = sheep:GetAttribute("SheepType")
	local info = if type(sheepType) == "string" then SheepData.Sheep[sheepType] else nil
	local mutation = MutationData.get(sheep:GetAttribute(MutationData.Attribute))
	if info and (RARE_RARITIES[info.rarity] or mutation) then
		logCustom(player, "Sheared Rare Sheep", 1, fields(sheepType, info.rarity, if mutation then mutation.id else "None"))
	end
end

function Analytics.sheepDiscovered(player: Player, sheepType: string, rarity: string)
	logCustom(player, "Discovered Sheep", 1, fields(sheepType, rarity))
end

function Analytics.indexClaimed(player: Player, count: number, luck: number)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, "Luck", luck, Enum.AnalyticsEconomyTransactionType.Gameplay, "IndexReward")
	logCustom(player, "Claimed Index Reward", count)
	logWindowFunnel(player, "Index", 2)
end

function Analytics.upgraded(player: Player, upgradeId: string, newLevel: number, levels: number, cost: number)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Sink, "Wool", cost, Enum.AnalyticsEconomyTransactionType.Shop, `Upgrade_{upgradeId}`)
	logCustom(player, "Upgraded", newLevel, fields(upgradeId, levels))
	logOnboarding(player, "Bought First Upgrade")
	logWindowFunnel(player, "UpgradeShop", 2)
end

function Analytics.rebirthed(player: Player, newRebirths: number, rebirths: number, cost: number)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Sink, "Wool", cost, Enum.AnalyticsEconomyTransactionType.Gameplay, "Rebirth")
	safeCall("LogProgressionCompleteEvent", player, "Rebirth", newRebirths, `Rebirth {newRebirths}`)
	logCustom(player, "Rebirthed", newRebirths, fields(rebirths))
	logOnboarding(player, "First Rebirth")
	logWindowFunnel(player, "Rebirth", 2)
end

function Analytics.prestiged(player: Player, newPrestiges: number)
	safeCall("LogProgressionCompleteEvent", player, "Prestige", newPrestiges, `Prestige {newPrestiges}`)
	logCustom(player, "Prestiged", newPrestiges)
end

function Analytics.shearBought(player: Player, shearId: string, price: number)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Sink, "Wool", price, Enum.AnalyticsEconomyTransactionType.Shop, `Shear_{shearId}`)
	logCustom(player, "Bought Shears", 1, fields(shearId))
	logWindowFunnel(player, "ShearShop", 2)
end

function Analytics.abilityUsed(player: Player, abilityId: string)
	logCustom(player, "Used Ability", 1, fields(abilityId))
end

-- One Ability Shack roll (1 or 5 at once) and what each roll gave.
function Analytics.abilityRolled(player: Player, cost: number, refund: number, results: { { id: string, isNew: boolean } })
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Sink, "Gems", cost, Enum.AnalyticsEconomyTransactionType.Shop, `AbilityRoll_x{#results}`)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, "Gems", refund, Enum.AnalyticsEconomyTransactionType.Gameplay, "DuplicateRefund")
	for _, result in results do
		local ability = AbilityData.get(result.id)
		logCustom(player, "Rolled Ability", 1, fields(result.id, if ability then ability.rarity else nil, if result.isNew then "New" else "Duplicate"))
	end
	logWindowFunnel(player, "AbilityShack", 2)
end

function Analytics.abilityEquipped(player: Player, abilityId: string)
	logCustom(player, "Equipped Ability", 1, fields(abilityId))
	logWindowFunnel(player, "AbilityShack", 3)
end

function Analytics.gemsFound(player: Player, amount: number, source: string)
	logEconomy(player, Enum.AnalyticsEconomyFlowType.Source, "Gems", amount, Enum.AnalyticsEconomyTransactionType.Gameplay, source)
end

function Analytics.podiumPlaced(player: Player, sheepType: any)
	logCustom(player, "Placed Podium Sheep", 1, fields(sheepType))
end

--// Client events ---------------------------------------------------------------------

-- True while the player is under CLIENT_EVENT_BUDGET reports per CLIENT_EVENT_WINDOW seconds; bursts (two steps at once) still get through.
local function takeClientBudget(player: Player): boolean
	local now = os.clock()
	local current = clientBudgets[player]
	local budget = if current and now - current.since < CLIENT_EVENT_WINDOW then current else { since = now, count = 0 }
	clientBudgets[player] = budget
	budget.count += 1
	return budget.count <= CLIENT_EVENT_BUDGET
end

local function onClientEvent(player: Player, kind: any, name: any)
	if type(name) ~= "string" or not takeClientBudget(player) then
		return
	end

	if kind == "Tutorial" then
		local step = TUTORIAL_STAGE_STEPS[name]
		if step then
			logOnboarding(player, step)
		end
	elseif kind == "Window" then
		local step = WINDOW_OPEN_STEPS[name]
		if step then
			logOnboarding(player, step)
		end
		logWindowFunnel(player, name, 1)
	end
end

--// Lifecycle ---------------------------------------------------------------------

local function onLoaded(player: Player)
	local isNew = getNumber(player, "SheepShearedCount") == 0 and getNumber(player, "Rebirths") == 0
	pending[player] = { wool = {}, luck = 0, sheared = 0 }
	funnelSessions[player] = {}
	if getNumber(player, "Rebirths") == 0 and getNumber(player, "Prestiges") == 0 then
		onboarding[player] = {}
	end

	logOnboarding(player, "Joined Game")
	logCustom(player, "Joined Game", 1, fields(if isNew then "New" else "Returning", getNumber(player, "Rebirths"), getNumber(player, "Prestiges")))
end

function Analytics.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.AnalyticsEvent, onClientEvent)

	PlayerDataHandler.Loaded:Connect(onLoaded)
	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) and not pending[player] then
			onLoaded(player)
		end
	end

	players.PlayerRemoving:Connect(function(player: Player)
		flush(player)
		pending[player] = nil
		onboarding[player] = nil
		funnelSessions[player] = nil
		clientBudgets[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			for player in pending do
				flush(player)
			end
		end
	end)
end

return Analytics
