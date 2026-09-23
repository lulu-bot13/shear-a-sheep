--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local contextActionService = game:GetService("ContextActionService")
local collectionService = game:GetService("CollectionService")

--// Player
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid", 5)
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Configurations
-- TODO: Replace with a real shearing animation asset once one exists.
local SHEAR_ANIMATION_ID = ""
local CAMERA_SIDE_OFFSET = 8
local CAMERA_HEIGHT_OFFSET = 5

--// Variables
local currentSheep: Model? = nil
local healthChangedConnection: RBXScriptConnection? = nil
local defaultWalkSpeed = humanoid.WalkSpeed
local defaultJumpPower = humanoid.JumpPower

-- local animator = humanoid:WaitForChild("Animator") :: Animator
-- local shearAnimation = Instance.new("Animation")
-- shearAnimation.AnimationId = SHEAR_ANIMATION_ID ~= "" and SHEAR_ANIMATION_ID
-- local shearAnimationTrack = animator:LoadAnimation(shearAnimation)

--[[
    Minimalistic health bar for the sheep currently being sheared. Built
    entirely in script (no StarterGui counterpart exists in this repo) and
    shown/hidden alongside the shearing lifecycle.
]]
local playerGui = player:WaitForChild("PlayerGui")

local healthBarGui = Instance.new("ScreenGui")
healthBarGui.Name = "ShearHealthUI"
healthBarGui.ResetOnSpawn = false
healthBarGui.IgnoreGuiInset = true

local healthBarTrack = Instance.new("Frame")
healthBarTrack.Name = "HealthBarTrack"
healthBarTrack.AnchorPoint = Vector2.new(0.5, 0.5)
healthBarTrack.Position = UDim2.fromScale(0.5, 0.85)
healthBarTrack.Size = UDim2.fromOffset(300, 22)
healthBarTrack.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
healthBarTrack.BorderSizePixel = 0
healthBarTrack.Visible = false
healthBarTrack.Parent = healthBarGui

local healthBarTrackCorner = Instance.new("UICorner")
healthBarTrackCorner.CornerRadius = UDim.new(1, 0)
healthBarTrackCorner.Parent = healthBarTrack

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "Fill"
healthBarFill.Size = UDim2.fromScale(1, 1)
healthBarFill.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
healthBarFill.BorderSizePixel = 0
healthBarFill.Parent = healthBarTrack

local healthBarFillCorner = Instance.new("UICorner")
healthBarFillCorner.CornerRadius = UDim.new(1, 0)
healthBarFillCorner.Parent = healthBarFill

healthBarGui.Parent = playerGui

--[[
    Updates the fill bar's width to reflect the given health ratio.
]]
local function updateHealthBar(current: number, max: number)
	local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
	healthBarFill.Size = UDim2.fromScale(ratio, 1)
end

--[[
    Points the camera at a fixed CFrame framing both the player and the
    sheep from the side. Computed once on activation since neither the
    player nor the sheep move while shearing is in progress.
]]
local function faceCameraAtShearing(sheepModel: Model)
	local camera = workspace.CurrentCamera
	local sheepPart = sheepModel.PrimaryPart or sheepModel:FindFirstChild("HumanoidRootPart")
	if not camera or not sheepPart then return end

	local midpoint = (humanoidRootPart.Position + sheepPart.Position) / 2
	local separation = humanoidRootPart.Position - sheepPart.Position

	local flatSeparation = Vector3.new(separation.X, 0, separation.Z)
	if flatSeparation.Magnitude == 0 then
		flatSeparation = Vector3.new(0, 0, 1)
	end
	local sideDirection = Vector3.new(-flatSeparation.Unit.Z, 0, flatSeparation.Unit.X)

	local cameraPosition = midpoint + sideDirection * CAMERA_SIDE_OFFSET + Vector3.new(0, CAMERA_HEIGHT_OFFSET, 0)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(cameraPosition, midpoint)
end

--[[
    Finds the active sheep Model with the given unique id. Sheep ids are
    unique per-instance (unlike Name, which is shared by every clone of the
    same species), so this is safe even with multiple sheep of one type
    alive at once.
]]
local function findSheepById(sheepId: number): Model?
	for _, sheepModel in collectionService:GetTagged("Sheep") do
		if sheepModel:GetAttribute("id") == sheepId then
			return sheepModel :: Model
		end
	end

	return nil
end

--[[
    Halts the player's movement and locks the camera onto the player and
    sheep so they can shear in place.
]]
local function startShearing(sheepId: number)
	local sheepModel = findSheepById(sheepId)
	if not sheepModel then
		warn(`No active sheep found for id: {sheepId}`)
		return
	end

	currentSheep = sheepModel

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	faceCameraAtShearing(sheepModel)

	updateHealthBar(sheepModel:GetAttribute("ShearHealth"), sheepModel:GetAttribute("MaxShearHealth"))
	healthBarTrack.Visible = true

	healthChangedConnection = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateHealthBar(sheepModel:GetAttribute("ShearHealth"), sheepModel:GetAttribute("MaxShearHealth"))
	end)

	contextActionService:BindAction("Shear", function(actionName, inputState)
		if actionName ~= "Shear" then return end
		if inputState ~= Enum.UserInputState.Begin then return end
		if not currentSheep then return end

		print(`Shearing action is clicked`)
		network.fireServer(network.RemoteEvents.Shear)
		-- shearAnimationTrack:Play()
	end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)
end

--[[
    Restores normal movement and camera control once shearing has ended
    (the sheep was fully sheared and removed by the server).
]]
local function stopShearing()
	contextActionService:UnbindAction("Shear")

	-- if shearAnimationTrack.IsPlaying then
	-- 	shearAnimationTrack:Stop()
	-- end

	currentSheep = nil

	if healthChangedConnection then
		healthChangedConnection:Disconnect()
		healthChangedConnection = nil
	end
	healthBarTrack.Visible = false

	humanoid.WalkSpeed = defaultWalkSpeed
	humanoid.JumpPower = defaultJumpPower

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

--[[
    This script isn't loaded through ModuleLoader's Setup/Start lifecycle
    (it lives under StarterPlayerScripts, not ReplicatedStorage.Source), so
    there's no guarantee ClientStart.local.luau has already called
    network.startClientAsync() by the time this line runs. Wait for it
    explicitly rather than racing it.
]]
network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ActivateShearing, function(sheepId: number)
	startShearing(sheepId)
end)

network.connectEvent(network.RemoteEvents.DeactivateShearing, function()
	stopShearing()
end)
