--[[
	Luck icons rain down the screen at random spots, sizes and spins; played after a rebirth and on Index claims.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.LuckRain
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Configs
-- Spawning + the slowest fall add up to EFFECT_SECONDS.
local LUCK_ICON_IMAGE = "rbxassetid://86611651520562" -- empty falls back to a 🍀 emoji
local EFFECT_SECONDS = 3.5
local FALL_ICON_COUNT = 40
local FALL_SPAWN_SECONDS = 1.5
local FALL_MIN_SECONDS = 1.4
local FALL_MAX_SECONDS = EFFECT_SECONDS - FALL_SPAWN_SECONDS
local FALL_MIN_SIZE = 36
local FALL_MAX_SIZE = 72

local LuckRain = {}

local effectGui = Instance.new("ScreenGui")
effectGui.Name = "LuckRainGui"
effectGui.ResetOnSpawn = false
effectGui.IgnoreGuiInset = true
effectGui.Parent = players.LocalPlayer:WaitForChild("PlayerGui")

--// Helpers ---------------------------------------------------------------------

local function makeLuckIcon(size: number): GuiObject
	local icon: GuiObject
	if LUCK_ICON_IMAGE ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Image = LUCK_ICON_IMAGE
		icon = imageLabel
	else
		local clover = Instance.new("TextLabel")
		clover.Text = "🍀"
		clover.TextScaled = true
		icon = clover
	end

	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.Parent = effectGui
	return icon
end

--// API -------------------------------------------------------------------------

-- The icons draw over aboveGui (the screen the effect was played from).
function LuckRain.play(aboveGui: ScreenGui)
	effectGui.DisplayOrder = math.max(effectGui.DisplayOrder, aboveGui.DisplayOrder + 1)

	for _ = 1, FALL_ICON_COUNT do
		task.delay(math.random() * FALL_SPAWN_SECONDS, function()
			local icon = makeLuckIcon(math.random(FALL_MIN_SIZE, FALL_MAX_SIZE))
			local x = math.random()
			local drift = (math.random() - 0.5) * 0.12
			local fallSeconds = FALL_MIN_SECONDS + math.random() * (FALL_MAX_SECONDS - FALL_MIN_SECONDS)

			icon.Position = UDim2.fromScale(x, -0.1)
			icon.Rotation = math.random(-30, 30)

			local fallInfo = TweenInfo.new(fallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fall = tweenService:Create(icon, fallInfo, {
				Position = UDim2.fromScale(x + drift, 1.1),
				Rotation = icon.Rotation + math.random(-180, 180),
			})
			fall.Completed:Once(function()
				icon:Destroy()
			end)
			fall:Play()
		end)
	end
end

return LuckRain
