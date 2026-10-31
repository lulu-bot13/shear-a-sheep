--!strict

--[[
	Runs the server weather cycle (Clear spells broken up by Rain, Thunderstorm or Night) and replicates it
	through the workspace "Weather" and "WeatherEndsAt" attributes. Other handlers read the multipliers here.

	Location: ServerScriptService.Modules.Controllers.WeatherHandler
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)

--// Configs
local WEATHER_ATTRIBUTE = "Weather"
local ENDS_AT_ATTRIBUTE = "WeatherEndsAt"

--// State
local current = WeatherData.Clear
local pendingChange: thread? = nil -- the delay that ends the current weather
local random = Random.new()

local WeatherHandler = {}

WeatherHandler.HalloweenChanged = Signal.new() -- (halloween: boolean)

--// Helpers -------------------------------------------------------------------

local function getInfo(): WeatherData.WeatherInfo
	return WeatherData.Weathers[current] or WeatherData.Weathers[WeatherData.Clear]
end

local function pickEvent(): string?
	local total = 0
	for name, info in WeatherData.Weathers do
		if name ~= WeatherData.Clear then
			total += info.Weight
		end
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber() * total
	for name, info in WeatherData.Weathers do
		if name ~= WeatherData.Clear and info.Weight > 0 then
			roll -= info.Weight
			if roll <= 0 then
				return name
			end
		end
	end
	return nil
end

local function getClearSeconds(): number
	return random:NextNumber(WeatherData.MinClearSeconds, WeatherData.MaxClearSeconds)
end

local function advance()
	pendingChange = nil
	local nextWeather = if current == WeatherData.Clear then pickEvent() else nil
	WeatherHandler.setWeather(nextWeather or WeatherData.Clear)
end

--// Public API ------------------------------------------------------------------

function WeatherHandler.getWeather(): string
	return current
end

-- Halloween mode (Halloween-only sheep and abilities) is on while it's Night.
function WeatherHandler.isHalloween(): boolean
	return current == WeatherData.Halloween
end

function WeatherHandler.getRespawnMultiplier(): number
	return getInfo().RespawnMultiplier
end

function WeatherHandler.getLuckMultiplier(): number
	return getInfo().LuckMultiplier
end

-- Rolls whether a sheep spawning right now comes out Charged.
function WeatherHandler.rollCharged(): boolean
	local chance = getInfo().ChargedChance
	return chance > 0 and random:NextNumber() < chance
end

-- Switches the weather now (also the admin/test hook). Duration defaults to the weather's own; returns false for unknown names.
function WeatherHandler.setWeather(name: string, duration: number?): boolean
	local info = WeatherData.Weathers[name]
	if not info then
		return false
	end

	if pendingChange then
		task.cancel(pendingChange)
	end

	local seconds = duration or (if name == WeatherData.Clear then getClearSeconds() else info.Duration)
	local wasHalloween = WeatherHandler.isHalloween()
	current = name
	workspace:SetAttribute(WEATHER_ATTRIBUTE, name)
	workspace:SetAttribute(ENDS_AT_ATTRIBUTE, workspace:GetServerTimeNow() + seconds)
	pendingChange = task.delay(seconds, advance)
	if WeatherHandler.isHalloween() ~= wasHalloween then
		WeatherHandler.HalloweenChanged:Fire(WeatherHandler.isHalloween())
	end
	return true
end

--// Lifecycle -----------------------------------------------------------------------

function WeatherHandler.Start()
	WeatherHandler.setWeather(WeatherData.Clear)
end

return WeatherHandler
