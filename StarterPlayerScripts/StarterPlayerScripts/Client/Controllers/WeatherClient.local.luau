--!strict

--[[
	Follows the server's workspace "Weather" / "WeatherEndsAt" attributes: blends the scene's look, shows a small
	weather + time-left in Main.Weather, announces changes and throws lightning (at random and onto newly Charged sheep) in storms.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.WeatherClient
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Modules
local chargedSheep = require(script.Parent.Parent.Modules.ChargedSheep)
local lightning = require(script.Parent.Parent.Modules.Lightning)
local weatherEffects = require(script.Parent.Parent.Modules.WeatherEffects)

--// Configs
local WEATHER_ATTRIBUTE = "Weather"
local ENDS_AT_ATTRIBUTE = "WeatherEndsAt"
local STORM = "Thunderstorm"
local CLEAR = "Clear"

local WEATHER_TEXT: { [string]: { label: string, announcement: string, color: Color3 } } = {
	Clear = { label = "☀️ Clear", announcement = "The skies have cleared", color = Color3.fromRGB(255, 225, 120) },
	Rain = { label = "🌧️ Rain", announcement = "It's raining! Sheep regrow faster", color = Color3.fromRGB(140, 195, 255) },
	Thunderstorm = {
		label = "⛈️ Thunderstorm",
		announcement = "Thunderstorm! Charged sheep give 3x wool",
		color = Color3.fromRGB(150, 210, 255),
	},
	Night = { label = "🌙 Night", announcement = "Night falls... rarer sheep roam", color = Color3.fromRGB(190, 180, 255) },
}

local LABEL_TIMEOUT = 10 -- seconds to wait for the Studio-built Main.Weather label
local ANNOUNCE_POSITION = UDim2.fromScale(0.5, 0.18)
local ANNOUNCE_SECONDS = 3
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TIMER_TICK = 0.5

local STRIKE_MIN_SECONDS = 4 -- random lightning while a storm lasts
local STRIKE_MAX_SECONDS = 11
local NEAR_STRIKE_CHANCE = 0.45 -- the rest are distant flashes with no bolt
local NEAR_STRIKE_MIN_DISTANCE = 60
local NEAR_STRIKE_MAX_DISTANCE = 160
local SHEEP_STRIKE_DISTANCE = 160 -- newly Charged sheep this close to the camera get struck
local SHEEP_STRIKE_GAP = 0.6 -- seconds between sheep strikes, so a full refill isn't a strobe

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WeatherGui"
gui.ResetOnSpawn = false
gui.Parent = playerGui

-- The Studio-built label (Main.Weather) shows the weather name + time left.
local weatherLabel: TextLabel? = nil
do
	local main = playerGui:WaitForChild("Main", LABEL_TIMEOUT)
	local found = if main then main:WaitForChild("Weather", LABEL_TIMEOUT) else nil
	if found and found:IsA("TextLabel") then
		weatherLabel = found
	else
		warn("WeatherClient: PlayerGui.Main.Weather TextLabel not found, weather timer hidden")
	end
end

local announcement = Instance.new("TextLabel")
announcement.Name = "Announcement"
announcement.AnchorPoint = Vector2.new(0.5, 0.5)
announcement.Position = ANNOUNCE_POSITION
announcement.Size = UDim2.fromScale(0.6, 0.07)
announcement.BackgroundTransparency = 1
announcement.Font = Enum.Font.GothamBlack
announcement.TextScaled = true
announcement.Visible = false
announcement.Parent = gui

local announceStroke = Instance.new("UIStroke")
announceStroke.Color = Color3.fromRGB(20, 24, 35)
announceStroke.Thickness = 3
announceStroke.Parent = announcement

local announceScale = Instance.new("UIScale")
announceScale.Parent = announcement

--// State
local current = CLEAR
local weatherToken = 0
local announceToken = 0
local lastSheepStrike = 0
local random = Random.new()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

--// Weather label + announcement -------------------------------------------------------

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function updateLabel()
	local label = weatherLabel
	if not label then
		return
	end
	if current == CLEAR then
		label.Visible = false
		return
	end
	local text = WEATHER_TEXT[current] or WEATHER_TEXT.Clear
	local endsAt = workspace:GetAttribute(ENDS_AT_ATTRIBUTE)
	if type(endsAt) == "number" then
		label.Text = `{text.label}  {formatTime(endsAt - workspace:GetServerTimeNow())}`
	else
		label.Text = text.label
	end
	label.Visible = true
end

local function announce(weather: string)
	local text = WEATHER_TEXT[weather]
	if not text then
		return
	end
	announceToken += 1
	local token = announceToken

	announcement.Text = text.announcement
	announcement.TextColor3 = text.color
	announcement.TextTransparency = 0
	announceStroke.Transparency = 0
	announcement.Visible = true
	announceScale.Scale = 0.3
	tweenService:Create(announceScale, POP_TWEEN, { Scale = 1 }):Play()

	task.delay(ANNOUNCE_SECONDS, function()
		if token ~= announceToken then
			return
		end
		tweenService:Create(announceStroke, FADE_TWEEN, { Transparency = 1 }):Play()
		local fade = tweenService:Create(announcement, FADE_TWEEN, { TextTransparency = 1 })
		fade.Completed:Once(function(playbackState: Enum.PlaybackState)
			if token == announceToken and playbackState == Enum.PlaybackState.Completed then
				announcement.Visible = false
			end
		end)
		fade:Play()
	end)
end

--// Lightning -------------------------------------------------------------------

local function findGround(position: Vector3): Vector3?
	local camera = workspace.CurrentCamera
	local character = players.LocalPlayer.Character
	local exclude: { Instance } = {}
	if camera then
		table.insert(exclude, camera)
	end
	if character then
		table.insert(exclude, character)
	end
	rayParams.FilterDescendantsInstances = exclude

	local result = workspace:Raycast(position + Vector3.new(0, 200, 0), Vector3.new(0, -400, 0), rayParams)
	return if result then result.Position else nil
end

local function randomStrike()
	local camera = workspace.CurrentCamera
	if not camera or random:NextNumber() > NEAR_STRIKE_CHANCE then
		lightning.flash()
		return
	end

	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(NEAR_STRIKE_MIN_DISTANCE, NEAR_STRIKE_MAX_DISTANCE)
	local around = camera.CFrame.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
	local ground = findGround(around)
	if ground then
		lightning.strike(ground)
	else
		lightning.flash()
	end
end

local function runStorm(token: number)
	while true do
		task.wait(random:NextNumber(STRIKE_MIN_SECONDS, STRIKE_MAX_SECONDS))
		if token ~= weatherToken then
			return
		end
		randomStrike()
	end
end

local function strikeSheep(sheep: Model)
	local camera = workspace.CurrentCamera
	local root = sheep:FindFirstChild("HumanoidRootPart")
	if current ~= STORM or not camera or not root or not root:IsA("BasePart") then
		return
	end
	local now = os.clock()
	if now - lastSheepStrike < SHEEP_STRIKE_GAP then
		return
	end
	if (root.Position - camera.CFrame.Position).Magnitude > SHEEP_STRIKE_DISTANCE then
		return
	end
	lastSheepStrike = now
	lightning.strike(root.Position)
end

--// Weather changes -------------------------------------------------------------

local function readWeather(): string
	local weather = workspace:GetAttribute(WEATHER_ATTRIBUTE)
	return if type(weather) == "string" and WEATHER_TEXT[weather] then weather else CLEAR
end

local function setWeather(weather: string, instant: boolean)
	if weather == current and not instant then
		return
	end
	current = weather
	weatherToken += 1

	weatherEffects.apply(weather, instant)
	updateLabel()
	if not instant then
		announce(weather)
	end
	if weather == STORM then
		task.spawn(runStorm, weatherToken)
	end
end

-- Joining mid-weather snaps straight to it, with no announcement.
setWeather(readWeather(), true)
chargedSheep.start(strikeSheep)

workspace:GetAttributeChangedSignal(WEATHER_ATTRIBUTE):Connect(function()
	setWeather(readWeather(), false)
end)
workspace:GetAttributeChangedSignal(ENDS_AT_ATTRIBUTE):Connect(updateLabel)

while true do
	task.wait(TIMER_TICK)
	if current ~= CLEAR then
		updateLabel()
	end
end
