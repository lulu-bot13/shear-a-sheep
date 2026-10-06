--!strict

--[[
	Per-player inventory stored as IntValues under Player.Inventory (so it replicates to the owner).

		Inventory/<ItemName>          stackable items such as "Wool"

	Location: ServerScriptService.Modules.Controllers.InventoryHandler
]]--

--// Configs
local INVENTORY_NAME = "Inventory"

local InventoryHandler = {}

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getInventoryFolder(player: Player): Folder
	return getOrCreateFolder(player, INVENTORY_NAME)
end

-- Ensures the player has an Inventory folder.
function InventoryHandler.setupPlayer(player: Player): ()
	getInventoryFolder(player)
end

local function getOrCreateItem(player: Player, itemName: string): IntValue
	local inventory = getInventoryFolder(player)
	local existing = inventory:FindFirstChild(itemName)
	if existing and existing:IsA("IntValue") then
		return existing
	end

	local item = Instance.new("IntValue")
	item.Name = itemName
	item.Value = 0
	item.Parent = inventory

	return item
end

-- Adds to the player's count of an item and returns the new total.
function InventoryHandler.addItem(player: Player, itemName: string, amount: number): number
	local item = getOrCreateItem(player, itemName)
	item.Value += amount

	return item.Value
end

-- Subtracts from an item's count; returns false if the player doesn't have enough.
function InventoryHandler.removeItem(player: Player, itemName: string, amount: number): boolean
	local item = getOrCreateItem(player, itemName)
	if amount > item.Value then
		return false
	end

	item.Value -= amount

	return true
end

-- Returns the player's count of an item, or 0.
function InventoryHandler.getItem(player: Player, itemName: string): number
	local item = getInventoryFolder(player):FindFirstChild(itemName)

	return if item and item:IsA("IntValue") then item.Value else 0
end

-- Returns whether the player has at least amount (default 1) of an item.
function InventoryHandler.hasItem(player: Player, itemName: string, amount: number?): boolean
	return InventoryHandler.getItem(player, itemName) >= (amount or 1)
end

return InventoryHandler
