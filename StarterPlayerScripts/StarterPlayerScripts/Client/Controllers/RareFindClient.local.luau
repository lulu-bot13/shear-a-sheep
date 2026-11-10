--[[
	Rare-find moment: when an Epic+ or mutated sheep appears at the player's belt Feed, a short camera nudge and big "EPIC FIND!" text.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RareFindClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local NUDGE_SECONDS = 0.35
local NUDGE_ANGLE = math.rad(1.2) -- strongest tilt at the start, easing out
local NUDGE_COOLDOWN = 1.5
local NUDGE_BIND_NAME = "RareFindNudge"
local SHOW_SECONDS = 1.8
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local STROKE_THICKNESS = 3

--// State
local lastNudge = 0
local showToken = 0

-- The overlay is an effect built here, not Studio UI: a ScreenGui with a header line and the sheep's name.
local overlay = Instance.new("ScreenGui")
overlay.Name = "RareFindOverlay"
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 20
overlay.Enabled = false

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0.5)
holder.Position = UDim2.fromScale(0.5, 0.3)
holder.Size = UDim2.fromScale(0.6, 0.16)
holder.Parent = overlay

local holderScale = Instance.new("UIScale")
holderScale.Parent = holder

local function newLine(name: string, positionY: number, height: number): (TextLabel, UIStroke)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromScale(0, positionY)
	label.Size = UDim2.fromScale(1, height)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = STROKE_THICKNESS
	stroke.Parent = label
	return label, stroke
end

local headerLabel, headerStroke = newLine("Header", 0, 0.55)
local nameLabel, nameStroke = newLine("SheepName", 0.58, 0.42)
overlay.Parent = playerGui

local function setTransparency(value: number)
	headerLabel.TextTransparency = value
	nameLabel.TextTransparency = value
	headerStroke.Transparency = value
	nameStroke.Transparency = value
end

-- A quick tilt of the camera that eases out (applied after the camera scripts each frame, so it never accumulates).
local function nudgeCamera()
	local now = os.clock()
	if now - lastNudge < NUDGE_COOLDOWN then
		return
	end
	lastNudge = now
	runService:UnbindFromRenderStep(NUDGE_BIND_NAME)
	runService:BindToRenderStep(NUDGE_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		local elapsed = os.clock() - now
		if elapsed >= NUDGE_SECONDS or not camera then
			runService:UnbindFromRenderStep(NUDGE_BIND_NAME)
			return
		end
		local strength = NUDGE_ANGLE * (1 - elapsed / NUDGE_SECONDS)
		camera.CFrame *= CFrame.Angles(math.sin(elapsed * 40) * strength, 0, math.cos(elapsed * 35) * strength)
	end)
end

local function showText(header: string, name: string)
	showToken += 1
	local token = showToken
	headerLabel.Text = header
	nameLabel.Text = name
	setTransparency(0)
	holderScale.Scale = 0.4
	overlay.Enabled = true
	tweenService:Create(holderScale, POP_TWEEN, { Scale = 1 }):Play()

	task.delay(SHOW_SECONDS, function()
		if token ~= showToken then
			return
		end
		for _, item in { headerLabel, nameLabel } do
			tweenService:Create(item, FADE_TWEEN, { TextTransparency = 1 }):Play()
		end
		for _, item in { headerStroke, nameStroke } do
			tweenService:Create(item, FADE_TWEEN, { Transparency = 1 }):Play()
		end
		task.delay(FADE_TWEEN.Time, function()
			if token == showToken then
				overlay.Enabled = false
			end
		end)
	end)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RareSheepSpawn, function(info: any)
	if type(info) ~= "table" then
		return
	end
	local kind = if type(info.mutation) == "string" then info.mutation elseif type(info.rarity) == "string" then info.rarity else "Rare"
	showText(`{string.upper(kind)} FIND!`, if type(info.name) == "string" then info.name else "")
	nudgeCamera()
end)
