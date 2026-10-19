--!strict

--[[
	Tuning for the sheep farm on each plot: capacity, how fast sheep refill and how they wander the SheepArea.

	Location: ServerScriptService.Modules.Constants.FarmData
]]--

local farmData = {}

--// Capacity ------------------------------------------------------------------------------

farmData.StartingMaxSheep = 3 -- how many sheep a brand new (or reborn) farm holds
farmData.MaxSheepCap = 40 -- hard limit, however many capacity upgrades are bought

--// Spawning ------------------------------------------------------------------------------

farmData.SpawnInterval = 1.5 -- seconds between new sheep while the farm is below capacity
farmData.SpawnDropHeight = 3 -- studs above the ground a sheep appears at

--// Wandering -----------------------------------------------------------------------------

farmData.Wander = {
	MinWalkSpeed = 4, -- each walk picks a speed between these two
	MaxWalkSpeed = 6,
	MinIdleSeconds = 1.5, -- pause after arriving before the next walk
	MaxIdleSeconds = 4,
	MinDistance = 6, -- studs per walk
	MaxDistance = 18,
	EdgePadding = 2, -- studs kept clear of the SheepArea's edges
	TickSeconds = 0.25, -- how often the wander loop checks every sheep
	ShearHoldSeconds = 3, -- a sheared sheep stands still this long after the last snip before wandering again
}

--// Plot instance names -------------------------------------------------------------------

farmData.SheepAreaName = "SheepArea"
farmData.CenterName = "Center"
farmData.CapacityGuiName = "SheepCapacity"

return farmData
