--[[
	Client side of the shearing timing mini-game.

	Drives the hand-built `Shearing` ScreenGui (StarterGui.Shearing). The names this script looks for:

		Shearing [ScreenGui]
		├─ PopupLayer [Frame]            floating damage numbers are added here
		├─ SheepHUD [Frame]
		│  ├─ SheepName [TextLabel]
		│  └─ HealthBar [Frame]
		│     ├─ Fill [Frame]            its width follows the sheep's wool
		│     └─ HealthText [TextLabel]
		├─ TimingBar [Frame]
		│  ├─ Zones [Frame]              the track the cursor runs along
		│  │  └─ Frame [Frame]           the PERFECT zone (the only zone drawn)
		│  ├─ Cursor [Frame]
		│  └─ Hint [TextLabel]
		└─ Exit [TextButton]

	While a sheep is being sheared the camera sits behind it, the cursor bounces along the track and the
	sweet spot moves after every attempt. Click, tap, Space or gamepad A to shear. The client only moves the
	cursor and reports where it was when the player pressed; the server scores the press and takes the wool
	off. The client predicts the result with the same maths (ShearTiming) so the feedback is instant.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearingClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local contextActionService = game:GetService("ContextActionService")
local debris = game:GetService("Debris")
local guiService = game:GetService("GuiService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")
local players = game:GetService("Players")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local ShearTiming = require(replicatedStorage.Shared.Utils.ShearTiming)
local ShearTimingData = require(replicatedStorage.Shared.Constants.ShearTimingData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shearingGui = playerGui:WaitForChild("Shearing") :: ScreenGui
local popupLayer = shearingGui:WaitForChild("PopupLayer") :: Frame
local sheepHud = shearingGui:WaitForChild("SheepHUD") :: Frame
local sheepNameLabel = sheepHud:WaitForChild("SheepName") :: TextLabel
local healthBar = sheepHud:WaitForChild("HealthBar") :: Frame
local healthFill = healthBar:WaitForChild("Fill") :: Frame
local healthText = healthBar:WaitForChild("HealthText") :: TextLabel
local timingBar = shearingGui:WaitForChild("TimingBar") :: Frame
local zoneTrack = timingBar:WaitForChild("Zones") :: Frame
local perfectZone = zoneTrack:WaitForChild("Frame") :: Frame
local cursor = timingBar:WaitForChild("Cursor") :: Frame
local hintLabel = timingBar:WaitForChild("Hint") :: TextLabel
local exitButton = shearingGui:WaitForChild("Exit") :: TextButton

-- The script keeps references into this GUI for the whole session, so it must survive respawns.
shearingGui.ResetOnSpawn = false

--// Animations
local shearToolAnim = replicatedStorage.Assets.Animations.ShearTool
local shearRigAnim = replicatedStorage.Assets.Animations.ShearRig

--// Camera tuning (studs / degrees). Tweak these to reframe the shot.
local CAMERA_DISTANCE = 5.5
local CAMERA_HEIGHT = 3.2
local CAMERA_LOOK_AHEAD = 2.2
local CAMERA_LOOK_HEIGHT = 0.6
local CAMERA_FOV = 60
local CAMERA_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

--// Input: any of these shears while the timing bar is up. Keys go through ContextActionService (so Space
--// doesn't also try to jump); clicks and taps through UserInputService (so the Exit button still works).
local PRESS_INPUT_TYPES = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local PRESS_KEYS = { Enum.KeyCode.Space, Enum.KeyCode.ButtonA }
local PRESS_ACTION = "ShearTimingPress"

--// Wool effects
local WOOL_BURST_COUNT = 18
local WOOL_CHUNK_LIFETIME = 1.4

--// Style
local POPUP_FONT = sheepNameLabel.Font -- popups match the font of the GUI
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Tier colours come from ShearTimingData.TierColors; these are used for any tier it doesn't list.
local DEFAULT_TIER_COLORS: { [string]: Color3 } = {
	PERFECT = Color3.fromRGB(72, 255, 69),
	GREAT = Color3.fromRGB(150, 235, 80),
	GOOD = Color3.fromRGB(240, 205, 70),
	POOR = Color3.fromRGB(240, 150, 60),
	MISS = Color3.fromRGB(190, 192, 202),
}

local function getTierColor(tier: string): Color3
	local colors = ShearTimingData.TierColors :: { [string]: Color3 }
	return colors[tier] or DEFAULT_TIER_COLORS[tier] or WHITE
end

--// Layout, read from the GUI as it was built in Studio
local TRACK_LEFT = zoneTrack.Position.X.Scale -- the track's span inside TimingBar, so the cursor lines up with it
local TRACK_WIDTH = zoneTrack.Size.X.Scale
local CURSOR_Y = cursor.Position.Y
local TIMING_HOME = timingBar.Position

-- Tells WoolCollectClient to play the wool effect (origin: Vector3, woolAmount: number).
local woolCollected = player:FindFirstChild("WoolCollected") :: BindableEvent?
if not woolCollected then
	woolCollected = Instance.new("BindableEvent")
	woolCollected.Name = "WoolCollected"
	woolCollected.Parent = player
end

--// Character
local character: Model
local humanoid: Humanoid
local humanoidRootPart: BasePart

--// State
local inStation = false -- camera locked at the pen (from the first START SHEARING until Leave)
local shearing = false -- a sheep is currently being sheared (timing bar up)
local stationToken = 0 -- bumps every time the station ends, so a late "start" can tell it's stale
local currentSheep: Model? = nil
local shearTool: Tool? = nil
local healthConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local lastSheepPosition: Vector3? = nil
local savedWalkSpeed = 16
local savedFieldOfView = 70

-- The live attempt, as sent by the server plus when it arrived and whether it's been used up.
local attempt: any = nil

--// Character handling ---------------------------------------------------------

local endMinigame: () -> ()
local exitStation: () -> ()

local function bindCharacter(newCharacter: Model)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid
	humanoidRootPart = newCharacter:WaitForChild("HumanoidRootPart", 10) :: BasePart

	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.Died:Connect(function()
			if shearing then
				endMinigame()
			end
			if inStation then
				exitStation()
			end
		end)
	end
end

bindCharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(bindCharacter)

--// GUI setup --------------------------------------------------------------------

-- Everything starts hidden; the station and the mini-game switch the pieces on.
shearingGui.Enabled = false
sheepHud.Visible = false
timingBar.Visible = false
exitButton.Visible = false

local healthScale = Instance.new("UIScale")
healthScale.Parent = healthBar

local timingScale = Instance.new("UIScale")
timingScale.Parent = timingBar

-- The cursor is positioned by its centre.
cursor.AnchorPoint = Vector2.new(0.5, cursor.AnchorPoint.Y)

-- Your Frame is the PERFECT zone and the only zone drawn: the wider tiers still score, but they aren't shown.
perfectZone.ZIndex = 1
cursor.ZIndex = 2

-- Snip sound (only when a sound id is set in ShearTimingData).
local shearSound: Sound? = nil
if ShearTimingData.ShearSoundId ~= "" then
	local sound = Instance.new("Sound")
	sound.Name = "ShearSnip"
	sound.SoundId = ShearTimingData.ShearSoundId
	sound.Volume = ShearTimingData.ShearSoundVolume
	sound.Parent = shearingGui
	shearSound = sound
end

--// Small helpers -----------------------------------------------------------------

-- The game's own HUD (wool / money labels) is hidden while a sheep is being sheared.
local function setMainHudVisible(visible: boolean)
	local main = playerGui:FindFirstChild("Main")
	if main and main:IsA("ScreenGui") then
		main.Enabled = visible
	end
end

local function addStroke(instance: Instance, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = instance
	return stroke
end

-- Floating text at a screen position that drifts upward and fades out.
local function spawnPopup(text: string, screenPosition: Vector2, color: Color3, textSize: number, rise: number, duration: number): TextLabel
	local position = screenPosition - popupLayer.AbsolutePosition

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = POPUP_FONT
	label.TextSize = textSize
	label.TextColor3 = color
	label.Text = text
	label.ZIndex = 4
	label.Parent = popupLayer
	local stroke = addStroke(label, 3)

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenService:Create(label, info, {
		Position = UDim2.fromOffset(position.X, position.Y - rise),
		TextTransparency = 1,
	}):Play()
	tweenService:Create(stroke, info, { Transparency = 1 }):Play()

	task.delay(duration, function()
		label:Destroy()
	end)

	return label
end

local function updateHealthBar(current: number, maximum: number)
	local ratio = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0

	tweenService:Create(healthFill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()

	healthText.Text = `{math.ceil(math.max(current, 0))}/{maximum}`

	healthScale.Scale = 1.05
	tweenService:Create(healthScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function emitWoolBurst(sheepModel: Model)
	local torso = sheepModel:FindFirstChild("Torso")
	local emitter = torso and torso:FindFirstChild("WoolBurst") :: ParticleEmitter?
	if emitter then
		emitter:Emit(WOOL_BURST_COUNT)
	end
end

local function getSheepRoot(): BasePart?
	local sheepModel = currentSheep
	if not sheepModel then
		return nil
	end
	return (sheepModel.PrimaryPart or sheepModel:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- Little wool spheres (the sheep's wool colour) that fly out from `origin` in the `outward` direction.
local function spawnWoolChunks(origin: Vector3, outward: Vector3, count: number, sizeScale: number)
	local torso = if currentSheep then currentSheep:FindFirstChild("Torso") else nil
	local color = if torso and torso:IsA("BasePart") then torso.Color else WHITE

	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Name = "WoolChunk"
		chunk.Shape = Enum.PartType.Ball
		chunk.Size = Vector3.one * ((0.5 + math.random() * 0.4) * sizeScale)
		chunk.Color = color
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.CanCollide = false
		chunk.CanTouch = false
		chunk.CanQuery = false
		chunk.CastShadow = false
		chunk.CFrame = CFrame.new(origin)
		chunk.Parent = workspace

		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.5, math.random() - 0.5)
		local direction = (outward + spread * 0.8).Unit
		chunk.AssemblyLinearVelocity = direction * (10 + math.random() * 6) + Vector3.new(0, 8 + math.random() * 4, 0)

		-- Shrink away just before it's removed.
		task.delay(WOOL_CHUNK_LIFETIME - 0.35, function()
			if chunk.Parent then
				tweenService:Create(chunk, TweenInfo.new(0.35), { Size = Vector3.one * 0.05 }):Play()
			end
		end)
		debris:AddItem(chunk, WOOL_CHUNK_LIFETIME)
	end
end

-- Throws `count` chunks off the side of the sheep that faces the camera.
local function flyWool(count: number, sizeScale: number)
	local sheepRoot = getSheepRoot()
	local camera = workspace.CurrentCamera
	if count <= 0 or not sheepRoot or not camera then
		return
	end

	local toCamera = camera.CFrame.Position - sheepRoot.Position
	toCamera = Vector3.new(toCamera.X, 0, toCamera.Z)
	local outward = if toCamera.Magnitude > 0.05 then toCamera.Unit else sheepRoot.CFrame.RightVector

	for _ = 1, count do
		local scatter = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 1.6
		spawnWoolChunks(sheepRoot.Position + Vector3.new(0, 0.8, 0) + scatter, outward, 1, sizeScale)
	end
end

--[[
	Animation tracks are loaded once and replayed on every swing. Loading a new track per swing leaks
	one track each time until the animator's 64 track limit is hit and animations stop playing.
	The caches are weak, so a track goes away with its tool (shear swapped) or animator (respawn).
]]--
local toolTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any
local rigTracks: { [Animator]: AnimationTrack } = setmetatable({}, { __mode = "k" }) :: any

local function getTrack(cache: { [Animator]: AnimationTrack }, animator: Animator, animation: Animation): AnimationTrack
	local track = cache[animator]
	if not track then
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		cache[animator] = track
	end
	return track
end

local function playShearAnimation()
	local tool = shearTool
	if not tool or tool.Parent ~= character then
		return
	end
	local toolAnimationController = tool:FindFirstChild("AnimationController")
	local toolAnimator = toolAnimationController and toolAnimationController:FindFirstChildOfClass("Animator")
	local characterAnimator = humanoid:FindFirstChildOfClass("Animator")
	if not toolAnimator or not characterAnimator then
		return
	end

	-- Electric shears crackle on every snip (other players see it via the tool's "Snips" attribute).
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "ElectricBurst" then
			descendant:Emit(18)
		end
	end

	-- Tracks aren't looped, so each one stops by itself when the swing ends.
	local shearToolTrack = getTrack(toolTracks, toolAnimator, shearToolAnim)
	local shearRigTrack = getTrack(rigTracks, characterAnimator, shearRigAnim)
	if not shearToolTrack.IsPlaying then
		shearToolTrack:Play()
	end
	if not shearRigTrack.IsPlaying then
		shearRigTrack:Play()
	end
end

--// Timing bar ------------------------------------------------------------------------

-- Moves the cursor to a bar position (0..1) along the zone track.
local function setCursor(position: number)
	cursor.Position = UDim2.new(TRACK_LEFT + position * TRACK_WIDTH, 0, CURSOR_Y.Scale, CURSOR_Y.Offset)
end

-- Puts a zone frame over [centre - halfWidth, centre + halfWidth] of the track, kept inside it.
local function placeZone(zone: Frame, center: number, halfWidth: number)
	local left = math.max(center - halfWidth, 0)
	local right = math.min(center + halfWidth, 1)
	zone.Position = UDim2.new(left, 0, zone.Position.Y.Scale, zone.Position.Y.Offset)
	zone.Size = UDim2.new(right - left, 0, zone.Size.Y.Scale, zone.Size.Y.Offset)
end

local function layoutAttempt(current: any)
	placeZone(perfectZone, current.sweetSpot, current.zones.perfect)

	cursor.BackgroundTransparency = 0
	setCursor(ShearTiming.getCursorPosition(current.cursorStart, current.cursorSpeed, 0))
end

-- A quick punch for good hits and a little shake for a miss.
local function animateBar(tier: string)
	if tier == "PERFECT" or tier == "GREAT" then
		timingScale.Scale = if tier == "PERFECT" then 1.1 else 1.05
		tweenService:Create(timingScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	elseif tier == "MISS" then
		task.spawn(function()
			for _, offset in { -6, 6, -4, 0 } do
				timingBar.Position = UDim2.new(TIMING_HOME.X.Scale, TIMING_HOME.X.Offset + offset, TIMING_HOME.Y.Scale, TIMING_HOME.Y.Offset)
				task.wait(0.03)
			end
		end)
	end
end

-- The damage number the server reports for a hit, popping up over the sheep (the tier only sets its colour and size).
local function showDamage(tier: string, damage: number)
	local camera = workspace.CurrentCamera
	local sheepRoot = getSheepRoot()
	if not camera or not sheepRoot then
		return
	end

	local viewportPoint = camera:WorldToViewportPoint(sheepRoot.Position + Vector3.new(0, 1.6, 0))
	local screenPoint = Vector2.new(viewportPoint.X, viewportPoint.Y)
	if not shearingGui.IgnoreGuiInset then
		screenPoint += guiService:GetGuiInset()
	end
	screenPoint += Vector2.new(math.random(-70, 70), math.random(-30, 20))

	local big = tier == "PERFECT"
	local text = if damage > 0 then `-{damage}` else "MISS"
	local size = if big then 54 else if tier == "MISS" then 30 else 38
	local label = spawnPopup(text, screenPoint, getTierColor(tier), size, if big then 90 else 70, if big then 0.85 else 0.7)

	-- Punch in: starts small and overshoots, so every hit lands with a thump.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	tweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if big then 1.3 else 1 }):Play()
	label.Rotation = math.random(-8, 8)
end

local function showResult(tier: string)
	local big = tier == "PERFECT"
	local sheepRoot = getSheepRoot()
	if sheepRoot then
		lastSheepPosition = sheepRoot.Position
	end
	animateBar(tier)
	cursor.BackgroundTransparency = 0.4

	if shearSound and tier ~= "MISS" then
		shearSound.PlaybackSpeed = ShearTimingData.TierPitch[tier]
		shearSound:Play()
	end

	if tier ~= "MISS" then
		playShearAnimation()
		flyWool(ShearTimingData.WoolChunks[tier], if big then 1.4 else 1)
		if (big or tier == "GREAT") and currentSheep then
			emitWoolBurst(currentSheep)
		end
	end
end

-- The player pressed: lock the cursor, tell the server where it was and predict the result.
local function press()
	local current = attempt
	if not shearing or not current or current.done then
		return
	end

	local elapsed = os.clock() - current.receivedAt
	if elapsed > current.lifetime then
		return
	end
	current.done = true
	hintLabel.Visible = false

	local position = ShearTiming.getCursorPosition(current.cursorStart, current.cursorSpeed, elapsed)
	setCursor(position)
	network.fireServer(network.RemoteEvents.ShearPress, current.id, position)

	local tier = ShearTiming.classify(math.abs(position - current.sweetSpot), current.zones)
	showResult(tier)
end

-- Every frame: move the cursor; an attempt that runs out of time is a miss (the server agrees).
local function updateTiming()
	local current = attempt
	if not current or current.done then
		return
	end

	local elapsed = os.clock() - current.receivedAt
	if elapsed >= current.lifetime then
		current.done = true
		local position = ShearTiming.getCursorPosition(current.cursorStart, current.cursorSpeed, current.lifetime)
		setCursor(position)
		showResult("MISS")
		return
	end

	setCursor(ShearTiming.getCursorPosition(current.cursorStart, current.cursorSpeed, elapsed))
end

local function onAttempt(data: any)
	if not shearing or type(data) ~= "table" or type(data.zones) ~= "table" then
		return
	end

	attempt = {
		id = data.id,
		sweetSpot = data.sweetSpot,
		zones = data.zones,
		cursorStart = data.cursorStart,
		cursorSpeed = data.cursorSpeed,
		lifetime = data.lifetime,
		receivedAt = os.clock(),
		done = false,
	}
	layoutAttempt(attempt)
	timingBar.Visible = true
end

local function onPressAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		press()
	end
	return Enum.ContextActionResult.Sink
end

-- Clicks and taps that didn't land on a button (the Exit button, the chat...).
userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if shearing and not gameProcessed and PRESS_INPUT_TYPES[input.UserInputType] then
		press()
	end
end)

--// Station / shearing ------------------------------------------------------------------

-- Finds the active sheep Model by its unique id (waits briefly in case it hasn't replicated yet).
local function findSheepById(sheepId: number): Model?
	for _, sheepModel in collectionService:GetTagged("Sheep") do
		if sheepModel:GetAttribute("id") == sheepId then
			return sheepModel :: Model
		end
	end
	task.wait(0.1)
	return nil
end

local SHEAR_TOOL_NAMES = { "DefaultShear", "Shear" }

local function findShearTool(): Tool?
	local backpack = player:FindFirstChild("Backpack")

	local toolNames = table.clone(SHEAR_TOOL_NAMES)
	local equippedId = player:GetAttribute("ShearId")
	if type(equippedId) == "string" then
		table.insert(toolNames, 1, equippedId)
	end

	for _, toolName in toolNames do
		local fromBackpack = backpack and backpack:FindFirstChild(toolName)
		if fromBackpack and fromBackpack:IsA("Tool") then
			return fromBackpack
		end

		local fromCharacter = character:FindFirstChild(toolName)
		if fromCharacter and fromCharacter:IsA("Tool") then
			return fromCharacter
		end
	end

	warn(`ShearingClient: no shears found. Looked for {table.concat(toolNames, ", ")} in the Backpack and character.`)
	return nil
end

-- Swings the camera to sit behind the sheep, looking across it at the player.
local function frameCamera(sheepModel: Model, sheepPosition: Vector3?, playerPosition: Vector3?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local sheepRoot = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if sheepRoot then sheepRoot.Position else (sheepPosition or Vector3.zero) + Vector3.new(0, 2.5, 0)
	local playerPoint = playerPosition or humanoidRootPart.Position

	local toPlayer = Vector3.new(playerPoint.X - center.X, 0, playerPoint.Z - center.Z)
	toPlayer = if toPlayer.Magnitude > 0.01 then toPlayer.Unit else Vector3.zAxis

	local cameraPosition = center - toPlayer * CAMERA_DISTANCE + Vector3.new(0, CAMERA_HEIGHT, 0)
	local lookTarget = center + toPlayer * CAMERA_LOOK_AHEAD + Vector3.new(0, CAMERA_LOOK_HEIGHT, 0)

	camera.CameraType = Enum.CameraType.Scriptable
	tweenService:Create(camera, CAMERA_TWEEN, {
		CFrame = CFrame.lookAt(cameraPosition, lookTarget),
		FieldOfView = CAMERA_FOV,
	}):Play()
end

-- Locks the player in place at the pen and frames the camera (only the first time; later sheep reuse it).
local function enterStation(sheepModel: Model, sheepPosition: Vector3?, playerPosition: Vector3?)
	if not inStation then
		inStation = true

		savedWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = 0
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

		local camera = workspace.CurrentCamera
		if camera then
			savedFieldOfView = camera.FieldOfView
		end

		shearingGui.Enabled = true
		exitButton.Visible = true
	end

	frameCamera(sheepModel, sheepPosition, playerPosition)
end

-- Starts the timing mini-game on a sheep; the first attempt arrives from the server shortly after.
local function startMinigame(sheepModel: Model)
	shearing = true
	currentSheep = sheepModel
	attempt = nil
	setMainHudVisible(false)

	updateHealthBar(sheepModel:GetAttribute("ShearHealth") :: number, sheepModel:GetAttribute("MaxShearHealth") :: number)

	local rarityColor = sheepModel:GetAttribute("RarityColor")
	sheepNameLabel.TextColor3 = if typeof(rarityColor) == "Color3" then rarityColor:Lerp(WHITE, 0.7) else WHITE
	sheepNameLabel.Text = `{sheepModel:GetAttribute("SheepName") or sheepModel.Name} - {sheepModel:GetAttribute("Rarity") or ""}`
	sheepHud.Visible = true

	healthConnection = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateHealthBar(sheepModel:GetAttribute("ShearHealth") :: number, sheepModel:GetAttribute("MaxShearHealth") :: number)
	end)

	-- Hold the shears while working.
	shearTool = findShearTool()
	if shearTool then
		humanoid:EquipTool(shearTool)
	end

	timingScale.Scale = 1
	hintLabel.Visible = true

	contextActionService:BindActionAtPriority(PRESS_ACTION, onPressAction, false, Enum.ContextActionPriority.High.Value, table.unpack(PRESS_KEYS))
	renderConnection = runService.RenderStepped:Connect(updateTiming)
end

-- Stops the mini-game (sheep finished or player left) but leaves the camera/station alone.
endMinigame = function()
	if not shearing then
		return
	end
	shearing = false
	currentSheep = nil
	attempt = nil

	contextActionService:UnbindAction(PRESS_ACTION)

	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	timingBar.Visible = false
	timingBar.Position = TIMING_HOME
	sheepHud.Visible = false
	setMainHudVisible(true)

	if shearTool then
		humanoid:UnequipTools()
		shearTool = nil
	end
end

-- Releases the camera and movement (the server moves the character out of the pen).
exitStation = function()
	if not inStation then
		return
	end
	inStation = false
	stationToken += 1
	exitButton.Visible = false

	-- Leave the GUI up just long enough for the "+N Wool" popup to finish.
	task.delay(1.3, function()
		if not inStation then
			shearingGui.Enabled = false
		end
	end)

	humanoid.WalkSpeed = savedWalkSpeed
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = savedFieldOfView

		-- Safety net: in testing the camera was twice seen still Scriptable after leaving, so re-check shortly after.
		task.delay(0.3, function()
			if not inStation and camera.CameraType == Enum.CameraType.Scriptable then
				camera.CameraType = Enum.CameraType.Custom
			end
		end)
	end
end

exitButton.Activated:Connect(function()
	if inStation then
		network.fireServer(network.RemoteEvents.StopShearing)
	end
end)

--[[
	This script isn't loaded through ModuleLoader's Setup/Start lifecycle
	(it lives under StarterPlayerScripts, not ReplicatedStorage.Source), so
	there's no guarantee ClientStart has already called
	network.startClientAsync() by the time this line runs. Wait for it
	explicitly rather than racing it.
]]--
network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ActivateShearing, function(sheepId: number, sheepPosition: Vector3?, playerPosition: Vector3?)
	if shearing then
		return
	end

	local token = stationToken
	local sheepModel = findSheepById(sheepId)
	if token ~= stationToken then
		return -- the station ended while we were waiting for the sheep
	end
	if not sheepModel then
		warn(`No active sheep found for id: {sheepId}`)
		network.fireServer(network.RemoteEvents.StopShearing)
		return
	end

	enterStation(sheepModel, sheepPosition, playerPosition)
	startMinigame(sheepModel)
end)

network.connectEvent(network.RemoteEvents.DeactivateShearing, function(completed: boolean?, woolAmount: number?)
	-- The sheep is already gone by now, so the wool leaves from where it was last seen.
	local sheepRoot = getSheepRoot()
	local origin = if sheepRoot then sheepRoot.Position else lastSheepPosition
	endMinigame()

	if completed and woolAmount and origin then
		woolCollected:Fire(origin, woolAmount)
	end

	exitStation()
end)

-- The server's verdict on each press: the damage that really came off the sheep.
network.connectEvent(network.RemoteEvents.ShearDamage, function(tier: string, damage: number)
	if shearing then
		showDamage(tier, damage)
	end
end)

network.connectEvent(network.RemoteEvents.ShearAttempt, onAttempt)
