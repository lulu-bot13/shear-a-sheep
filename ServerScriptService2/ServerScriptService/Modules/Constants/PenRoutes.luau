--!strict

--[[
	Lists which waypoints each pen's sheep walk through, by pen number, rebirths and spawn waypoint.
	Sheep visit only the listed waypoints, then the pen's own Entrance.

	Location: ServerScriptService.Modules.Constants.PenRoutes
]]--

export type Route = {
	rebirths: number,
	spawn: number?,
	waypoints: { string },
}

--[[
	Index is for the pen number
]]--
local ROUTES: { [number]: { Route } } = {
	[1] = { { rebirths = 1, waypoints = { "2" } } },
	[2] = { { rebirths = 1, waypoints = { "2" } } },
	[3] = { { rebirths = 3, waypoints = { "2", "3"} } },
	[4] = { { rebirths = 4, waypoints = { "2", "3", "4" } } },
	[5] = { { rebirths = 5, waypoints = { "2", "3", "4", "5" } } },
	[6] = { { rebirths = 6, waypoints = { "2", "3", "4", "5" } } },
}

local PenRoutes = {}

-- The waypoint names for this pen, rebirth count and spawn waypoint; a spawn-specific row beats a general one.
-- Below a pen's lowest `rebirths` the pen's first row is used, so its sheep never walk a straight line to the pen.
function PenRoutes.getWaypointNames(penNumber: number, rebirths: number, spawnIndex: number?): { string }
	local best: Route? = nil
	local lowest: Route? = nil
	for _, route in ROUTES[penNumber] or {} do
		if route.spawn and route.spawn ~= spawnIndex then
			continue
		end
		if not lowest or route.rebirths < lowest.rebirths then
			lowest = route
		end
		if rebirths < route.rebirths then
			continue
		end
		if not best or (route.spawn ~= nil and best.spawn == nil) or (route.spawn == best.spawn and route.rebirths >= best.rebirths) then
			best = route
		end
	end

	local chosen = best or lowest
	return if chosen then chosen.waypoints else {}
end

return PenRoutes
