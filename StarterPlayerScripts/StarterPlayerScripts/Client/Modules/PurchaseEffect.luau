--!strict

--[[
	Plays while a Robux purchase prompt is open (the screen darkens, a rainbow spins, the camera zooms in), then a celebration once it's bought.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.PurchaseEffect
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Configs
local DIM_TRANSPARENCY = 0.45 -- the black overlay at full strength
local RAINBOW_TRANSPARENCY = 0.75
local RAINBOW_SPIN_SPEED = 120 -- degrees per second
local FOV_ZOOM = 8 -- degrees the field of view narrows by
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_SECONDS = 60 -- ends by itself if no prompt ever closes (the server refused to prompt)
local DISPLAY_ORDER = 1000
local CELEBRATE_TEXT = "THANK YOU!"
local CELEBRATE_FLASH_TRANSPARENCY = 0.35
local CELEBRATE_HOLD = 1.4 -- seconds the text stays before fading
local CELEBRATE_POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CELEBRATE_FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

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

-- The celebration has its own gui, so stop()'s fade out never hides it.
local celebrateGui = Instance.new("ScreenGui")
celebrateGui.Name = "PurchaseCelebration"
celebrateGui.ResetOnSpawn = false
celebrateGui.IgnoreGuiInset = true
celebrateGui.DisplayOrder = DISPLAY_ORDER + 1
celebrateGui.Enabled = false
celebrateGui.Parent = gui.Parent

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Interactable = false
flash.Parent = celebrateGui
local flashGradient = Instance.new("UIGradient")
flashGradient.Color = RAINBOW
flashGradient.Rotation = 45
flashGradient.Parent = flash

local thanks = Instance.new("TextLabel")
thanks.Name = "Thanks"
thanks.AnchorPoint = Vector2.new(0.5, 0.5)
thanks.Position = UDim2.fromScale(0.5, 0.4)
thanks.Size = UDim2.fromScale(0.6, 0.14)
thanks.BackgroundTransparency = 1
thanks.FontFace = Font.fromEnum(Enum.Font.SourceSansBold)
thanks.Text = CELEBRATE_TEXT
thanks.TextColor3 = Color3.new(1, 1, 1)
thanks.TextScaled = true
thanks.TextTransparency = 1
thanks.Interactable = false
thanks.Parent = celebrateGui
local thanksStroke = Instance.new("UIStroke")
thanksStroke.Color = Color3.new(0, 0, 0)
thanksStroke.Thickness = 4
thanksStroke.Transparency = 1
thanksStroke.Parent = thanks
local thanksScale = Instance.new("UIScale")
thanksScale.Parent = thanks

local uiSounds = soundService:FindFirstChild("UISounds")
local cashSound = if uiSounds then uiSounds:FindFirstChild("Cash") else nil

--// State
local active = false
local celebrateId = 0
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

-- A short burst once a purchase goes through: a bright rainbow flash, a cash sound and a big "THANK YOU!" pop.
function PurchaseEffect.celebrate()
	celebrateGui.Enabled = true
	celebrateId += 1
	local id = celebrateId

	flash.BackgroundTransparency = CELEBRATE_FLASH_TRANSPARENCY
	tweenService:Create(flash, CELEBRATE_FADE, { BackgroundTransparency = 1 }):Play()

	thanks.TextTransparency = 0
	thanksStroke.Transparency = 0
	thanksScale.Scale = 0.3
	thanks.Rotation = -8
	tweenService:Create(thanksScale, CELEBRATE_POP, { Scale = 1 }):Play()
	tweenService:Create(thanks, CELEBRATE_POP, { Rotation = 0 }):Play()
	if cashSound and cashSound:IsA("Sound") then
		cashSound:Play()
	end

	task.delay(CELEBRATE_HOLD, function()
		if celebrateId ~= id then
			return
		end
		tweenService:Create(thanks, CELEBRATE_FADE, { TextTransparency = 1 }):Play()
		local fade = tweenService:Create(thanksStroke, CELEBRATE_FADE, { Transparency = 1 })
		fade.Completed:Once(function()
			if celebrateId == id then
				celebrateGui.Enabled = false
			end
		end)
		fade:Play()
	end)
end

marketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, purchased: boolean)
	if userId == player.UserId then
		PurchaseEffect.stop()
		if purchased then
			PurchaseEffect.celebrate()
		end
	end
end)

marketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchaser: Player, _gamePassId: number, purchased: boolean)
	if purchaser == player then
		PurchaseEffect.stop()
		if purchased then
			PurchaseEffect.celebrate()
		end
	end
end)

-- The server refusing a product prompt (e.g. Skip Rebirth at max) sends an error alert and no prompt opens, so the effect ends there.
task.spawn(function()
	network.waitUntilReadyAsync()
	network.connectEvent(network.RemoteEvents.ShowAlert, function(_text: string, kind: string?)
		if kind == "error" then
			PurchaseEffect.stop()
		end
	end)
end)

return PurchaseEffect
