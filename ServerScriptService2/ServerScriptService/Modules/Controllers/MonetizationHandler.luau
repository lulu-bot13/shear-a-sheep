--!strict

--[[
	Shear A Sheep's Robux perks (pass and boost multipliers, the Auto Shear unlock, Server Luck, Skip Rebirth, Gem packs), registered into the monetization kit,
	plus the shop's remotes. Boost time only counts down in game; Skip Rebirths at max rebirths are kept as FreeRebirths.

	Location: ServerScriptService.Modules.Controllers.MonetizationHandler
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local GamePassService = require(script.Parent.GamePassService)
local GemHandler = require(script.Parent.GemHandler)
local GiftService = require(script.Parent.GiftService)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)
local ReceiptProcessor = require(script.Parent.ReceiptProcessor)

--// Configs
local TICK_SECONDS = 1
local PROMPT_COOLDOWN = 1
local STATE_REQUEST_COOLDOWN = 0.5
local GIFT_REQUEST_COOLDOWN = 1
local GIFT_LOCKS_COOLDOWN = 0.5
local PRESTIGE_SETTLE_SECONDS = 3 -- saved Skip Rebirths are used this long after a Prestige, once its farm reset is done
local ENDS_AT_SUFFIX = "EndsAt" -- player attribute <boost key>EndsAt: workspace:GetServerTimeNow() the boost runs out (for a future timer UI)
local SERVER_LUCK_ATTRIBUTE = "ServerLuckEndsAt" -- workspace attribute, the same for Server Luck
local AUTO_SHEAR_ATTRIBUTE = "AutoShearPass" -- player attribute ShearClient reads to unlock Auto Shear
local STATE_KEYS = { Rebirths = true, Prestiges = true, GiftedPasses = true }

local Items = MonetizationData.Items
local BOOST_KEYS = { "LuckBoost" }

-- What the shop needs to draw its cards.
export type ShopState = {
	passes: { [string]: boolean }, -- pass keys this player owns (bought or gifted)
	rebirthMaxed: boolean, -- Skip Rebirth can't be bought
}

--// State
local serverLuckEndsAt = 0
local pushQueued: { [Player]: boolean } = {}

local MonetizationHandler = {}

local function showAlert(player: Player, text: string, kind: string?)
	network.fireClient(network.RemoteEvents.ShowAlert, player, text, kind or "success")
end

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

--// Boosts ---------------------------------------------------------------------------

local function getBoostSeconds(player: Player, key: string): number
	local boosts = PlayerDataHandler.get(player, "Boosts")
	local seconds = if type(boosts) == "table" then boosts[key] else nil
	return if type(seconds) == "number" then seconds else 0
end

local function updateBoostAttributes(player: Player)
	local now = workspace:GetServerTimeNow()
	for _, key in BOOST_KEYS do
		local seconds = getBoostSeconds(player, key)
		player:SetAttribute(key .. ENDS_AT_SUFFIX, if seconds > 0 then now + seconds else nil)
	end
end

local function isServerLuckActive(): boolean
	return workspace:GetServerTimeNow() < serverLuckEndsAt
end

-- Counts every loaded player's boosts down by `elapsed` seconds and ends Server Luck when it runs out.
local function tickBoosts(elapsed: number)
	for _, player in players:GetPlayers() do
		local boosts = PlayerDataHandler.get(player, "Boosts")
		if type(boosts) ~= "table" or next(boosts) == nil then
			continue
		end

		local expired = {}
		for key, seconds in boosts do
			-- Ticked in place: only the end of a boost is worth a Changed.
			boosts[key] = seconds - elapsed
			if boosts[key] <= 0 then
				table.insert(expired, key)
			end
		end
		if #expired > 0 then
			local newBoosts = table.clone(boosts)
			for _, key in expired do
				newBoosts[key] = nil
				local item = Items[key]
				showAlert(player, `Your {if item then item.displayName else key} ran out`, "info")
			end
			PlayerDataHandler.set(player, "Boosts", newBoosts)
			updateBoostAttributes(player)
		end
	end

	if serverLuckEndsAt > 0 and not isServerLuckActive() then
		serverLuckEndsAt = 0
		workspace:SetAttribute(SERVER_LUCK_ATTRIBUTE, nil)
	end
end

--// Grants ------------------------------------------------------------------------------
-- Each one applies an item to a player with loaded data and returns whether it worked, plus the toast for a buyer.

local function addBoost(player: Player, item: MonetizationData.Item): (boolean, string?)
	local boosts = PlayerDataHandler.get(player, "Boosts")
	if type(boosts) ~= "table" then
		return false, nil
	end

	local minutes = item.durationMinutes or 0
	local newBoosts = table.clone(boosts)
	newBoosts[item.key] = math.max(newBoosts[item.key] or 0, 0) + minutes * 60
	PlayerDataHandler.set(player, "Boosts", newBoosts)
	updateBoostAttributes(player)
	return true, `{item.displayName} active! +{minutes} minutes`
end

local function activateServerLuck(player: Player, item: MonetizationData.Item): (boolean, string?)
	local minutes = item.durationMinutes or 0
	serverLuckEndsAt = math.max(serverLuckEndsAt, workspace:GetServerTimeNow()) + minutes * 60
	workspace:SetAttribute(SERVER_LUCK_ATTRIBUTE, serverLuckEndsAt)
	AnnouncementHandler.serverLuck(player, item.multiplier or 1, minutes)
	return true, `{item.displayName} is on for everyone for +{minutes} minutes!`
end

local function showRebirthResult(player: Player)
	network.fireClient(network.RemoteEvents.RebirthResult, player, true, nil, RebirthHandler.getRebirths(player), 1)
end

-- A rebirth with no wool cost; at max rebirths it's saved as a FreeRebirths credit instead, so it's never lost.
local function skipRebirth(player: Player, _item: MonetizationData.Item): (boolean, string?)
	local success, reason = RebirthHandler.rebirth(player, 1, true)
	if success then
		showRebirthResult(player)
		return true, "Rebirth skipped!"
	elseif reason == "MaxRebirths" then
		PlayerDataHandler.increment(player, "FreeRebirths", 1)
		return true, "You're at max rebirths, so your Skip Rebirth is saved for after your next Prestige!"
	end
	return false, nil
end

local function giveGems(player: Player, item: MonetizationData.Item): (boolean, string?)
	local amount = item.gems or 0
	return GemHandler.give(player, amount) ~= nil, `+{amount} Gems!`
end

local function grantPass(player: Player, item: MonetizationData.Item): (boolean, string?)
	return GamePassService.grantGiftedPass(player, item.key), `You now own {item.displayName}!`
end

local GRANTS: { [string]: (Player, MonetizationData.Item) -> (boolean, string?) } = {
	DoubleWool = grantPass,
	DoubleLuck = grantPass,
	AutoShears = grantPass,
	LuckBoost = addBoost,
	ServerLuck = activateServerLuck,
	SkipRebirth = skipRebirth,
	GemsSmall = giveGems,
	GemsMedium = giveGems,
	GemsLarge = giveGems,
}

local function grantItem(player: Player, key: string): (boolean, string?)
	local item = Items[key]
	local grant = GRANTS[key]
	if not item or not grant then
		return false, nil
	end
	return grant(player, item)
end

local function onProductReceipt(player: Player, receiptInfo: any, item: MonetizationData.Item): boolean
	local gifted = GiftService.processSharedReceipt(player, receiptInfo, item)
	if gifted ~= nil then
		return gifted
	end

	local success, message = grantItem(player, item.key)
	if success and message then
		showAlert(player, message)
	end
	return success
end

-- Spends saved Skip Rebirths while a rebirth is possible.
local function useFreeRebirths(player: Player)
	while getNumber(player, "FreeRebirths") > 0 do
		if not RebirthHandler.rebirth(player, 1, true) then
			return
		end
		PlayerDataHandler.increment(player, "FreeRebirths", -1)
		showRebirthResult(player)
		showAlert(player, "Used a saved Skip Rebirth!")
	end
end

--// Public API ------------------------------------------------------------------

-- The 2x WOOL pass.
function MonetizationHandler.getWoolMultiplier(player: Player): number
	if GamePassService.ownsPass(player, "DoubleWool") then
		return Items.DoubleWool.multiplier or 1
	end
	return 1
end

-- The 2x LUCK pass, the Luck Boost and Server Luck, multiplied together.
function MonetizationHandler.getLuckMultiplier(player: Player): number
	local multiplier = 1
	if GamePassService.ownsPass(player, "DoubleLuck") then
		multiplier *= Items.DoubleLuck.multiplier or 1
	end
	if getBoostSeconds(player, "LuckBoost") > 0 then
		multiplier *= Items.LuckBoost.multiplier or 1
	end
	if isServerLuckActive() then
		multiplier *= Items.ServerLuck.multiplier or 1
	end
	return multiplier
end

function MonetizationHandler.getShopState(player: Player): ShopState
	return {
		passes = GamePassService.getOwnedPasses(player),
		rebirthMaxed = RebirthHandler.getState(player).maxed,
	}
end

--// Lifecycle ---------------------------------------------------------------------

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.ShopState, player, MonetizationHandler.getShopState(player))
	end
