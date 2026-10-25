--[[
	Makes a HUD button's "Alert" badge beat like a heart (grow and shrink) while it's visible, so players know to press it.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.AlertPulse
]]--

--// Services
local tweenService = game:GetService("TweenService")

--// Configs
local PULSE_SCALE = 1.25
local GROW_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHRINK_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BEATS = 2 -- per heartbeat
local REST_SECONDS = 0.45 -- between heartbeats

local AlertPulse = {}

--// Helpers ---------------------------------------------------------------------

-- The badge's text ("!") if it has any, else the badge itself.
local function getPulseTarget(badge: GuiObject): GuiObject
	if badge:IsA("TextLabel") or badge:IsA("TextButton") then
		return badge
	end
	return badge:FindFirstChildWhichIsA("TextLabel", true) or badge
end

--// API -------------------------------------------------------------------------

function AlertPulse.attach(badge: GuiObject)
	local target = getPulseTarget(badge)
	local scale = target:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
	scale.Parent = target
	local baseScale = scale.Scale
	local pulseThread: thread? = nil

	local function tweenTo(info: TweenInfo, scaleValue: number)
		tweenService:Create(scale, info, { Scale = scaleValue }):Play()
	end

	local function stop()
		if pulseThread then
			task.cancel(pulseThread)
			pulseThread = nil
		end
		-- A new tween on Scale cancels any half-finished beat.
		tweenTo(SHRINK_TWEEN, baseScale)
	end

	local function start()
		if pulseThread then
			return
		end
		pulseThread = task.spawn(function()
			while true do
				for _ = 1, BEATS do
					tweenTo(GROW_TWEEN, baseScale * PULSE_SCALE)
					task.wait(GROW_TWEEN.Time)
					tweenTo(SHRINK_TWEEN, baseScale)
					task.wait(SHRINK_TWEEN.Time)
				end
				task.wait(REST_SECONDS)
			end
		end)
	end

	local function update()
		if badge.Visible and badge.Parent then
			start()
		else
			stop()
		end
	end

	badge:GetPropertyChangedSignal("Visible"):Connect(update)
	badge.AncestryChanged:Connect(update)
	update()
end

return AlertPulse
