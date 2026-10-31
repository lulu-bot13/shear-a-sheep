--[[
	The "+1 Gem" popup from GemHandler's GemFound: pops in near the top of the screen, then floats up and fades away.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.GemClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sounds
local uiSounds = soundService:FindFirstChild("UISounds")
local gemSound = if uiSounds then uiSounds:FindFirstChild("DiamondPickup") :: Sound? else nil

--// Configs
local POP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FLOAT_OUT = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 1.2
local START_POSITION = UDim2.fromScale(0.5, 0.2)
local END_POSITION = UDim2.fromScale(0.5, 0.12)
local LABEL_SIZE = UDim2.fromScale(0.3, 0.08)
local TOP_COLOR = Color3.fromRGB(110, 240, 255) -- gem cyan
local BOTTOM_COLOR = Color3.fromRGB(190, 120, 255) -- gem purple
local STROKE_COLOR = Color3.fromRGB(60, 20, 110)
local STROKE_THICKNESS = 3
local TEXT_FONT = Enum.Font.FredokaOne

--// State
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GemPopup"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

local function buildLabel(amount: number): (TextLabel, UIScale, UIStroke)
	local label = Instance.new("TextLabel")
	label.Name = "GemFound"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = START_POSITION
	label.Size = LABEL_SIZE
	label.BackgroundTransparency = 1
	label.Font = TEXT_FONT
	label.Text = `+{amount} Gem{if amount == 1 then "" else "s"} 💎`
	label.TextColor3 = Color3.new(1, 1, 1) -- the gradient gives the text its colour
	label.TextScaled = true

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(TOP_COLOR, BOTTOM_COLOR)
	gradient.Rotation = 90
	gradient.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = STROKE_THICKNESS
	stroke.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = label

	return label, scale, stroke
end

local function onGemFound(amount: number)
	if type(amount) ~= "number" or amount <= 0 then
		return
	end

	local label, scale, stroke = buildLabel(amount)
	label.Parent = screenGui
	if gemSound then
		gemSound:Play()
	end

	tweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
	task.wait(POP_IN.Time + HOLD_SECONDS)

	tweenService:Create(stroke, FLOAT_OUT, { Transparency = 1 }):Play()
	local float = tweenService:Create(label, FLOAT_OUT, { Position = END_POSITION, TextTransparency = 1 })
	float:Play()
	float.Completed:Wait()
	label:Destroy()
end

--// Setup -------------------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.GemFound, onGemFound)
