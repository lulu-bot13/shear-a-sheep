--!strict

--[[
	Every shear's wool price, sheep-sheared unlock, damage per swing and hitbox range, plus the swing and shop settings.
	The client's display copy lives in ShearShopUIData - keep the prices and stats in sync.

	Location: ServerScriptService.Modules.Constants.ShearData
]]--

export type ShearInfo = {
	id: string, -- matches the Tool's name in ReplicatedStorage.Assets.Shears
	price: number, -- wool
	sheepRequired: number, -- lifetime sheep sheared before it can be bought
	damage: number, -- wool taken off every sheep in range per swing
	range: number, -- hitbox radius in studs, measured flat from the character
}

local shearData = {}

--// Shears (list order = progression order) ----------------------------------------------

shearData.DefaultShearId = "DefaultShear"

--[[
	sheepRequired is lifetime (rebirths and Prestiges keep it). A player shears ~15-30 sheep/min at first, ~50 by
	minute 5 and hits the farm's spawn cap (40-86/min) by about minute 15. Minutes of active / casual play to unlock:
	Steel ~2 / 4    Large ~6 / 11    Electric ~22 / 35 (before the first Prestige)    Master ~60 / 70
]]
shearData.Shears = {
	{ id = "DefaultShear",   price = 0,     sheepRequired = 0,    damage = 20, range = 6 },
	{ id = "SteelShears",    price = 300,   sheepRequired = 50,   damage = 26, range = 7.5 },
	{ id = "LargeShears",    price = 1200,  sheepRequired = 300,  damage = 34, range = 9 },
	{ id = "ElectricShears", price = 4000,  sheepRequired = 1500, damage = 45, range = 11 },
	{ id = "MasterShears",   price = 12000, sheepRequired = 4500, damage = 60, range = 13 },
} :: { ShearInfo }

--// Swinging ------------------------------------------------------------------------------

shearData.SwingCooldown = 0.35 -- seconds between swings
shearData.RangeTolerance = 1.5 -- extra studs the server allows for sheep that moved while the swing travelled
shearData.MaxHeightDifference = 6 -- studs a sheep may be above or below the character and still be hit

--// Shop ----------------------------------------------------------------------------------

shearData.PurchaseRange = 12 -- studs outside the shop hitbox a player may still buy (the client closes the shop at 6)

--// Lookups -------------------------------------------------------------------------------

local indexById: { [string]: number } = {}
for index, info in shearData.Shears do
	indexById[info.id] = index
end

function shearData.get(id: any): ShearInfo?
	if type(id) ~= "string" then
		return nil
	end
	local index = indexById[id]
	return if index then shearData.Shears[index] else nil
end

return shearData
