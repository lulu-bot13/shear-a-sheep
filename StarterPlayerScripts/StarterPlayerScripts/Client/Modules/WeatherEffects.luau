--!strict

--[[
	Local look of each weather: blends the Lighting, a colour grade and the Terrain clouds, and runs the rain,
	fireflies and looping ambience. Clear is whatever the place was built with.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.WeatherEffects
]]--

--// Services
local lighting = game:GetService("Lighting")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Configs
local TRANSITION_SECONDS = 6

local RAIN_TEXTURE = "rbxassetid://131193008859152" -- a thin vertical streak; empty uses the default particle
local RAIN_SOUND_ID = "" -- looping rain; empty plays no sound
local NIGHT_SOUND_ID = "" -- looping crickets / night ambience
local FIREFLY_TEXTURE = "rbxassetid://92367567771233" -- a soft glowing dot
local AMBIENCE_VOLUME = 0.5
local AMBIENCE_FADE = TweenInfo.new(2)

local RAIN_AREA = 90 -- studs square above the camera the rain falls from
local RAIN_HEIGHT = 35
local FIREFLY_AREA = Vector3.new(50, 6, 50) -- box around the character they drift in

type Look = {
	clockTime: number?, -- nil keeps the place's own time
	brightness: number, -- multiplies the place's Brightness
	ambient: Color3?, -- nil keeps the place's own
	outdoorAmbient: Color3?,
	tint: Color3,
	saturation: number,
	contrast: number,
	cloudCover: number?, -- Terrain Clouds, only when the place has them
	cloudDensity: number?,
	rainRate: number,
	fireflyRate: number,
	ambience: "Rain" | "Night" | nil,
}

local LOOKS: { [string]: Look } = {
	Clear = { brightness = 1, tint = Color3.new(1, 1, 1), saturation = 0, contrast = 0, rainRate = 0, fireflyRate = 0 },
	Rain = {
		brightness = 0.65,
		outdoorAmbient = Color3.fromRGB(110, 115, 125),
		tint = Color3.fromRGB(215, 225, 240),
		saturation = -0.2,
		contrast = 0,
		cloudCover = 0.85,
		cloudDensity = 0.6,
		rainRate = 350,
		fireflyRate = 0,
		ambience = "Rain",
	},
	Thunderstorm = {
		brightness = 0.45,
		outdoorAmbient = Color3.fromRGB(85, 90, 105),
		tint = Color3.fromRGB(195, 205, 230),
		saturation = -0.35,
		contrast = 0.1,
		cloudCover = 0.95,
		cloudDensity = 0.85,
		rainRate = 650,
		fireflyRate = 0,
		ambience = "Rain",
	},
	Night = {
		clockTime = 0,
		brightness = 0.5,
		ambient = Color3.fromRGB(60, 70, 110),
		outdoorAmbient = Color3.fromRGB(90, 100, 150),
		tint = Color3.fromRGB(195, 210, 255),
		saturation = -0.1,
		contrast = 0.05,
		rainRate = 0,
		fireflyRate = 8,
		ambience = "Night",
	},
}

--// Types
type Snapshot = {
	clockTime: number,
	brightness: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	tint: Color3,
	saturation: number,
	contrast: number,
	cloudCover: number,
	cloudDensity: number,
}

local WeatherEffects = {}

--// Instances
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "WeatherGrade"
grade.Parent = lighting

local function makeEmitterPart(name: string, size: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	return part
end

local rigFolder = Instance.new("Folder")
rigFolder.Name = "WeatherRig"

local rainPart = makeEmitterPart("Rain", Vector3.new(RAIN_AREA, 1, RAIN_AREA))
rainPart.Parent = rigFolder

local rain = Instance.new("ParticleEmitter")
rain.Name = "Rain"
if RAIN_TEXTURE ~= "" then
	rain.Texture = RAIN_TEXTURE
end
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Shape = Enum.ParticleEmitterShape.Box
rain.Orientation = Enum.ParticleOrientation.VelocityParallel
rain.Speed = NumberRange.new(90, 110)
rain.Lifetime = NumberRange.new(0.45, 0.6)
rain.Size = NumberSequence.new(0.15)
rain.Squash = NumberSequence.new(3) -- stretches each drop into a streak
rain.Color = ColorSequence.new(Color3.fromRGB(200, 215, 235))
rain.Transparency = NumberSequence.new(0.35)
rain.LightInfluence = 1
rain.Rate = 0
rain.Enabled = false
rain.Parent = rainPart

local fireflyPart = makeEmitterPart("Fireflies", FIREFLY_AREA)
fireflyPart.Parent = rigFolder

local fireflies = Instance.new("ParticleEmitter")
fireflies.Name = "Fireflies"
if FIREFLY_TEXTURE ~= "" then
	fireflies.Texture = FIREFLY_TEXTURE
end
fireflies.Shape = Enum.ParticleEmitterShape.Box
fireflies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
fireflies.Speed = NumberRange.new(0.4, 1.2)
fireflies.SpreadAngle = Vector2.new(180, 180)
fireflies.Lifetime = NumberRange.new(4, 7)
fireflies.RotSpeed = NumberRange.new(-40, 40)
fireflies.Size = NumberSequence.new(0.35)
fireflies.Color = ColorSequence.new(Color3.fromRGB(220, 255, 120))
fireflies.LightEmission = 1
fireflies.LightInfluence = 0
fireflies.Brightness = 2
fireflies.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.1),
	NumberSequenceKeypoint.new(0.4, 0.6),
	NumberSequenceKeypoint.new(0.6, 0.1),
	NumberSequenceKeypoint.new(1, 1),
})
fireflies.Rate = 0
fireflies.Enabled = false
fireflies.Parent = fireflyPart