end

local function queuePush(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		pushState(player)
	end)
end

-- Prompts a developer product from the server, so one that can't be bought right now (Skip Rebirth at max) never opens.
local function onPromptRequest(player: Player, key: any)
	local item = MonetizationData.get(key)
	if not item or item.kind ~= "DevProduct" or item.id == 0 then
		return
	end
	if item.key == "SkipRebirth" and RebirthHandler.getState(player).maxed then
		showAlert(player, "You're at max rebirths! Prestige first.", "error")
		return
	end
	-- Bought from the shop, so it's for the buyer even if a gift of it was picked earlier.
	GiftService.clearPendingGift(player, item.key)
	marketplaceService:PromptProductPurchase(player, item.id)
end

function MonetizationHandler.Setup()
	for key, item in Items do
		if item.kind == "DevProduct" and GRANTS[key] then
			ReceiptProcessor.registerProduct(item.id, onProductReceipt)
		end
	end
	GiftService.setGrantHandler(function(player: Player, key: string): boolean
		return (grantItem(player, key))
	end)
	GiftService.onGiftSent(function(gifter: Player, item: MonetizationData.Item, robuxSpent: number, recipientName: string)
		AnnouncementHandler.gift(gifter, item.displayName, robuxSpent, recipientName)
	end)

	for key, item in Items do
		if item.kind == "GamePass" then
			GamePassService.onPassOwned(key, function(player: Player, source: GamePassService.Source)
				if source == "Purchased" then
					showAlert(player, `You now own {item.displayName}!`)
				end
			end)
		end
	end

	GamePassService.onPassOwned("AutoShears", function(player: Player, _source: GamePassService.Source)
		player:SetAttribute(AUTO_SHEAR_ATTRIBUTE, true)
	end)
