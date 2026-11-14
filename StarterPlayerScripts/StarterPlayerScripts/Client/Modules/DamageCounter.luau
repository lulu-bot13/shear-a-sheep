--!strict

--[[
	Running total of the damage dealt while shearing, in big tilted pale red text over a timer bar that shrinks in from both sides.
	Each hit adds to the total and refills the bar; when the bar runs out the counter fades away and the total resets.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.DamageCounter
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local screenScale = require(script.Parent.ScreenScale)

--// Configs
local DISPLAY_ORDER = 4 -- same layer as DamageNumbers
local EFFECT_LAYER_ATTRIBUTE = "EffectLayer" -- TutorialClient leaves guis with this on
local TIMEOUT = 3 -- seconds without a hit before the total resets
local SCREEN_POSITION = UDim2.fromScale(0.133, 0.614) -- where the counter sits on screen
local TEXT_SIZE = 90 -- TextSize caps at 100; the ScreenScale UIScale grows it past that on big screens
local TILT = -8 -- degrees the whole counter leans
local BAR_WIDTH = 320
local BAR_HEIGHT = 12
local BAR_GAP = 6 -- pixels between the text and the bar
local TEXT_COLOR = Color3.fromRGB(255, 150, 150)
local STROKE_COLOR = Color3.fromRGB(70, 20, 20)
local BAR_COLOR = Color3.fromRGB(255, 150, 150)
local FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local HIT_PUNCH = 1.18 -- the text pops to this scale on each hit...
local PUNCH_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out) -- ...and settles back with this
local FADE_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DamageCounter"
gui.ResetOnSpawn = false
gui.DisplayOrder = DISPLAY_ORDER
gui.Enabled = false
gui:SetAttribute(EFFECT_LAYER_ATTRIBUTE, true)
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = SCREEN_POSITION
holder.Size = UDim2.fromOffset(BAR_WIDTH + 40, TEXT_SIZE + BAR_GAP + BAR_HEIGHT + 8)
holder.Rotation = TILT
holder.BackgroundTransparency = 1
holder.Parent = gui
screenScale.attach(holder)

local label = Instance.new("TextLabel")
label.Name = "Damage"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.fromScale(0.5, 0)
label.Size = UDim2.new(1, 0, 0, TEXT_SIZE)
label.BackgroundTransparency = 1
label.FontFace = FONT
label.TextSize = TEXT_SIZE
label.TextColor3 = TEXT_COLOR
label.Text = "0"
label.Parent = holder

local labelStroke = Instance.new("UIStroke")
labelStroke.Color = STROKE_COLOR
labelStroke.Thickness = 4
labelStroke.Parent = label

local punchScale = Instance.new("UIScale")
punchScale.Parent = label

local bar = Instance.new("Frame")
bar.Name = "Timer"
bar.AnchorPoint = Vector2.new(0.5, 0) -- centered, so shrinking the width pulls in both ends
bar.Position = UDim2.new(0.5, 0, 0, TEXT_SIZE + BAR_GAP)
bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
bar.BackgroundColor3 = BAR_COLOR
bar.BorderSizePixel = 0
bar.Parent = holder

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = bar

local barStroke = Instance.new("UIStroke")
barStroke.Color = STROKE_COLOR
barStroke.Thickness = 2
barStroke.Parent = bar

--// State
local total = 0
local lastHitAt = 0
local renderConnection: RBXScriptConnection? = nil
local fadeTweens: { Tween } = {}

local DamageCounter = {}

local function hide()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	total = 0
	fadeTweens = {
		tweenService:Create(label, FADE_INFO, { TextTransparency = 1 }),
		tweenService:Create(labelStroke, FADE_INFO, { Transparency = 1 }),
		tweenService:Create(bar, FADE_INFO, { BackgroundTransparency = 1 }),
		tweenService:Create(barStroke, FADE_INFO, { Transparency = 1 }),
	}
	fadeTweens[1].Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed then
			gui.Enabled = false
		end
	end)
	for _, tween in fadeTweens do
		tween:Play()
	end
end

local function step()
	local remaining = 1 - (os.clock() - lastHitAt) / TIMEOUT
	if remaining <= 0 then
		hide()
		return
	end
	bar.Size = UDim2.fromOffset(BAR_WIDTH * remaining, BAR_HEIGHT)
end

-- Adds `damage` to the running total and refills the timer.
function DamageCounter.add(damage: number)
	if damage <= 0 then
		return
	end
	for _, tween in fadeTweens do
		tween:Cancel()
	end
	table.clear(fadeTweens)
	total += damage
	lastHitAt = os.clock()

	label.Text = numberFormatter:Format(math.floor(total), 1)
	bar.Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT)
	label.TextTransparency = 0
	labelStroke.Transparency = 0
	bar.BackgroundTransparency = 0
	barStroke.Transparency = 0
	gui.Enabled = true

	punchScale.Scale = HIT_PUNCH
	tweenService:Create(punchScale, PUNCH_INFO, { Scale = 1 }):Play()

	if not renderConnection then
		renderConnection = runService.RenderStepped:Connect(step)
	end
end

return DamageCounter
