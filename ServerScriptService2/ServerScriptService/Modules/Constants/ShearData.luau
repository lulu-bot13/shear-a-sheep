--!strict

--[[
	Every shear's sheep-sheared cost, damage per swing and hitbox range, plus the swing and shop settings.
	The client's display copy lives in ShearShopUIData - keep the costs and stats in sync.

	Location: ServerScriptService.Modules.Constants.ShearData
]]--

export type ShearInfo = {
	id: string, -- matches the Tool's name in ReplicatedStorage.Assets.Shears
	sheepRequired: number, -- lifetime sheep sheared to unlock it (the count is not spent)
	damage: number, -- wool taken off every sheep in range per swing
	range: number, -- hitbox radius in studs, measured flat from the character
}

local shearData = {}

--// Shears (list order = shop card order) -------------------------------------------------

shearData.DefaultShearId = "DefaultShear"

--[[
	sheepRequired is lifetime (rebirths and Prestiges keep it). Steel unlocks after the tutorial's first 3 sheep and buying it
	is a tutorial step. Past that the farm's refill (10 sheep/min at first, ~94/min at Faster Respawn 10) paces the unlocks.
]]
shearData.Shears = {
	{ id = "DefaultShear",   sheepRequired = 0,    damage = 20, range = 6 },
	{ id = "SteelShears",    sheepRequired = 3,    damage = 26, range = 7.5 },
	{ id = "RoyalShear",     sheepRequired = 750,  damage = 40, range = 10 }, -- shown right after the basic shears, ahead of its cost order
	{ id = "LargeShears",    sheepRequired = 300,  damage = 34, range = 9 },
	{ id = "ElectricShears", sheepRequired = 1500, damage = 45, range = 11 },
	{ id = "MasterShears",   sheepRequired = 4500, damage = 60, range = 13 },
	{ id = "ShadowShear",    sheepRequired = 9000, damage = 75, range = 14 },
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
