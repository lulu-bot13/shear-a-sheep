--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local contextActionService = game:GetService("ContextActionService")
local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

--// Player
local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid", 5)
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Configurations
local CAMERA_SIDE_OFFSET = 8
local CAMERA_HEIGHT_OFFSET = 5
local WOOL_BURST_COUNT = 18
local FILL_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LOW_HEALTH_COLOR = Color3.fromRGB(220, 60, 60)
local FULL_HEALTH_COLOR = Color3.fromRGB(90, 200, 90)

--// Variables
local currentSheep: Model? = nil
local healthChangedConnection: RBXScriptConnection? = nil
local defaultWalkSpeed = humanoid.WalkSpeed
local defaultJumpPower = humanoid.JumpPower
local shearTool: Tool? = nil
local shearToolActivatedConnection: RBXScriptConnection? = nil

--[[
    Health bar for the sheep currently being sheared. Built entirely in
    script (no StarterGui counterpart exists in this repo) and shown/hidden
    alongside the shearing lifecycle. The fill tweens smoothly, shifts from
    green to red as health drops, shows a "current / max" label, and gives
    a quick punch-scale on every hit so shears feel like they land.
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

local healthBarScale = Instance.new("UIScale")
healthBarScale.Scale = 1
healthBarScale.Parent = healthBarTrack

local healthBarFill = Instance.new("Frame")
healthBarFill.Name = "Fill"
healthBarFill.Size = UDim2.fromScale(1, 1)
healthBarFill.BackgroundColor3 = FULL_HEALTH_COLOR
healthBarFill.BorderSizePixel = 0
healthBarFill.Parent = healthBarTrack

local healthBarFillCorner = Instance.new("UICorner")
healthBarFillCorner.CornerRadius = UDim.new(1, 0)
healthBarFillCorner.Parent = healthBarFill

local healthBarText = Instance.new("TextLabel")
healthBarText.Name = "HealthText"
healthBarText.BackgroundTransparency = 1
healthBarText.Size = UDim2.fromScale(1, 1)
healthBarText.Font = Enum.Font.GothamBold
healthBarText.TextSize = 14
healthBarText.TextColor3 = Color3.fromRGB(255, 255, 255)
healthBarText.Text = ""
healthBarText.ZIndex = 2
healthBarText.Parent = healthBarTrack

local healthBarTextStroke = Instance.new("UIStroke")
healthBarTextStroke.Thickness = 1.5
healthBarTextStroke.Color = Color3.fromRGB(0, 0, 0)
healthBarTextStroke.Parent = healthBarText

healthBarGui.Parent = playerGui

--[[
    Updates the fill bar's width, color, and label to reflect the given
    health ratio -- tweened rather than snapped -- and gives the bar a
    quick punch-scale so each hit feels like it landed.
]]
local function updateHealthBar(current: number, max: number)
	local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0

	tweenService:Create(healthBarFill, FILL_TWEEN_INFO, {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = LOW_HEALTH_COLOR:Lerp(FULL_HEALTH_COLOR, ratio),
	}):Play()

	healthBarText.Text = `{math.max(current, 0)} / {max}`

	healthBarScale.Scale = 1.12
	tweenService:Create(healthBarScale, PUNCH_TWEEN_INFO, { Scale = 1 }):Play()
end

--[[
    Bursts a handful of wool particles off the sheep's Torso. Called on
    every individual shear hit, not just the final one, for per-hit
    feedback. No-ops quietly if the sheep model doesn't have the emitter
    (e.g. an older clone from before it was added to the template).
]]
local function emitWoolBurst(sheepModel: Model)
	local torso = sheepModel:FindFirstChild("Torso")
	local emitter = torso and torso:FindFirstChild("WoolBurst") :: ParticleEmitter?
	if emitter then
		emitter:Emit(WOOL_BURST_COUNT)
	end
end

--[[
    Points the camera at a fixed CFrame framing both the player and the
    sheep from the side. Takes explicit positions (the pen's PlayerPos and
    SheepPos marks, sent by the server) rather than reading live character
    positions, so the shot is stable and identical for every pen.
]]
local function faceCameraAtShearing(sheepPosition: Vector3, playerPosition: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local midpoint = (playerPosition + sheepPosition) / 2
	local separation = playerPosition - sheepPosition

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
    Finds the player's "Shear" Tool, whether it's sitting in their Backpack
    or already equipped in their Character (checked fresh each call rather
    than cached, since which one it's in changes as it gets equipped).
]]
local function findShearTool(): Tool?
	local backpack = player:FindFirstChild("Backpack")
	local fromBackpack = backpack and backpack:FindFirstChild("Shear")
	if fromBackpack and fromBackpack:IsA("Tool") then
		return fromBackpack
	end

	local fromCharacter = character:FindFirstChild("Shear")
	if fromCharacter and fromCharacter:IsA("Tool") then
		return fromCharacter
	end

	return nil
end

--[[
    Halts the player's movement and locks the camera onto the player and
    sheep so they can shear in place.
]]
local function startShearing(sheepId: number, sheepPosition: Vector3?, playerPosition: Vector3?)
	local sheepModel = findSheepById(sheepId)
	if not sheepModel then
		warn(`No active sheep found for id: {sheepId}`)
		return
	end

	currentSheep = sheepModel

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	-- Prefer the pen's fixed marks (sent by the server); fall back to live
	-- positions only if a sheep somehow isn't tied to a pen.
	local sheepPart = sheepModel.PrimaryPart or sheepModel:FindFirstChild("HumanoidRootPart")
	local resolvedSheepPosition = sheepPosition or (sheepPart and sheepPart.Position)
	local resolvedPlayerPosition = playerPosition or humanoidRootPart.Position

	if resolvedSheepPosition then
		faceCameraAtShearing(resolvedSheepPosition, resolvedPlayerPosition)
	end

	updateHealthBar(sheepModel:GetAttribute("ShearHealth"), sheepModel:GetAttribute("MaxShearHealth"))
	healthBarTrack.Visible = true

	healthChangedConnection = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateHealthBar(sheepModel:GetAttribute("ShearHealth"), sheepModel:GetAttribute("MaxShearHealth"))
		emitWoolBurst(sheepModel)
	end)

	-- Equip the real Shear tool and drive shearing off its Activated event
	-- (a normal click/tap while holding it) rather than a raw input bind.
	-- With no custom Animation on the tool, equipping it makes the
	-- character's default Animate script play its built-in tool-swing
	-- animation automatically on every Activated -- a real swinging-shears
	-- motion with no animation asset needed.
	shearTool = findShearTool()
	if shearTool then
		humanoid:EquipTool(shearTool)
		shearToolActivatedConnection = shearTool.Activated:Connect(function()
			if not currentSheep then return end
			network.fireServer(network.RemoteEvents.Shear)
		end)
	else
		warn("Shear tool not found in Backpack or Character; falling back to click-to-shear without a tool.")
		contextActionService:BindAction("Shear", function(actionName, inputState)
			if actionName ~= "Shear" then return end
			if inputState ~= Enum.UserInputState.Begin then return end
			if not currentSheep then return end

			network.fireServer(network.RemoteEvents.Shear)
		end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)
	end
end

--[[
    Restores normal movement and camera control once shearing has ended
    (the sheep was fully sheared and removed by the server).
]]
local function stopShearing()
	if shearToolActivatedConnection then
		shearToolActivatedConnection:Disconnect()
		shearToolActivatedConnection = nil
	end

	if shearTool then
		humanoid:UnequipTools()
		shearTool = nil
	else
		contextActionService:UnbindAction("Shear")
	end

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

network.connectEvent(network.RemoteEvents.ActivateShearing, function(sheepId: number, sheepPosition: Vector3?, playerPosition: Vector3?)
	startShearing(sheepId, sheepPosition, playerPosition)
end)

network.connectEvent(network.RemoteEvents.DeactivateShearing, function()
	stopShearing()
end)
