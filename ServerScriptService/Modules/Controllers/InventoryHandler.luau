--!strict

--[[
    Generic per-player item inventory backed by IntValue instances under a
    Player.Inventory folder. Item entries are created lazily by name, so
    adding a new item type later requires no changes to this module.
]]

local InventoryHandler = {}

local function getInventoryFolder(player: Player): Folder
	return player:FindFirstChild("Inventory") :: Folder
end

--[[
    Ensures the player has an Inventory folder. Call once from PlayerAdded.
]]
function InventoryHandler.setupPlayer(player: Player): ()
	if getInventoryFolder(player) then
		return
	end

	local inventory = Instance.new("Folder")
	inventory.Name = "Inventory"
	inventory.Parent = player
end

local function getOrCreateItem(player: Player, itemName: string): IntValue
	local inventory = getInventoryFolder(player)
	local item = inventory:FindFirstChild(itemName) :: IntValue?
	if item then
		return item
	end

	item = Instance.new("IntValue")
	item.Name = itemName
	item.Value = 0
	item.Parent = inventory

	return item
end

--[[
    Adds amount to the player's count of itemName, creating the item entry
    if it doesn't exist yet. Returns the new total.
]]
function InventoryHandler.addItem(player: Player, itemName: string, amount: number): number
	local item = getOrCreateItem(player, itemName)
	item.Value += amount

	return item.Value
end

--[[
    Subtracts amount from the player's count of itemName. Returns false
    (no change made) if amount is greater than the current count.
]]
function InventoryHandler.removeItem(player: Player, itemName: string, amount: number): boolean
	local item = getOrCreateItem(player, itemName)
	if amount > item.Value then
		return false
	end

	item.Value -= amount

	return true
end

--[[
    Returns the player's current count of itemName, or 0 if the item entry
    doesn't exist yet.
]]
function InventoryHandler.getItem(player: Player, itemName: string): number
	local inventory = getInventoryFolder(player)
	local item = inventory:FindFirstChild(itemName) :: IntValue?

	return item and item.Value or 0
end

--[[
    Returns whether the player has at least amount (default 1) of itemName.
]]
function InventoryHandler.hasItem(player: Player, itemName: string, amount: number?): boolean
	return InventoryHandler.getItem(player, itemName) >= (amount or 1)
end

return InventoryHandler
