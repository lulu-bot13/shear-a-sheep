--[[
	The "new sheep" popup (StarterGui.SheepUnlocked): pops up for ~2 seconds with the unlocked sheep spinning in the Template.
	Reuses the one Template and caches one preview model per sheep type, so nothing is cloned again on later unlocks.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SheepUnlockClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sheepModels = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Sheeps")

local unlockGui = playerGui:WaitForChild("SheepUnlocked") :: ScreenGui
local container = unlockGui:WaitForChild("UnlockedSheepContainer") :: GuiObject
local title = unlockGui:FindFirstChild("Title") :: GuiObject?
local template = container:WaitForChild("Template") :: GuiObject
local viewport = template:WaitForChild("ViewportFrame") :: ViewportFrame
local nameLabel = template:WaitForChild("SheepName") :: TextLabel
local rarityLabel = template:WaitForChild("Rarity") :: TextLabel

--// Sounds
local unlockSound = soundService:WaitForChild("UISounds"):FindFirstChild("UnlockedSheep") :: Sound? -- the sound played on every unlock

--// Configs
local POP_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local HOLD_SECONDS = 2 - POP_IN.Time - POP_OUT.Time -- the whole popup lasts 2 seconds
local SPIN_SPEED = math.rad(180) -- per second
local MODEL_FRONT_YAW = 0 -- turn this if a sheep model's face isn't on its front (-Z) side
local CAMERA_PITCH = math.rad(15)
local CAMERA_FOV = 40

type Preview = {
	model: Model,
	center: Vector3, -- spun around (the model's pivot sits at the origin)
	cameraCFrame: CFrame,
}

type Unlock = {
	sheepType: string,
	name: string,
	rarity: string,
	color: Color3,
}

--// State
local previewCache: { [string]: Preview } = {}
local queue: { Unlock } = {}
local playing = false
local currentPreview: Preview? = nil
local spinAngle = 0

local camera = Instance.new("Camera")
camera.FieldOfView = CAMERA_FOV
camera.Parent = viewport
viewport.CurrentCamera = camera

-- One UIScale per popped frame, made once and tweened every time.
local function getScale(gui: GuiObject): UIScale
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = gui
	end
	return scale
end

local poppedScales = { getScale(container) }
if title then
	table.insert(poppedScales, getScale(title))
end

--// Previews ----------------------------------------------------------------------

-- Builds a sheep type's scriptless, anchored preview the first time it's needed; after that the cached one is reused.
local function getPreview(sheepType: string): Preview?
	local cached = previewCache[sheepType]
	if cached then
		return cached
	end

	local babyModels = sheepModels:FindFirstChild("BabySheeps")
	local source = sheepModels:FindFirstChild(sheepType) or (babyModels and babyModels:FindFirstChild(sheepType))
	if not source or not source:IsA("Model") then
		return nil
	end

	local model = source:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model:PivotTo(CFrame.new())

	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = boxCFrame.Position
	local distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(CAMERA_FOV / 2))
	local direction = (CFrame.Angles(0, math.pi + MODEL_FRONT_YAW, 0) * CFrame.Angles(-CAMERA_PITCH, 0, 0)).LookVector

	local preview: Preview = {
		model = model,
		center = center,
		cameraCFrame = CFrame.lookAt(center - direction * distance, center),
	}
	previewCache[sheepType] = preview
	return preview
end

-- Only the shown sheep is parented to the viewport; the others wait in the cache unparented.
local function showPreview(preview: Preview?)
	if currentPreview and currentPreview ~= preview then
		currentPreview.model.Parent = nil
	end
	currentPreview = preview
	if preview then
		spinAngle = 0
		preview.model:PivotTo(CFrame.new())
		preview.model.Parent = viewport
		camera.CFrame = preview.cameraCFrame
	end
end

local function onSpin(deltaTime: number)
	local preview = currentPreview
	if preview then
		spinAngle = (spinAngle + deltaTime * SPIN_SPEED) % (math.pi * 2)
		local center = preview.center
		preview.model:PivotTo(CFrame.new(center) * CFrame.Angles(0, spinAngle, 0) * CFrame.new(-center))
	end
end

--// Popup -------------------------------------------------------------------------

local function tweenScales(info: TweenInfo, scale: number): Tween
	local last: Tween
	for _, uiScale in poppedScales do
		last = tweenService:Create(uiScale, info, { Scale = scale })
		last:Play()
	end
	return last
end

local function play(unlock: Unlock)
	nameLabel.Text = unlock.name
	rarityLabel.Text = unlock.rarity
	rarityLabel.TextColor3 = unlock.color
	template.Visible = true
	showPreview(getPreview(unlock.sheepType))

	for _, uiScale in poppedScales do
		uiScale.Scale = 0
	end
	unlockGui.Enabled = true
	if unlockSound then
		unlockSound:Play()
	end

	-- The spin only runs while the popup is on screen.
	local spinConnection = runService.RenderStepped:Connect(onSpin)
	tweenScales(POP_IN, 1)
	task.wait(POP_IN.Time + HOLD_SECONDS)
	tweenScales(POP_OUT, 0).Completed:Wait()
	spinConnection:Disconnect()

	unlockGui.Enabled = false
	showPreview(nil)
end

-- Unlocks that arrive while one is showing wait their turn instead of overlapping.
local function playQueue()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		play(table.remove(queue, 1) :: Unlock)
	end
	playing = false
end

--// Setup -------------------------------------------------------------------------------

unlockGui.Enabled = false

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.SheepUnlocked, function(sheepType: string, name: string, rarity: string, color: Color3)
	table.insert(queue, { sheepType = sheepType, name = name, rarity = rarity, color = color })
	task.spawn(playQueue)
end)
