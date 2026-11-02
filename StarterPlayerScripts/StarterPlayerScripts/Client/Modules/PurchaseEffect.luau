--!strict

--[[
	Plays while a Robux purchase prompt is open: the screen darkens, a rainbow spins over it and the camera zooms in a little.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.PurchaseEffect
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Configs
local DIM_TRANSPARENCY = 0.45 -- the black overlay at full strength
local RAINBOW_TRANSPARENCY = 0.75
local RAINBOW_SPIN_SPEED = 120 -- degrees per second
local FOV_ZOOM = 8 -- degrees the field of view narrows by
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_SECONDS = 60 -- ends by itself if no prompt ever closes (the server refused to prompt)
local DISPLAY_ORDER = 1000

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 165, 50)),
	ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(255, 235, 70)),
	ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(80, 220, 100)),
	ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(70, 160, 255)),
	ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(170, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 70)),
})

--// Instances
local player = players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PurchaseEffect"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = DISPLAY_ORDER
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function createOverlay(name: string, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Interactable = false
	frame.Parent = gui
	return frame
end

local dim = createOverlay("Dim", Color3.new(0, 0, 0))
local rainbow = createOverlay("Rainbow", Color3.new(1, 1, 1))
local gradient = Instance.new("UIGradient")
gradient.Color = RAINBOW
gradient.Parent = rainbow

--// State
local active = false
local playId = 0
local baseFov = 70
local spinConnection: RBXScriptConnection? = nil
local fovTween: Tween? = nil

local PurchaseEffect = {}

local function tweenFov(fov: number, tweenInfo: TweenInfo)
	if fovTween then
		fovTween:Cancel()
	end
	local camera = workspace.CurrentCamera
	if camera then
		fovTween = tweenService:Create(camera, tweenInfo, { FieldOfView = fov })
		fovTween:Play()
	end
end

function PurchaseEffect.stop()
	if not active then
		return
	end
	active = false
	local stopId = playId

	tweenService:Create(dim, FADE_OUT, { BackgroundTransparency = 1 }):Play()
	tweenService:Create(rainbow, FADE_OUT, { BackgroundTransparency = 1 }):Play()
	tweenFov(baseFov, FADE_OUT)

	task.delay(FADE_OUT.Time, function()
		if playId == stopId and spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
			gui.Enabled = false
		end
	end)
end

-- Starts the effect; it ends when the player's next purchase prompt closes.
function PurchaseEffect.play()
	playId += 1
	local id = playId
	task.delay(MAX_SECONDS, function()
		if playId == id then
			PurchaseEffect.stop()
		end
	end)

	if active then
		return
	end
	active = true

	-- A replay during the fade out keeps the FOV it was going back to.
	local camera = workspace.CurrentCamera
	if not spinConnection and camera then
		baseFov = camera.FieldOfView
	end

	gui.Enabled = true
	if not spinConnection then
		spinConnection = runService.RenderStepped:Connect(function(deltaTime: number)
			gradient.Rotation = (gradient.Rotation + RAINBOW_SPIN_SPEED * deltaTime) % 360
		end)
	end

	tweenService:Create(dim, FADE_IN, { BackgroundTransparency = DIM_TRANSPARENCY }):Play()
	tweenService:Create(rainbow, FADE_IN, { BackgroundTransparency = RAINBOW_TRANSPARENCY }):Play()
	tweenFov(baseFov - FOV_ZOOM, FADE_IN)
end

marketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number)
	if userId == player.UserId then
		PurchaseEffect.stop()
	end
end)

marketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchaser: Player)
	if purchaser == player then
		PurchaseEffect.stop()
	end
end)

return PurchaseEffect
