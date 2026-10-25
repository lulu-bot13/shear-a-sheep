--[[
	On-screen alerts: short banners stacked at the top of the screen.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Alerts
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Configs
local BANNER_SECONDS = 2.2
local BANNER_HEIGHT = 44
local MAX_BANNERS = 4
local FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FONT = Enum.Font.SourceSansBold

local COLORS = {
	success = Color3.fromRGB(80, 230, 100),
	error = Color3.fromRGB(255, 85, 85),
	info = Color3.fromRGB(255, 255, 255),
}

export type Kind = "success" | "error" | "info"

local Alerts = {}

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

local alertGui = Instance.new("ScreenGui")
alertGui.Name = "AlertsGui"
alertGui.ResetOnSpawn = false
alertGui.DisplayOrder = 100
alertGui.Parent = playerGui

local bannerHolder = Instance.new("Frame")
bannerHolder.Name = "Banners"
bannerHolder.BackgroundTransparency = 1
bannerHolder.AnchorPoint = Vector2.new(0.5, 0)
bannerHolder.Position = UDim2.new(0.5, 0, 0, 12)
bannerHolder.Size = UDim2.new(0.6, 0, 0, (BANNER_HEIGHT + 6) * MAX_BANNERS)
bannerHolder.Parent = alertGui

local bannerLayout = Instance.new("UIListLayout")
bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bannerLayout.SortOrder = Enum.SortOrder.LayoutOrder
bannerLayout.Padding = UDim.new(0, 6)
bannerLayout.Parent = bannerHolder

--// State
local bannerOrder = 0

--// Helpers ---------------------------------------------------------------------

local function makeLabel(text: string, color: Color3, strokeThickness: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = strokeThickness
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	return label
end

local function fadeOut(label: TextLabel, onDone: () -> ())
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		tweenService:Create(stroke, FADE_TWEEN, { Transparency = 1 }):Play()
	end
	local fade = tweenService:Create(label, FADE_TWEEN, { TextTransparency = 1 })
	fade.Completed:Once(onDone)
	fade:Play()
end

--// Public API ------------------------------------------------------------------

-- A banner at the top of the screen; the oldest one is dropped once there are too many.
function Alerts.show(text: string, kind: Kind?)
	local banners = {}
	for _, child in bannerHolder:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(banners, child)
		end
	end
	if #banners >= MAX_BANNERS then
		table.sort(banners, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		banners[1]:Destroy()
	end

	bannerOrder += 1
	local label = makeLabel(text, COLORS[kind or "info"], 2.5)
	label.Name = "Banner"
	label.LayoutOrder = bannerOrder
	label.Size = UDim2.new(1, 0, 0, BANNER_HEIGHT)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = label
	label.Parent = bannerHolder
	tweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()

	task.delay(BANNER_SECONDS, function()
		if label.Parent then
			fadeOut(label, function()
				label:Destroy()
			end)
		end
	end)
end

return Alerts