local function makeAmbience(name: string, soundId: string): Sound?
	if soundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = soundService
	return sound
end

local ambienceSounds: { [string]: Sound? } = {
	Rain = makeAmbience("RainAmbience", RAIN_SOUND_ID),
	Night = makeAmbience("NightAmbience", NIGHT_SOUND_ID),
}

--// State
local baseline: Snapshot = {
	clockTime = lighting.ClockTime,
	brightness = lighting.Brightness,
	ambient = lighting.Ambient,
	outdoorAmbient = lighting.OutdoorAmbient,
	tint = Color3.new(1, 1, 1),
	saturation = 0,
	contrast = 0,
	cloudCover = if clouds then clouds.Cover else 0,
	cloudDensity = if clouds then clouds.Density else 0,
}
local applied: Snapshot = table.clone(baseline)
local transition: RBXScriptConnection? = nil
local follow: RBXScriptConnection? = nil

--// Lighting --------------------------------------------------------------------

local function resolve(look: Look): Snapshot
	return {
		clockTime = look.clockTime or baseline.clockTime,
		brightness = baseline.brightness * look.brightness,
		ambient = look.ambient or baseline.ambient,
		outdoorAmbient = look.outdoorAmbient or baseline.outdoorAmbient,
		tint = look.tint,
		saturation = look.saturation,
		contrast = look.contrast,
		cloudCover = look.cloudCover or baseline.cloudCover,
		cloudDensity = look.cloudDensity or baseline.cloudDensity,
	}
end

local function write(snapshot: Snapshot)
	lighting.ClockTime = snapshot.clockTime
	lighting.Brightness = snapshot.brightness
	lighting.Ambient = snapshot.ambient
	lighting.OutdoorAmbient = snapshot.outdoorAmbient
	grade.TintColor = snapshot.tint
	grade.Saturation = snapshot.saturation
	grade.Contrast = snapshot.contrast
	if clouds then
		clouds.Cover = snapshot.cloudCover
		clouds.Density = snapshot.cloudDensity
	end
	applied = snapshot
end

local function lerp(from: Snapshot, to: Snapshot, clockDelta: number, alpha: number): Snapshot
	return {
		clockTime = (from.clockTime + clockDelta * alpha) % 24,
		brightness = from.brightness + (to.brightness - from.brightness) * alpha,
		ambient = from.ambient:Lerp(to.ambient, alpha),
		outdoorAmbient = from.outdoorAmbient:Lerp(to.outdoorAmbient, alpha),
		tint = from.tint:Lerp(to.tint, alpha),
		saturation = from.saturation + (to.saturation - from.saturation) * alpha,
		contrast = from.contrast + (to.contrast - from.contrast) * alpha,
		cloudCover = from.cloudCover + (to.cloudCover - from.cloudCover) * alpha,
		cloudDensity = from.cloudDensity + (to.cloudDensity - from.cloudDensity) * alpha,
	}
end

local function blendTo(target: Snapshot, instant: boolean)
	if transition then
		transition:Disconnect()
		transition = nil
	end
	if instant then
		write(target)
		return
	end

	-- The clock only runs forwards, so night falls through sunset and ends at sunrise.
	local from = applied
	local clockDelta = (target.clockTime - from.clockTime) % 24
	local elapsed = 0
	transition = runService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		local alpha = math.min(elapsed / TRANSITION_SECONDS, 1)
		local eased = tweenService:GetValue(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		write(lerp(from, target, clockDelta, eased))
		if alpha >= 1 and transition then
			transition:Disconnect()
			transition = nil
		end
	end)
end

--// Particles and sound ---------------------------------------------------------

local function followCamera()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	rainPart.CFrame = CFrame.new(cameraPosition + Vector3.new(0, RAIN_HEIGHT, 0))

	local character = players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local center = if root and root:IsA("BasePart") then root.Position else cameraPosition
	fireflyPart.CFrame = CFrame.new(center + Vector3.new(0, 1, 0))
end

local function setEmitters(look: Look)
	rain.Rate = look.rainRate
	rain.Enabled = look.rainRate > 0
	fireflies.Rate = look.fireflyRate
	fireflies.Enabled = look.fireflyRate > 0

	local active = rain.Enabled or fireflies.Enabled
	if active and not follow then
		rigFolder.Parent = workspace.CurrentCamera
		followCamera()
		follow = runService.PreRender:Connect(followCamera)
	elseif not active and follow then
		follow:Disconnect()
		follow = nil
	end
end

local function setAmbience(look: Look)
	for name, sound in ambienceSounds do
		if not sound then
			continue
		end
		local wanted = look.ambience == name
		if wanted and not sound.IsPlaying then
			sound:Play()
		end
		local fade = tweenService:Create(sound, AMBIENCE_FADE, { Volume = if wanted then AMBIENCE_VOLUME else 0 })
		if not wanted then
			fade.Completed:Once(function(playbackState: Enum.PlaybackState)
				if playbackState == Enum.PlaybackState.Completed then
					sound:Stop()
				end
			end)
		end
		fade:Play()
	end
end

--// API -------------------------------------------------------------------------

-- Moves the scene over to `weather`'s look; `instant` skips the blend (joining mid-weather).
function WeatherEffects.apply(weather: string, instant: boolean?)
	local look = LOOKS[weather] or LOOKS.Clear
	blendTo(resolve(look), instant == true)
	setEmitters(look)
	setAmbience(look)
end

return WeatherEffects
