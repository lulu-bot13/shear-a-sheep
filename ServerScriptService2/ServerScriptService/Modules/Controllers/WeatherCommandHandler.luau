--!strict

--[[
	/weather <name> [seconds] chat command: switches the weather now (Clear, Rain, Thunderstorm, Night), optionally for a set duration.
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.WeatherCommandHandler
]]--

--// Modules
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Configs
local PRIMARY_ALIAS = "/weather"
local SECONDARY_ALIAS = "/setweather"

local WeatherCommandHandler = {}

-- Case-insensitive lookup so "/weather rain" works.
local function findWeather(query: string): string?
	local lowered = string.lower(query)
	for name in WeatherData.Weathers do
		if string.lower(name) == lowered then
			return name
		end
	end
	return nil
end

local function onTriggered(speaker: Player, message: string)
	local nameText, secondsText = string.match(message, "^%S+%s+(%S+)%s*(%S*)")
	local weather = if nameText then findWeather(nameText) else nil
	if not weather then
		local names = {}
		for name in WeatherData.Weathers do
			table.insert(names, name)
		end
		warn(`WeatherCommandHandler: unknown weather "{nameText or ""}" (options: {table.concat(names, ", ")}).`)
		return
	end

	local seconds = tonumber(secondsText)
	if seconds and seconds <= 0 then
		seconds = nil
	end

	WeatherHandler.setWeather(weather, seconds)
	print(`WeatherCommandHandler: {speaker.Name} set the weather to {weather}.`)
end

--// Lifecycle -----------------------------------------------------------------------

function WeatherCommandHandler.Start()
	AdminCommands.register("WeatherCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
end

return WeatherCommandHandler
