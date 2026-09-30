--!strict

--[[
	Server-side (authoritative) data for the shear shop: what each shear costs and how it
	performs. The client has a matching display-only copy in ShearShopUIData - keep the
	speed / damage / price numbers in sync when tuning.

	id       matches the Tool's name in ReplicatedStorage.Assets.Shears
	price    money cost (the default shear is free, everyone starts with it)
	damage   damage of a x1.0 weak point (replaces ShearData.HitDamage for this player)
	speed    shearing tempo multiplier: shortens the pause between waves and speeds up the snip animation

	Order in the list = progression order: a player can only buy a shear that is further
	down the list than the one they hold, so nobody pays to downgrade.

	Location: ServerScriptService.Modules.Constants.ShearShopData
]]--

export type ShearInfo = {
	id: string,
	price: number,
	damage: number,
	speed: number,
}

local shearShopData = {}

shearShopData.DefaultShearId = "DefaultShear"

shearShopData.Shears = {
	{ id = "DefaultShear",   price = 0,     damage = 8,  speed = 1.0 },
	{ id = "SteelShears",    price = 300,   damage = 12, speed = 1.15 },
	{ id = "LargeShears",    price = 1200,  damage = 18, speed = 1.3 },
	{ id = "ElectricShears", price = 4000,  damage = 26, speed = 1.6 },
	{ id = "MasterShears",   price = 12000, damage = 40, speed = 2.0 },
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
