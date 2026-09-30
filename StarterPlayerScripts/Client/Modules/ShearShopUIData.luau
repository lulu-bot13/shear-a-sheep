--!strict

--[[
	Client-side display data for the shear shop UI: names, stats and prices as shown on the cards.
	The server (ServerScriptService.Modules.Constants.ShearShopData) is the authority - it decides
	what a purchase costs and what a shear does - so keep the speed / damage / price numbers here
	in sync with it when tuning.

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ShearShopUIData
]]--

export type ShearUI = {
	id: string, -- Tool name in ReplicatedStorage.Assets.Shears
	displayName: string,
	price: number,
	damage: number,
	speed: number,
}

local shearShopUIData = {}

-- In progression order (the card order in the shop, cheapest first).
shearShopUIData.Shears = {
	{ id = "DefaultShear",   displayName = "Basic Shear",     price = 0,     damage = 8,  speed = 1.0 },
	{ id = "SteelShears",    displayName = "Steel Shears",    price = 300,   damage = 12, speed = 1.15 },
	{ id = "LargeShears",    displayName = "Large Shears",    price = 1200,  damage = 18, speed = 1.3 },
	{ id = "ElectricShears", displayName = "Electric Shears", price = 4000,  damage = 26, speed = 1.6 },
	{ id = "MasterShears",   displayName = "Master Shears",   price = 12000, damage = 40, speed = 2.0 },
} :: { ShearUI }

--// Preview (the spinning 3D shear on each card)
shearShopUIData.SpinSpeed = 1.2 -- radians per second (about 5 seconds per full turn)
shearShopUIData.PreviewPitch = math.rad(20)
shearShopUIData.PreviewFieldOfView = 35

--// Purchase button colours
shearShopUIData.ButtonColors = {
	Ready = Color3.fromRGB(110, 220, 120),
	Poor = Color3.fromRGB(205, 120, 120),
	Equipped = Color3.fromRGB(255, 200, 70),
	Owned = Color3.fromRGB(160, 160, 165),
}

local rankById: { [string]: number } = {}
for index, info in shearShopUIData.Shears do
	rankById[info.id] = index
end

-- Position in the progression (1 = default); 0 for an unknown id.
function shearShopUIData.getRank(id: any): number
	return if type(id) == "string" then (rankById[id] or 0) else 0
end

-- 1500 -> "$1,500"
function shearShopUIData.formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. formatted:gsub("^,", "")
end

return shearShopUIData
