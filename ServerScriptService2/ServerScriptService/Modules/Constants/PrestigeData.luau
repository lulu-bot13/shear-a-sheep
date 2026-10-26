--!strict

--[[
	Prestige tuning: how many rebirths a Prestige needs, and the permanent wool multiplier and luck-factor boost each one gives.

	Location: ServerScriptService.Modules.Constants.PrestigeData
]]--

local prestigeData = {}

prestigeData.REQUIRED_REBIRTHS = 10
prestigeData.PRESTIGE_LUCK_PER = 0.15 -- luck factor is multiplied by 1 + this * prestiges
prestigeData.PRESTIGE_WOOL_MULTIPLIER_PER = 0.5 -- wool multiplier = 1 + this * prestiges

function prestigeData.getWoolMultiplier(prestiges: number): number
	return 1 + prestigeData.PRESTIGE_WOOL_MULTIPLIER_PER * math.max(prestiges, 0)
end

function prestigeData.getLuckMultiplier(prestiges: number): number
	return 1 + prestigeData.PRESTIGE_LUCK_PER * math.max(prestiges, 0)
end

return prestigeData
