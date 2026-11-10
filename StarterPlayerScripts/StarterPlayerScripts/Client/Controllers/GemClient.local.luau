--[[
	The "+N" gem popup from GemHandler's GemFound: the gem icon and amount pop in with a burst of little gems, then fly into
	the HUD's gem counter (Main.CurrencyFrame.Gem) and fade away.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.GemClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local iconIds = require(replicatedStorage.Shared.Constants.IconIds)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sounds
local uiSounds = soundService:FindFirstChild("UISounds")
local gemSound = if uiSounds then uiSounds:FindFirstChild("DiamondPickup") :: Sound? else nil

--// Configs
local POP_IN = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLY = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FADE = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BURST = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOLD_SECONDS = 0.7
local START_Y = 0.3 -- of the screen height; each popup still showing pushes the next one down a step
local STACK_STEP_Y = 0.1
local MAX_STACK = 3
local POPUP_SIZE = UDim2.fromScale(0.3, 0.13)
local POPUP_ASPECT = 2.6
local ICON_CENTER = UDim2.fromScale(0.2, 0.5)
local ICON_TILT = -25 -- degrees the icon swings in from
local END_SCALE = 0.35 -- the size it shrinks to as it reaches the counter
local FALLBACK_END = UDim2.fromScale(0.5, 0.1) -- floats up here when the HUD counter isn't on screen
local BURST_COUNT = 6
local BURST_SIZE = 0.3 -- of the popup's height
local BURST_DISTANCE = 0.85 -- of the popup's height
local TOP_COLOR = Color3.fromRGB(160, 245, 255) -- gem cyan
local BOTTOM_COLOR = Color3.fromRGB(190, 120, 255) -- gem purple
local STROKE_COLOR = Color3.fromRGB(45, 15, 90)
local STROKE_THICKNESS = 3.5
local TEXT_FONT = Font.fromEnum(Enum.Font.FredokaOne)

type Popup = {
	frame: Frame,
	scale: UIScale,
	icon: ImageLabel,
	label: TextLabel,
	stroke: UIStroke,
}

--// State
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GemPopup"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

local random = Random.new()
local showing = 0 -- popups on screen, for stacking

-- 1234 -> "1,234"
local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function newPopup(amount: number): Popup
	local frame = Instance.new("Frame")
	frame.Name = "GemFound"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = POPUP_SIZE
	frame.BackgroundTransparency = 1

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = POPUP_ASPECT
	aspect.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = ICON_CENTER
	icon.Size = UDim2.fromScale(1, 1)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.BackgroundTransparency = 1
	icon.Image = iconIds.Gem
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Rotation = ICON_TILT
	icon.ZIndex = 2
	icon.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.AnchorPoint = Vector2.new(0, 0.5)
	label.Position = UDim2.fromScale(0.41, 0.5)
	label.Size = UDim2.fromScale(0.59, 0.82)
	label.BackgroundTransparency = 1
	label.FontFace = TEXT_FONT
	label.Text = `+{formatWithCommas(amount)}`
	label.TextColor3 = Color3.new(1, 1, 1) -- the gradient gives the text its colour
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 2
	label.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(TOP_COLOR, BOTTOM_COLOR)
	gradient.Rotation = 90
	gradient.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = STROKE_THICKNESS
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label

	return { frame = frame, scale = scale, icon = icon, label = label, stroke = stroke }
end

-- Little gems fly out from behind the big one and fade.
local function playBurst(frame: Frame)
	for index = 1, BURST_COUNT do
		local angle = index / BURST_COUNT * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local rotation = random:NextNumber(-40, 40)
		local gem = Instance.new("ImageLabel")
		gem.Name = "Burst"
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = ICON_CENTER
		gem.Size = UDim2.fromScale(BURST_SIZE, BURST_SIZE)
		gem.SizeConstraint = Enum.SizeConstraint.RelativeYY
		gem.BackgroundTransparency = 1
		gem.Image = iconIds.Gem
		gem.ScaleType = Enum.ScaleType.Fit
		gem.Rotation = rotation
		gem.ZIndex = 1
		gem.Parent = frame

		local offset = UDim2.fromScale(math.cos(angle) * BURST_DISTANCE / POPUP_ASPECT, math.sin(angle) * BURST_DISTANCE)
		local tween = tweenService:Create(gem, BURST, {
			Position = ICON_CENTER + offset,
			Size = UDim2.fromScale(BURST_SIZE * 0.4, BURST_SIZE * 0.4),
			Rotation = rotation + 90,
			ImageTransparency = 1,
		})
		tween.Completed:Once(function()
			gem:Destroy()
		end)
		tween:Play()
	end
end

-- The centre of the HUD's gem icon in this gui's own pixels, or nil while it isn't on screen.
local function getCounterPosition(): UDim2?
	local main = playerGui:FindFirstChild("Main")
	local currency = main and main:FindFirstChild("CurrencyFrame")
	local gem = currency and currency:FindFirstChild("Gem")
	if not (main and main:IsA("ScreenGui") and main.Enabled) then
		return nil
	end
	if not (currency and currency:IsA("GuiObject") and currency.Visible and gem and gem:IsA("GuiObject") and gem.Visible) then
		return nil
	end
	local center = gem.AbsolutePosition + gem.AbsoluteSize / 2 - screenGui.AbsolutePosition
	return UDim2.fromOffset(center.X, center.Y)
end

local function onGemFound(amount: number)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end

	local popup = newPopup(amount)
	popup.frame.Position = UDim2.fromScale(0.5, START_Y + STACK_STEP_Y * (showing % MAX_STACK))
	popup.frame.Parent = screenGui
	showing += 1
	if gemSound then
		gemSound:Play()
	end

	tweenService:Create(popup.scale, POP_IN, { Scale = 1 }):Play()
	tweenService:Create(popup.icon, POP_IN, { Rotation = 0 }):Play()
	playBurst(popup.frame)
	task.wait(POP_IN.Time + HOLD_SECONDS)

	tweenService:Create(popup.frame, FLY, { Position = getCounterPosition() or FALLBACK_END }):Play()
	tweenService:Create(popup.scale, FLY, { Scale = END_SCALE }):Play()
	task.wait(FLY.Time - FADE.Time)

	tweenService:Create(popup.icon, FADE, { ImageTransparency = 1 }):Play()
	tweenService:Create(popup.stroke, FADE, { Transparency = 1 }):Play()
	local fade = tweenService:Create(popup.label, FADE, { TextTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	showing -= 1
	popup.frame:Destroy()
end

--// Setup -------------------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.GemFound, onGemFound)
