--!strict

--[[
	Gem tuning: how often a sheep shorn bare drops Gems, the rare currency, and how many.

	Location: ServerScriptService.Modules.Constants.GemData
]]--

local gemData = {}

gemData.SheepDropChance = 1 / 40 -- rolled once for every sheep shorn bare; paired with AbilityData.RollCost
gemData.SheepDropAmount = 1

return gemData
