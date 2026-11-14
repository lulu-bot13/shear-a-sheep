--!strict

--[[
	Pooled damage numbers drawn on the screen over the spot a sheep was hit: they pop in, float up and fade; big hits and finishing blows pop bigger and gold.
	One RenderStepped loop moves them all and only runs while any are showing.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.DamageNumbers
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local screenScale = require(script.Parent.ScreenScale)

--// Configs
local DISPLAY_ORDER = 4 -- over the HUD, under windows and popups
local EFFECT_LAYER_ATTRIBUTE = "EffectLayer" -- TutorialClient leaves guis with this on
local POOL_SIZE = 18 -- labels made up front
local MAX_LABELS = 40 -- past this the oldest number is reused
local LIFETIME = 0.85 -- seconds on screen
local RISE = 3 -- studs each number floats up over its life
local START_HEIGHT = 2.6 -- studs above the hit position
local JITTER_PIXELS = 34 -- each number starts this far (at most) left / right of the hit, so a combo spreads out
local POP_SECONDS = 0.09 -- grows to its peak in this long...
local SETTLE_SECONDS = 0.16 -- ...then settles to its normal size
local FADE_FROM = 0.55 -- of its life, when it starts to fade
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

type Style = { size: number, peak: number, color: Color3, stroke: Color3, rotation: number }

local STYLES: { [string]: Style } = {
	Normal = { size = 48, peak = 1.35, color = Color3.fromRGB(255, 255, 255), stroke = Color3.fromRGB(40, 25, 15), rotation = 0 },
	Big = { size = 60, peak = 1.55, color = Color3.fromRGB(255, 196, 64), stroke = Color3.fromRGB(90, 40, 0), rotation = 8 },
	Finish = { size = 70, peak = 1.7, color = Color3.fromRGB(255, 232, 92), stroke = Color3.fromRGB(110, 50, 0), rotation = 10 },
}

type Number = {
	label: TextLabel,
	stroke: UIStroke,
	scale: UIScale,
	active: boolean,
	startedAt: number,
	position: Vector3,
	jitter: number,
	peak: number,
	tilt: number,
}

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DamageNumbers"
gui.IgnoreGuiInset = true -- so WorldToViewportPoint's pixels line up with the gui's
gui.ResetOnSpawn = false
gui.DisplayOrder = DISPLAY_ORDER
gui:SetAttribute(EFFECT_LAYER_ATTRIBUTE, true)
gui.Parent = playerGui

--// State
local numbers: { Number } = {}
local renderConnection: RBXScriptConnection? = nil
local random = Random.new()

local DamageNumbers = {}

local function createNumber(): Number
	local label = Instance.new("TextLabel")
	label.Name = "Damage"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = FONT
	label.TextScaled = true
	label.Visible = false
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Parent = label

	local number: Number = {
		label = label,
		stroke = stroke,
		scale = scale,
		active = false,
		startedAt = 0,
		position = Vector3.zero,
		jitter = 0,
		peak = 1,
		tilt = 0,
	}
	table.insert(numbers, number)
	return number
end

for _ = 1, POOL_SIZE do
	createNumber()
end

-- A free label, a new one under MAX_LABELS, or else the one closest to fading out.
local function acquire(): Number
	local oldest: Number? = nil
	for _, number in numbers do
		if not number.active then
			return number
		end
		if not oldest or number.startedAt < oldest.startedAt then
			oldest = number
		end
	end
	if #numbers < MAX_LABELS or not oldest then
		return createNumber()
	end
	return oldest
end

local function getPopScale(elapsed: number, peak: number): number
	if elapsed < POP_SECONDS then
		return peak * (elapsed / POP_SECONDS)
	end
	local settle = math.min((elapsed - POP_SECONDS) / SETTLE_SECONDS, 1)
	return peak + (1 - peak) * (1 - (1 - settle) ^ 2)
end

local function step()
	local camera = workspace.CurrentCamera
	local now = os.clock()
	local anyActive = false

	for _, number in numbers do
		if not number.active then
			continue
		end
		local elapsed = now - number.startedAt
		local t = elapsed / LIFETIME
		if t >= 1 or not camera then
			number.active = false
			number.label.Visible = false
			continue
		end
		anyActive = true

		local rise = RISE * (1 - (1 - t) ^ 3) -- eases out, so it jumps up then hangs
		local screen, onScreen = camera:WorldToViewportPoint(number.position + Vector3.new(0, START_HEIGHT + rise, 0))
		number.label.Visible = onScreen
		if not onScreen then
			continue
		end

		local fade = if t > FADE_FROM then (t - FADE_FROM) / (1 - FADE_FROM) else 0
		number.label.Position = UDim2.fromOffset(screen.X + number.jitter, screen.Y)
		number.label.TextTransparency = fade
		number.stroke.Transparency = fade
		number.scale.Scale = getPopScale(elapsed, number.peak)
		number.label.Rotation = number.tilt * (1 - math.min(elapsed / (POP_SECONDS + SETTLE_SECONDS), 1))
	end

	if not anyActive and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

--[[
	Shows `damage` over `position`. `kind` is "Normal", "Big" (a hit that took a big share of the sheep) or "Finish"
	(the blow that sheared it bare), which pop bigger and gold.
]]
function DamageNumbers.show(position: Vector3, damage: number, kind: string?)
	local style = STYLES[kind or "Normal"] or STYLES.Normal
	local number = acquire()
	local size = screenScale.px(style.size)

	number.active = true
	number.startedAt = os.clock()
	number.position = position
	number.jitter = random:NextNumber(-JITTER_PIXELS, JITTER_PIXELS) * screenScale.get()
	number.peak = style.peak
	number.tilt = style.rotation * (if random:NextNumber() < 0.5 then -1 else 1)

	local label = number.label
	label.Size = UDim2.fromOffset(size * 3, size)
	label.Text = numberFormatter:Format(math.floor(damage), 1)
	label.TextColor3 = style.color
	label.TextTransparency = 0
	label.ZIndex = if kind == "Finish" then 3 elseif kind == "Big" then 2 else 1
	number.stroke.Color = style.stroke
	number.stroke.Thickness = math.max(2, size / 14)
	number.stroke.Transparency = 0
	number.scale.Scale = 0
	label.Visible = false -- placed on the next frame, so it never flashes at its old spot

	if not renderConnection then
		renderConnection = runService.RenderStepped:Connect(step)
	end
end

return DamageNumbers
