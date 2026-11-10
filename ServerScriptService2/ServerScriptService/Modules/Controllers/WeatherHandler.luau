--!strict

--[[
	Runs the server weather cycle (Clear spells broken up by Rain, Thunderstorm or Night) through the workspace "Weather" /
	"WeatherEndsAt" attributes, keeps 2-5 min between notable events and publishes the next one as "NextEventName" / "NextEventAt".

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
local NEXT_NAME_ATTRIBUTE = "NextEventName"
local NEXT_AT_ATTRIBUTE = "NextEventAt"

type Scheduled = { name: string, at: number }

--// State
local current = WeatherData.Clear
local endsAt = 0 -- server time the current weather ends
local pendingChange: thread? = nil -- the delay that ends the current weather
local upcoming: string? = nil -- the event weather that starts after the next (or current) Clear spell
local upcomingAt = 0
local plannedClear = 0 -- seconds of the Clear spell after the current event
local holdUntil = 0 -- the next event weather starts no earlier than this (a King Sheep arriving)
local lastNotableAt = 0 -- server time the last notable event started
local scheduled: { [string]: Scheduled } = {} -- other events (Reaper raid, King Sheep) by source
local random = Random.new()

local WeatherHandler = {}

WeatherHandler.HalloweenChanged = Signal.new() -- (halloween: boolean)
WeatherHandler.WeatherChanged = Signal.new() -- (weather: string)

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

-- The Clear spell starting now: its planned length, kept MinEventGap..MaxEventGap after the last notable event and past holdUntil.
local function getClearDuration(now: number): number
	local planned = if plannedClear > 0 then plannedClear else getClearSeconds()
	local finish = math.clamp(now + planned, lastNotableAt + WeatherData.MinEventGap, lastNotableAt + WeatherData.MaxEventGap)
	finish = math.max(finish, holdUntil)
	return math.max(finish - now, WeatherData.MinClearFloor)
end

-- The soonest of the next event weather and the scheduled events.
local function publishNextEvent()
	local now = workspace:GetServerTimeNow()
	local name: string? = if upcoming and upcomingAt > now then upcoming else nil
	local at: number? = if name then upcomingAt else nil
	for _, entry in scheduled do
		if entry.at > now and (not at or entry.at < at) then
			name, at = entry.name, entry.at
		end
	end
	workspace:SetAttribute(NEXT_NAME_ATTRIBUTE, name or "")
	workspace:SetAttribute(NEXT_AT_ATTRIBUTE, at)
end

local function advance()
	pendingChange = nil
	local nextWeather = if current == WeatherData.Clear then upcoming or pickEvent() else nil
	WeatherHandler.setWeather(nextWeather or WeatherData.Clear)
end

local function scheduleEnd(seconds: number)
	if pendingChange then
		task.cancel(pendingChange)
	end
	endsAt = workspace:GetServerTimeNow() + seconds
	workspace:SetAttribute(ENDS_AT_ATTRIBUTE, endsAt)
	pendingChange = task.delay(seconds, advance)
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

	local now = workspace:GetServerTimeNow()
	local isClear = name == WeatherData.Clear
	local seconds = duration or (if isClear then getClearDuration(now) else info.Duration)
	if not isClear then
		lastNotableAt = now
	end

	local wasHalloween = WeatherHandler.isHalloween()
	current = name
	workspace:SetAttribute(WEATHER_ATTRIBUTE, name)
	scheduleEnd(seconds)

	upcoming = pickEvent()
	if isClear then
		plannedClear = 0
		upcomingAt = endsAt
	else
		plannedClear = math.max(getClearSeconds(), holdUntil - endsAt)
		upcomingAt = endsAt + plannedClear
	end
	publishNextEvent()

	WeatherHandler.WeatherChanged:Fire(name)
	if WeatherHandler.isHalloween() ~= wasHalloween then
		WeatherHandler.HalloweenChanged:Fire(WeatherHandler.isHalloween())
	end
	return true
end

-- Something notable (a King Sheep arriving) started now; the next event weather keeps its distance from it.
function WeatherHandler.markNotable()
	lastNotableAt = workspace:GetServerTimeNow()
end

-- Pushes the next event weather back to at least `at` (server time), stretching the Clear spell before it.
function WeatherHandler.delayNextWeather(at: number)
	holdUntil = math.max(holdUntil, at)
	if current == WeatherData.Clear then
		if endsAt < at then
			scheduleEnd(at - workspace:GetServerTimeNow())
			upcomingAt = endsAt
		end
	elseif upcomingAt < at then
		plannedClear = at - endsAt
		upcomingAt = at
	end
	publishNextEvent()
end

-- Adds (or with nil, removes) an event from `source` that the next-event countdown should consider.
function WeatherHandler.setScheduled(source: string, name: string?, at: number?)
	scheduled[source] = if name and at then { name = name, at = at } else nil
	publishNextEvent()
end

--// Lifecycle -----------------------------------------------------------------------

function WeatherHandler.Start()
	lastNotableAt = workspace:GetServerTimeNow()
	WeatherHandler.setWeather(WeatherData.Clear)
end

return WeatherHandler
