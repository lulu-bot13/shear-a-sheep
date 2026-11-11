--!strict

--[[
	Client-side display data for the shear shop UI: names, stats and sheep costs as shown on the cards.
	The server (ServerScriptService.Modules.Constants.ShearData) is the authority - it decides
	what a shear costs and what it does - so keep the damage / range / sheep numbers here
	in sync with it when tuning.

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ShearShopUIData
]]--

export type ShearUI = {
	id: string, -- Tool name in ReplicatedStorage.Assets.Shears
	displayName: string,
	sheepRequired: number, -- lifetime sheep sheared to unlock it
	damage: number, -- matches ShearData
	range: number,
}

local shearShopUIData = {}

-- In progression order (the card order in the shop, cheapest first).
shearShopUIData.Shears = {
	{ id = "DefaultShear",   displayName = "Basic Shear",     sheepRequired = 0,    damage = 20, range = 6 },
	{ id = "SteelShears",    displayName = "Steel Shears",    sheepRequired = 3,    damage = 26, range = 7.5 },
	{ id = "LargeShears",    displayName = "Large Shears",    sheepRequired = 300,  damage = 34, range = 9 },
	{ id = "ElectricShears", displayName = "Electric Shears", sheepRequired = 1500, damage = 45, range = 11 },
	{ id = "MasterShears",   displayName = "Master Shears",   sheepRequired = 4500, damage = 60, range = 13 },
} :: { ShearUI }

--// Preview (the spinning 3D shear on each card)
shearShopUIData.SpinSpeed = 1.2 -- radians per second (about 5 seconds per full turn)
shearShopUIData.PreviewPitch = math.rad(20)
shearShopUIData.PreviewFieldOfView = 35

--// Purchase button text and ImageColor3, by card state
shearShopUIData.ButtonStyles = {
	locked = { text = "Locked", color = Color3.fromRGB(95, 95, 105) },
	ready = { text = "Unlock", color = Color3.fromRGB(110, 220, 120) },
	owned = { text = "Equip", color = Color3.fromRGB(80, 160, 255) },
	equipped = { text = "Unequip", color = Color3.fromRGB(235, 85, 85) },
	equippedDefault = { text = "Equipped", color = Color3.fromRGB(255, 200, 70) }, -- the default shear can't be unequipped
}

local rankById: { [string]: number } = {}
for index, info in shearShopUIData.Shears do
	rankById[info.id] = index
end

-- Position in the progression (1 = default); 0 for an unknown id.
function shearShopUIData.getRank(id: any): number
	return if type(id) == "string" then (rankById[id] or 0) else 0
end

local function formatWithCommas(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- 1500 -> "Sheep: 1,500"
function shearShopUIData.formatSheep(amount: number): string
	return "Sheep: " .. formatWithCommas(amount)
end

return shearShopUIData
