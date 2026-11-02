--!strict

--[[
	The game's one MarketplaceService.ProcessReceipt: runs the handler registered for each developer product exactly once per PurchaseId,
	and only says PurchaseGranted once the grant and its PurchaseId are confirmed saved (NotProcessedYet while the data isn't loaded).

	Location: ServerScriptService.Modules.Controllers.ReceiptProcessor
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")

--// Modules
local Wiring = require(script.Parent.MonetizationWiring)

--// Configs
local PURCHASE_IDS_TAG = "ProfilePurchaseIds"
local PURCHASE_ID_CACHE_SIZE = 50 -- the newest purchase ids kept; Roblox never re-sends one this old

-- Grants the product and returns true, or false to have Roblox retry later. Must not yield: its changes and the
-- recorded PurchaseId have to land in the same save.
export type Handler = (player: Player, receiptInfo: any, item: Wiring.Item) -> boolean

--// State
local config, store = Wiring.config, Wiring.store
local handlers: { [number]: Handler } = {}

local ReceiptProcessor = {}

local function processReceipt(receiptInfo: any): Enum.ProductPurchaseDecision
	local player = players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player or not store.isLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = handlers[receiptInfo.ProductId]
	local item = config.findByProductId(receiptInfo.ProductId)
	if not handler or not item then
		warn(`ReceiptProcessor: no handler for product {receiptInfo.ProductId} (bought by {player.Name}); it will be retried`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if not store.hasRecord(player, PURCHASE_IDS_TAG, purchaseId) then
		local success, granted = pcall(handler, player, receiptInfo, item)
		if not success or granted ~= true then
			if not success then
				warn(`ReceiptProcessor: granting {item.key} to {player.Name} failed: {granted}`)
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not store.addRecord(player, PURCHASE_IDS_TAG, purchaseId, PURCHASE_ID_CACHE_SIZE) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	-- Yields until the grant is confirmed saved; a release before that means it's retried on their next join.
	if store.waitForRecordSaved(player, PURCHASE_IDS_TAG, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

--// Public API ------------------------------------------------------------------

-- Registers the grant for one developer product id (a product's own id or a gift product id). Ids still 0 are skipped.
function ReceiptProcessor.registerProduct(productId: number, handler: Handler)
	if productId == 0 then
		return
	end
	if handlers[productId] then
		warn(`ReceiptProcessor: product {productId} was registered twice; the second handler replaces the first`)
	end
	handlers[productId] = handler
end

--// Lifecycle ---------------------------------------------------------------------

-- Set in Start, after every module's Setup has registered its products.
function ReceiptProcessor.Start()
	marketplaceService.ProcessReceipt = processReceipt
end

return ReceiptProcessor
