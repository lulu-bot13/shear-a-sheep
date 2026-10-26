--[[
	The white fade that hides the farm reset after a Prestige (started from the rebirth screen's button in RebirthClient).
	PrestigeHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PrestigeClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local rebirthCount = playerGui:WaitForChild("RebirthScreen"):WaitForChild("Main"):WaitForChild("RebirthCount") :: TextLabel

--// Sounds
local uiSounds = soundService:WaitForChild("UISounds")
local prestigedSound = (uiSounds:FindFirstChild("Prestiged") or uiSounds:FindFirstChild("Rebirthed")) :: Sound?

--// Configs
local FADE_IN_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local FADE_OUT_TWEEN = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local HOLD_SECONDS = 0.8 -- the white screen stays up at least this long after the farm is reset, so the text can be read
local FINISH_TIMEOUT_SECONDS = 6 -- fade out anyway if the server's "finished" never arrives
local FADE_DISPLAY_ORDER = 10000
local FADE_TEXT_COLOR = Color3.fromRGB(35, 35, 45)

local REASON_TEXT = {
	NotReady = "Not enough rebirths to Prestige",
	Busy = "Already prestiging",
}

--// State
local fading = false
local farmReset = false -- set by PrestigeFinished while the white screen is up

--// White screen -----------------------------------------------------------------------

-- One smooth fade to white and back (no flashing), held while the server resets the farm.
local function playWhiteScreen(prestiges: number)
	if fading then
		return
	end
	fading = true

	local fadeGui = Instance.new("ScreenGui")
	fadeGui.Name = "PrestigeFade"
	fadeGui.IgnoreGuiInset = true
	fadeGui.DisplayOrder = FADE_DISPLAY_ORDER
	fadeGui.ResetOnSpawn = false

	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.BorderSizePixel = 0
	white.Parent = fadeGui

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromScale(0.7, 0.16)
	title.BackgroundTransparency = 1
	title.FontFace = rebirthCount.FontFace
	title.TextColor3 = FADE_TEXT_COLOR
	title.TextScaled = true
	title.TextTransparency = 1
	title.Text = `PRESTIGE {prestiges}`
	title.Parent = white

	fadeGui.Parent = playerGui

	tweenService:Create(white, FADE_IN_TWEEN, { BackgroundTransparency = 0 }):Play()
	local fadeIn = tweenService:Create(title, FADE_IN_TWEEN, { TextTransparency = 0 })
	fadeIn:Play()
	fadeIn.Completed:Wait()

	local deadline = os.clock() + FINISH_TIMEOUT_SECONDS
	while not farmReset and os.clock() < deadline do
		task.wait()
	end
	task.wait(HOLD_SECONDS)

	tweenService:Create(white, FADE_OUT_TWEEN, { BackgroundTransparency = 1 }):Play()
	local fadeOut = tweenService:Create(title, FADE_OUT_TWEEN, { TextTransparency = 1 })
	fadeOut:Play()
	fadeOut.Completed:Wait()

	fadeGui:Destroy()
	fading = false
end

--// Setup -------------------------------------------------------------------------------

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.PrestigeResult, function(success: boolean, reason: string?, prestiges: number?)
	if not success then
		alerts.show(REASON_TEXT[reason or ""] or "Can't Prestige", "error")
		return
	end

	farmReset = false
	windowsManager.closeAll()
	if prestigedSound then
		prestigedSound:Play()
	end
	task.spawn(playWhiteScreen, prestiges or 0)
end)

network.connectEvent(network.RemoteEvents.PrestigeFinished, function()
	farmReset = true
end)
