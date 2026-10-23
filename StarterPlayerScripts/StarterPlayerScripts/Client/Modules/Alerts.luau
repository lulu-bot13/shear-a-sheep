--[[
	On-screen alerts: short banners stacked at the top of the screen, and a big centered announcement (rebirths).
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Alerts
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Configs
local BANNER_SECONDS = 2.2
local BANNER_HEIGHT = 44
local MAX_BANNERS = 4
local CENTER_SECONDS = 2.5
local FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FONT = Enum.Font.FredokaOne

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
local centerToken = 0

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

-- A big title in the middle of the screen with a smaller line under it; a new one replaces the last.
function Alerts.showCenter(title: string, subtitle: string?)
	centerToken += 1
	local token = centerToken

	local old = alertGui:FindFirstChild("Center")
	if old then
		old:Destroy()
	end

	local holder = Instance.new("Frame")
	holder.Name = "Center"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.4)
	holder.Size = UDim2.fromScale(0.7, 0.25)

	local titleLabel = makeLabel(title, Color3.fromRGB(255, 213, 74), 4)
	titleLabel.Size = UDim2.fromScale(1, 0.65)
	titleLabel.Parent = holder

	local subtitleLabel = makeLabel(subtitle or "", COLORS.info, 3)
	subtitleLabel.Position = UDim2.fromScale(0, 0.65)
	subtitleLabel.Size = UDim2.fromScale(1, 0.35)
	subtitleLabel.Visible = subtitle ~= nil
	subtitleLabel.Parent = holder

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = holder
	holder.Parent = alertGui
	tweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()

	task.delay(CENTER_SECONDS, function()
		if token ~= centerToken then
			return
		end
		fadeOut(subtitleLabel, function() end)
		fadeOut(titleLabel, function()
			holder:Destroy()
		end)
	end)
end

return Alerts
