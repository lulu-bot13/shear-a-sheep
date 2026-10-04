--[[
	Tuning for automated shearing (the pen worker). The manual shearing mini-game is tuned in
	ReplicatedStorage.Shared.Constants.ShearTimingData.

	Location: ServerScriptService.Modules.Constants.ShearData
]]--

local shearData = {}

-- Worker (automation) damage per tick.
shearData.Default = {
	name = "Basic Shear",
	damage = 25,
}

return shearData
