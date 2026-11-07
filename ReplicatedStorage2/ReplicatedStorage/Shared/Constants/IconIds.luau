--!strict

--[[
	Image ids for the currency icons used by both the client and the server, so no script hardcodes them.
	Location: ReplicatedStorage.Shared.Constants.IconIds
]]--

local iconIds = {
	Wool = "rbxassetid://136230905804958",
	Luck = "rbxassetid://119119538038200",
	Gem = "rbxassetid://83413919774646",
}

-- Width / height of the wool image; anything showing it gets a UIAspectRatioConstraint with this (see IconUtil).
iconIds.WoolAspectRatio = 1.121

return iconIds
