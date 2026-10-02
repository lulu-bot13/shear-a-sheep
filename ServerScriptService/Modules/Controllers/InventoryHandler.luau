--!strict

--[[
	Per-player inventory stored as IntValues under Player.Inventory (so it replicates to the owner).

		Inventory/<ItemName>          stackable items such as "Wool"
		Inventory/Pens/<PenType>      owned pens, by template name in ReplicatedStorage.Assets.Models.Pens

	A pen entry only exists while the player owns at least one of that pen type.
	The pen functions don't know which pen types are valid; callers check that.

	Location: ServerScriptService.Modules.Controllers.InventoryHandler
]]--

--// Configs
local INVENTORY_NAME = "Inventory"
local PENS_FOLDER_NAME = "Pens"

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

local function getPensFolder(player: Player): Folder
	return getOrCreateFolder(getInventoryFolder(player), PENS_FOLDER_NAME)
end

-- Ensures the player has an Inventory folder (with its Pens folder).
function InventoryHandler.setupPlayer(player: Player): ()
	getPensFolder(player)
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

--// Pens ----------------------------------------------------------------------------

-- Adds pens of a type (default 1) to the player's inventory and returns how many they now own.
function InventoryHandler.addPen(player: Player, penType: string, amount: number?): number
	local count = math.floor(amount or 1)
	local pens = getPensFolder(player)
	local existing = pens:FindFirstChild(penType)

	if existing and existing:IsA("IntValue") then
		existing.Value += math.max(count, 0)
		return existing.Value
	end

	if count <= 0 then
		return 0
	end

	local entry = Instance.new("IntValue")
	entry.Name = penType
	entry.Value = count
	entry.Parent = pens

	return count
end

-- Takes pens of a type (default 1) out of the inventory; false if the player doesn't own enough.
function InventoryHandler.removePen(player: Player, penType: string, amount: number?): boolean
	local count = math.floor(amount or 1)
	local existing = getPensFolder(player):FindFirstChild(penType)
	if count <= 0 or not existing or not existing:IsA("IntValue") or existing.Value < count then
		return false
	end

	existing.Value -= count
	if existing.Value <= 0 then
		existing:Destroy()
	end

	return true
end

-- How many pens of a type the player owns, or 0.
function InventoryHandler.getPenCount(player: Player, penType: string): number
	local existing = getPensFolder(player):FindFirstChild(penType)

	return if existing and existing:IsA("IntValue") then existing.Value else 0
end

-- Whether the player owns at least amount (default 1) of a pen type.
function InventoryHandler.hasPen(player: Player, penType: string, amount: number?): boolean
	return InventoryHandler.getPenCount(player, penType) >= (amount or 1)
end

-- Returns a copy of the pen inventory: { [penType] = count }.
function InventoryHandler.getPens(player: Player): { [string]: number }
	local owned: { [string]: number } = {}
	for _, entry in getPensFolder(player):GetChildren() do
		if entry:IsA("IntValue") and entry.Value > 0 then
			owned[entry.Name] = entry.Value
		end
	end

	return owned
end

return InventoryHandler
