--!strict

--[[
	Gem tuning: how often a sheep shorn bare drops Gems, the rare currency, and how many.

	Location: ServerScriptService.Modules.Constants.GemData
]]--

local gemData = {}

gemData.SheepDropChance = 1 / 1000 -- rolled once for every sheep shorn bare
gemData.SheepDropAmount = 1

return gemData
