--!strict

--[[
	Server-side (authoritative) data for the shear shop: what each shear costs and how it changes the
	shearing mini-game. The client has a matching display-only copy in ShearShopUIData - keep the
	numbers and prices in sync when tuning.

	id                matches the Tool's name in ReplicatedStorage.Assets.Shears
	price             money cost (the default shear is free, everyone starts with it)
	damageMultiplier  scales the wool every hit takes off
	zoneScale         scales the sweet spot (and the zones around it): bigger = easier to hit
	cursorSpeed       scales how fast the timing cursor moves: faster shearing, but harder timing

	See ShearTimingData.ShearStats. Order in the list = progression order: a player can only buy a
	shear that is further down the list than the one they hold, so nobody pays to downgrade.

	Location: ServerScriptService.Modules.Constants.ShearShopData
]]--

export type ShearInfo = {
	id: string,
	price: number,
	damageMultiplier: number,
	zoneScale: number,
	cursorSpeed: number,
}

local shearShopData = {}

shearShopData.DefaultShearId = "DefaultShear"

shearShopData.Shears = {
	{ id = "DefaultShear",   price = 0,     damageMultiplier = 1.0,  zoneScale = 1.0,  cursorSpeed = 1.0 },
	{ id = "SteelShears",    price = 300,   damageMultiplier = 1.1,  zoneScale = 1.12, cursorSpeed = 1.04 },
	{ id = "LargeShears",    price = 1200,  damageMultiplier = 1.2,  zoneScale = 1.22, cursorSpeed = 1.06 },
	{ id = "ElectricShears", price = 4000,  damageMultiplier = 1.35, zoneScale = 1.32, cursorSpeed = 1.1 },
	{ id = "MasterShears",   price = 12000, damageMultiplier = 1.6,  zoneScale = 1.45, cursorSpeed = 1.12 },
} :: { ShearInfo }

-- How far (studs) from the shop prompt a player may still buy.
shearShopData.PurchaseRange = 25

shearShopData.ShopPromptTag = "ShearShop"

local indexById: { [string]: number } = {}
for index, info in shearShopData.Shears do
	indexById[info.id] = index
end

function shearShopData.get(id: any): ShearInfo?
	if type(id) ~= "string" then
		return nil
	end
	local index = indexById[id]
	return if index then shearShopData.Shears[index] else nil
end

-- Position in the progression (1 = default); 0 for an unknown id.
function shearShopData.getRank(id: any): number
	return if type(id) == "string" then (indexById[id] or 0) else 0
end

return shearShopData
