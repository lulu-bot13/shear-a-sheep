--!strict

--[[
	Local-only lightning bolt: a jagged neon line from the sky to a point, a screen flash and a delayed thunder clap.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Lightning
]]--

--// Services
local lighting = game:GetService("Lighting")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Sounds
local weatherSounds = soundService:WaitForChild("Weather", 10)
local thunderSfx = if weatherSounds then weatherSounds:FindFirstChild("ThunderStrike") :: Sound? else nil

--// Configs
local THUNDER_DELAY = 0.35 -- seconds after the flash, so it feels a little way off

local SEGMENT_COUNT = 9
local BOLT_HEIGHT = 140 -- studs above the target the bolt starts
local BOLT_JITTER = 7 -- max sideways kink per joint
local BOLT_WIDTH = 0.5
local BOLT_COLOR = Color3.fromRGB(190, 220, 255)
local BOLT_SHOW_SECONDS = 0.08 -- fully bright before it fades
local BOLT_FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local IMPACT_LIGHT_RANGE = 40
local IMPACT_LIGHT_BRIGHTNESS = 6

local FLASH_BRIGHTNESS = 0.35
local FLASH_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local Lightning = {}

--// Instances
local folder = Instance.new("Folder")
folder.Name = "Lightning"

local segments: { BasePart } = {}
for index = 1, SEGMENT_COUNT do
	local segment = Instance.new("Part")
	segment.Name = `Segment{index}`
	segment.Anchored = true
	segment.CanCollide = false
	segment.CanQuery = false
	segment.CanTouch = false
	segment.CastShadow = false
	segment.Material = Enum.Material.Neon
	segment.Color = BOLT_COLOR
	segment.Transparency = 1
	segment.Parent = folder
	segments[index] = segment
end

local impact = Instance.new("Part")
impact.Name = "Impact"
impact.Anchored = true
impact.CanCollide = false
impact.CanQuery = false
impact.CanTouch = false
impact.Transparency = 1
impact.Size = Vector3.one
impact.Parent = folder

local impactLight = Instance.new("PointLight")
impactLight.Color = BOLT_COLOR
impactLight.Range = IMPACT_LIGHT_RANGE
impactLight.Brightness = 0
impactLight.Parent = impact

local flash = Instance.new("ColorCorrectionEffect")
flash.Name = "LightningFlash"
flash.Brightness = 0
flash.Parent = lighting

--// State
local strikeToken = 0
local fadeTweens: { Tween } = {}
local random = Random.new()

--// Helpers ---------------------------------------------------------------------

local function placeBolt(target: Vector3)
	local top = target + Vector3.new(random:NextNumber(-20, 20), BOLT_HEIGHT, random:NextNumber(-20, 20))
	local previous = top
	for index, segment in segments do
		local alpha = index / SEGMENT_COUNT
		local point = top:Lerp(target, alpha)
		if index < SEGMENT_COUNT then
			point += Vector3.new(random:NextNumber(-BOLT_JITTER, BOLT_JITTER), 0, random:NextNumber(-BOLT_JITTER, BOLT_JITTER))
		end

		local length = (point - previous).Magnitude
		segment.Size = Vector3.new(BOLT_WIDTH, BOLT_WIDTH, length)
		segment.CFrame = CFrame.lookAt((previous + point) / 2, point)
		segment.Transparency = 0
		previous = point
	end
	impact.Position = target + Vector3.new(0, 2, 0)
end

--// API -------------------------------------------------------------------------

-- Strikes `target` in world space. A new strike while one is still fading takes over the same bolt.
function Lightning.strike(target: Vector3)
	if not folder.Parent then
		folder.Parent = workspace.CurrentCamera
	end

	strikeToken += 1
	local token = strikeToken
	for _, tween in fadeTweens do
		tween:Cancel()
	end
	table.clear(fadeTweens)

	placeBolt(target)
	impactLight.Brightness = IMPACT_LIGHT_BRIGHTNESS
	Lightning.flash()

	task.delay(BOLT_SHOW_SECONDS, function()
		if token ~= strikeToken then
			return
		end
		for _, segment in segments do
			local tween = tweenService:Create(segment, BOLT_FADE, { Transparency = 1 })
			table.insert(fadeTweens, tween)
			tween:Play()
		end
		local lightTween = tweenService:Create(impactLight, BOLT_FADE, { Brightness = 0 })
		table.insert(fadeTweens, lightTween)
		lightTween:Play()
	end)

	-- PlayLocalSound plays a fresh copy, so back-to-back strikes overlap instead of cutting each other off.
	local sound = thunderSfx
	if sound and sound:IsA("Sound") then
		task.delay(THUNDER_DELAY, function()
			soundService:PlayLocalSound(sound)
		end)
	end
end

-- A sky flash with no bolt, for distant lightning.
function Lightning.flash()
	flash.Brightness = FLASH_BRIGHTNESS
	tweenService:Create(flash, FLASH_FADE, { Brightness = 0 }):Play()
end

return Lightning