end

function MonetizationHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RequestProductPrompt, onPromptRequest, {
		network.Middleware.RateLimit(PROMPT_COOLDOWN),
	})
	network.connectEvent(network.RemoteEvents.RequestShopState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})
	network.bindFunction(network.RemoteFunctions.RequestGift, GiftService.requestGift, {
		network.Middleware.RateLimit(GIFT_REQUEST_COOLDOWN),
	})
	network.bindFunction(network.RemoteFunctions.GetGiftLocks, GiftService.getGiftLocks, {
		network.Middleware.RateLimit(GIFT_LOCKS_COOLDOWN),
	})

	local function onLoaded(player: Player)
		updateBoostAttributes(player)
		pushState(player)
		task.defer(useFreeRebirths, player)
	end
	PlayerDataHandler.Loaded:Connect(onLoaded)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if STATE_KEYS[key] then
			queuePush(player)
		end
		if key == "Prestiges" then
			task.delay(PRESTIGE_SETTLE_SECONDS, useFreeRebirths, player)
		end
	end)
	GamePassService.onChanged(queuePush)

	players.PlayerRemoving:Connect(function(player: Player)
		pushQueued[player] = nil
	end)
	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) then
			task.spawn(onLoaded, player)
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK_SECONDS)
			local now = os.clock()
			tickBoosts(now - last)
			last = now
		end
	end)
end

return MonetizationHandler
