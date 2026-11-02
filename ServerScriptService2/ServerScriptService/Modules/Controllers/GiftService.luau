--!strict

--[[
	Gifting: validates a gift request (ownership and price levels) and saves it in the gifter's save, turns the gift product's receipt into a
	GiftOutbox entry, and delivers it to the recipient exactly once (straight away if they're here, otherwise as an offline message to their save).

	Location: ServerScriptService.Modules.Controllers.GiftService
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationConfig = require(replicatedStorage.Shared.Utils.MonetizationConfig)
local Wiring = require(script.Parent.MonetizationWiring)
local GamePassService = require(script.Parent.GamePassService)
local PriceLevelService = require(script.Parent.PriceLevelService)
local ReceiptProcessor = require(script.Parent.ReceiptProcessor)

--// Configs
local PENDING_KEY = "PendingGifts" -- save key: { [item key]: { userId, name } } picked in the gift window, until the receipt arrives
local OUTBOX_KEY = "GiftOutbox" -- save key: { [PurchaseId]: { item, userId, name } } paid gifts not yet delivered
local RECEIVED_TAG = "ReceivedGiftIds" -- record: gift ids already applied to this save, so a re-delivery is ignored
local RECEIVED_CACHE_SIZE = 200
local SAVE_CONFIRM_TIMEOUT = 120 -- an in-server delivery not confirmed saved by then stays in the outbox and is retried
local RETRY_SECONDS = 60
local MESSAGE_TYPE = "Gift"

export type Reason = "NotGiftable" | "NotLoaded" | "NotInServer" | "Self" | "AlreadyOwned" | "PriceLevel"

-- Why a player can't be picked in the gift window.
export type Lock = "Owned" | "PriceLevel"

-- Applies an item to a player with loaded data (a pass, boost time, currency...); true once it's in their save. Must not yield.
export type GrantHandler = (player: Player, key: string) -> boolean

-- Fired once a gift is paid for, e.g. for a server-wide announcement.
export type GiftSentCallback = (gifter: Player, item: Wiring.Item, robuxSpent: number, recipientName: string) -> ()

--// State
local config, store, notify = Wiring.config, Wiring.store, Wiring.notify
local grantHandler: GrantHandler? = nil
local giftSentCallbacks: { GiftSentCallback } = {}
local delivering: { [string]: boolean } = {}

local GiftService = {}

local function getTable(player: Player, key: string): { [string]: any }?
	local value = store.get(player, key)
	return if type(value) == "table" then value else nil
end

--// Receiving ---------------------------------------------------------------------

-- Grants a gift to a loaded recipient unless this gift id was already applied; the id is saved with the grant.
local function receiveGift(recipient: Player, giftId: string, key: string, gifterName: string): boolean
	local item = config.get(key)
	if not store.isLoaded(recipient) or not item or not grantHandler then
		return false
	end
	if store.hasRecord(recipient, RECEIVED_TAG, giftId) then
		return true
	end

	if not grantHandler(recipient, key) then
		return false
	end
	store.addRecord(recipient, RECEIVED_TAG, giftId, RECEIVED_CACHE_SIZE)
	notify(recipient, `{gifterName} gifted you {item.displayName}!`, "success")
	return true
end

--// Delivering ---------------------------------------------------------------------

local function removeFromOutbox(gifter: Player, giftId: string)
	local outbox = getTable(gifter, OUTBOX_KEY)
	if outbox and outbox[giftId] then
		local newOutbox = table.clone(outbox)
		newOutbox[giftId] = nil
		store.set(gifter, OUTBOX_KEY, newOutbox)
	end
end

-- Sends one paid gift on; it stays in the gifter's outbox until the recipient's save has it, so it's never lost.
local function deliver(gifter: Player, giftId: string)
	local outbox = getTable(gifter, OUTBOX_KEY)
	local entry = outbox and outbox[giftId]
	if not entry or delivering[giftId] then
		return
	end
	delivering[giftId] = true

	local delivered = false
	local recipient = players:GetPlayerByUserId(entry.userId)
	if recipient and store.isLoaded(recipient) then
		delivered = receiveGift(recipient, giftId, entry.item, gifter.Name)
			and store.waitForRecordSaved(recipient, RECEIVED_TAG, giftId, SAVE_CONFIRM_TIMEOUT)
	end
	if not delivered then
		-- Not here (or left mid-delivery): the next server to load their save applies it; re-sends are ignored there.
		delivered = store.sendToUser(entry.userId, {
			type = MESSAGE_TYPE,
			giftId = giftId,
			item = entry.item,
			gifterName = gifter.Name,
		})
	end

	if delivered then
		removeFromOutbox(gifter, giftId)
	end
	delivering[giftId] = nil
end

local function deliverAll(gifter: Player)
	local outbox = getTable(gifter, OUTBOX_KEY)
	for giftId in outbox or {} do
		task.spawn(deliver, gifter, giftId)
	end
end

--// Receipts ---------------------------------------------------------------------

local function onGiftReceipt(gifter: Player, receiptInfo: any, item: Wiring.Item): boolean
	if not grantHandler then
		return false
	end

	local pending = getTable(gifter, PENDING_KEY)
	local outbox = getTable(gifter, OUTBOX_KEY)
	local entry = pending and pending[item.key]
	if not pending or not outbox then
		return false
	end

	-- Bought without picking anyone, or the recipient (still here) is no longer at an equal or lower price level:
	-- it's still paid for, so the buyer gets it.
	local recipient = entry and players:GetPlayerByUserId(entry.userId)
	local priceLevelBlocked = recipient ~= nil and not PriceLevelService.canGift(gifter, recipient)
	if not entry or priceLevelBlocked then
		if not grantHandler(gifter, item.key) then
			return false
		end
		if priceLevelBlocked then
			local newPending = table.clone(pending)
			newPending[item.key] = nil
			store.set(gifter, PENDING_KEY, newPending)
			notify(gifter, `{item.displayName} can't be gifted to {entry.name}, so it's yours!`, "info")
		else
			notify(gifter, `No one was picked, so {item.displayName} is yours!`, "success")
		end
		return true
	end

	local giftId = tostring(receiptInfo.PurchaseId)
	local newOutbox = table.clone(outbox)
	newOutbox[giftId] = { item = item.key, userId = entry.userId, name = entry.name }
	local newPending = table.clone(pending)
	newPending[item.key] = nil
	store.set(gifter, OUTBOX_KEY, newOutbox)
	store.set(gifter, PENDING_KEY, newPending)

	notify(gifter, `You gifted {item.displayName} to {entry.name}!`, "success")
	local robuxSpent = tonumber(receiptInfo.CurrencySpent) or 0
	for _, callback in giftSentCallbacks do
		task.spawn(callback, gifter, item, robuxSpent, entry.name)
	end
	task.defer(deliver, gifter, giftId)
	return true
end

--// Public API ------------------------------------------------------------------

-- Sets how a gifted item is applied to its recipient (and to a buyer who bought a gift without picking anyone).
function GiftService.setGrantHandler(handler: GrantHandler)
	grantHandler = handler
end

function GiftService.onGiftSent(callback: GiftSentCallback)
	table.insert(giftSentCallbacks, callback)
end

-- For an item that shares its product id with its gift (MonetizationConfig.sharesGiftProduct): its product handler calls this
-- first, and a receipt bought while a recipient is picked is a gift. nil = not a gift, grant it to the buyer as usual.
function GiftService.processSharedReceipt(gifter: Player, receiptInfo: any, item: Wiring.Item): boolean?
	local pending = getTable(gifter, PENDING_KEY)
	if not MonetizationConfig.sharesGiftProduct(item) or not pending or not pending[item.key] then
		return nil
	end
	return onGiftReceipt(gifter, receiptInfo, item)
end

-- Forgets the recipient picked for a shared-id item, so the next purchase of it is the buyer's own.
function GiftService.clearPendingGift(gifter: Player, key: string)
	local pending = getTable(gifter, PENDING_KEY)
	if pending and pending[key] then
		local newPending = table.clone(pending)
		newPending[key] = nil
		store.set(gifter, PENDING_KEY, newPending)
	end
end

-- Checks a gift and saves who it's for in the gifter's save; the client then prompts the gift product. Bind it to a rate-limited remote.
function GiftService.requestGift(gifter: Player, key: any, recipientUserId: any): (boolean, Reason?)
	local item = config.get(key)
	if not item or not item.giftable or item.giftProductId == 0 then
		return false, "NotGiftable"
	end
	if not store.isLoaded(gifter) then
		return false, "NotLoaded"
	end

	local recipient = if type(recipientUserId) == "number" then players:GetPlayerByUserId(recipientUserId) else nil
	if not recipient then
		return false, "NotInServer"
	elseif recipient == gifter then
		return false, "Self"
	elseif item.kind == "GamePass" and GamePassService.ownsPass(recipient, item.key) then
		return false, "AlreadyOwned"
	elseif not PriceLevelService.canGiftAsync(gifter, recipient) then
		return false, "PriceLevel"
	end

	-- Read after the price level check, which can yield.
	local pending = getTable(gifter, PENDING_KEY)
	if not pending then
		return false, "NotLoaded"
	end
	local newPending = table.clone(pending)
	newPending[item.key] = { userId = recipient.UserId, name = recipient.Name }
	store.set(gifter, PENDING_KEY, newPending)
	return true, nil
end

-- The other players here the asker can't gift this item to, keyed by tostring(UserId): they own the pass, or are at a higher price level.
function GiftService.getGiftLocks(asker: Player, key: any): { [string]: Lock }
	local item = config.get(key)
	local locks: { [string]: Lock } = {}
	if not item or not item.giftable then
		return locks
	end
	for _, player in players:GetPlayers() do
		if player == asker then
			continue
		end
		if item.kind == "GamePass" and GamePassService.ownsPass(player, item.key) then
			locks[tostring(player.UserId)] = "Owned"
		elseif not PriceLevelService.canGiftAsync(asker, player) then
			locks[tostring(player.UserId)] = "PriceLevel"
		end
	end
	return locks
end

--// Lifecycle ---------------------------------------------------------------------

function GiftService.Setup()
	for _, item in config.Items do
		if item.giftable and not MonetizationConfig.sharesGiftProduct(item) then
			ReceiptProcessor.registerProduct(item.giftProductId, onGiftReceipt)
		end
	end

	-- A cancelled gift of a shared-id item mustn't turn the buyer's next own purchase of it into a gift.
	marketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		local item = config.findByProductId(productId)
		local gifter = players:GetPlayerByUserId(userId)
		if not purchased and gifter and item and MonetizationConfig.sharesGiftProduct(item) then
			GiftService.clearPendingGift(gifter, item.key)
		end
	end)

	store.setMessageHandler(function(player: Player, message: any): boolean
		if type(message) ~= "table" or message.type ~= MESSAGE_TYPE then
			return false
		end
		return receiveGift(player, tostring(message.giftId), message.item, tostring(message.gifterName))
	end)
end

function GiftService.Start()
	store.onLoaded(deliverAll)
	for _, player in players:GetPlayers() do
		if store.isLoaded(player) then
			task.spawn(deliverAll, player)
		end
	end

	-- Retries gifts whose delivery failed (e.g. a DataStore outage) while their gifter is still here.
	task.spawn(function()
		while true do
			task.wait(RETRY_SECONDS)
			for _, player in players:GetPlayers() do
				deliverAll(player)
			end
		end
	end)
end

return GiftService
