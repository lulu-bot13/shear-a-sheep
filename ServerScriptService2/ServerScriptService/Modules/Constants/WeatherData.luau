--!strict

--[[
	Tuning for the server weather cycle: how long Clear lasts between events, how often each event is picked and what it changes.

	Location: ServerScriptService.Modules.Constants.WeatherData
]]--

export type WeatherInfo = {
	Duration: number, -- seconds the event lasts (Clear uses the range below instead)
	Weight: number, -- chance of being picked after a Clear spell, relative to the other events
	RespawnMultiplier: number, -- multiplies the seconds between sheep refills
	LuckMultiplier: number, -- multiplies the spawn roll's luck factor, so each rarity tier up gets this much likelier again
	ChargedChance: number, -- chance a sheep spawned during it is Charged
}

local weatherData = {}

weatherData.Clear = "Clear"
weatherData.Halloween = "Night" -- Halloween mode runs while this weather is up (the client checks the same name)

--// Cycle ---------------------------------------------------------------------------------

weatherData.MinClearSeconds = 240 -- Clear spell between two events
weatherData.MaxClearSeconds = 480

--// Charged sheep -------------------------------------------------------------------------

weatherData.ChargedAttribute = "Charged"
weatherData.ChargedWoolMultiplier = 3

--// Weathers ------------------------------------------------------------------------------

weatherData.Weathers = {
	Clear = {
		Duration = 0,
		Weight = 0,
		RespawnMultiplier = 1,
		LuckMultiplier = 1,
		ChargedChance = 0,
	},
	Rain = {
		Duration = 120,
		Weight = 4,
		RespawnMultiplier = 0.5,
		LuckMultiplier = 1,
		ChargedChance = 0,
	},
	Thunderstorm = {
		Duration = 90,
		Weight = 2,
		RespawnMultiplier = 0.5,
		LuckMultiplier = 1,
		ChargedChance = 0.25,
	},
	Night = {
		Duration = 150,
		Weight = 3,
		RespawnMultiplier = 1,
		LuckMultiplier = 1.25,
		ChargedChance = 0,
	},
} :: { [string]: WeatherInfo }

return weatherData
