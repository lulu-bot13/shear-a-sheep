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
	tier: string, -- key in TierColors: the card Background's ImageColor3
}

local shearShopUIData = {}

-- In card order (matches ShearData). Royal sits right after the basic shears even though it costs more than Large.
shearShopUIData.Shears = {
	{ id = "DefaultShear",   displayName = "Basic Shear",     sheepRequired = 0,    damage = 20, range = 6,   tier = "basic" },
	{ id = "SteelShears",    displayName = "Steel Shears",    sheepRequired = 3,    damage = 26, range = 7.5, tier = "basic" },
	{ id = "RoyalShear",     displayName = "Royal Shears",    sheepRequired = 750,  damage = 40, range = 10,  tier = "royal" },
	{ id = "LargeShears",    displayName = "Large Shears",    sheepRequired = 300,  damage = 34, range = 9,   tier = "rare" },
	{ id = "ElectricShears", displayName = "Electric Shears", sheepRequired = 1500, damage = 45, range = 11,  tier = "rare" },
	{ id = "MasterShears",   displayName = "Master Shears",   sheepRequired = 4500, damage = 60, range = 13,  tier = "rare" },
	{ id = "ShadowShear",    displayName = "Shadow Shears",   sheepRequired = 9000, damage = 75, range = 14,  tier = "rare" },
} :: { ShearUI }

--// Card Background ImageColor3 by tier (basic keeps the Template's own color)
shearShopUIData.TierColors = {
	rare = Color3.fromRGB(85, 170, 255),
	royal = Color3.fromRGB(255, 200, 90),
} :: { [string]: Color3 }

--// Preview (the spinning 3D shear on each card)
shearShopUIData.SpinSpeed = 1.2 -- radians per second (about 5 seconds per full turn)
shearShopUIData.PreviewPitch = math.rad(20)
shearShopUIData.PreviewFieldOfView = 35

--// Purchase button text and ImageColor3, by card state
shearShopUIData.ButtonStyles = {
	locked = { text = "Locked", color = Color3.fromRGB(95, 95, 105) },
	ready = { text = "Unlock", color = Color3.fromRGB(110, 220, 120) },
	owned = { text = "Equip", color = Color3.fromRGB(110, 220, 120) },
	equipped = { text = "Unequip", color = Color3.fromRGB(235, 85, 85) },
	equippedDefault = { text = "Equipped", color = Color3.fromRGB(95, 95, 105) }, -- the default shear can't be unequipped
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
