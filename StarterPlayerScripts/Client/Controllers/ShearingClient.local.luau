--[[
	Client side of the shearing mini-game.

	Handles the main shearing effects on the client, the circles that popup, the
	animations and states of the 
	shearing process.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearingClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Animations
local shearToolAnim = replicatedStorage.Assets.Animations.ShearTool
local shearRigAnim = replicatedStorage.Assets.Animations.ShearRig

--// Camera tuning (studs / degrees). Tweak these to reframe the shot.
local CAMERA_DISTANCE = 6.5 -- how far behind the sheep the camera sits
local CAMERA_HEIGHT = 3.2 -- how far above the sheep's centre (also keeps it above the pen fence)
local CAMERA_LOOK_AHEAD = 2.2 -- aim this far from the sheep towards the player, so both are in frame
local CAMERA_LOOK_HEIGHT = 0.6
local CAMERA_FOV = 60
local CAMERA_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

--// Circle tuning
local BASE_CIRCLE_SIZE = 84 -- pixels at 720p, scaled by rarity and screen size
local RING_EXTRA = 1.4 -- the approach ring starts this much bigger than the circle
local WOOL_BURST_COUNT = 18

--// Wool chunk tuning (little spheres that fly off the sheep when a circle is popped)
local WOOL_CHUNKS_PER_POP = 2
local WOOL_CHUNKS_PER_CRIT = 8
local WOOL_CHUNK_LIFETIME = 1.4

--// Layout
local HEALTH_HUD_BOTTOM_OFFSET = -110 -- pixels up from the bottom edge, clear of the default hotbar

--// Style
local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local LOW_HEALTH_COLOR = Color3.fromRGB(230, 70, 70)
local FULL_HEALTH_COLOR = Color3.fromRGB(90, 210, 100)
local TIER_LOW = Color3.fromRGB(80, 170, 255)
local TIER_MID = Color3.fromRGB(255, 170, 40)
local TIER_HIGH = Color3.fromRGB(255, 70, 90)

--// Character
local character: Model
local humanoid: Humanoid
local humanoidRootPart: BasePart

--// State
local inStation = false -- camera locked at the pen (from the first START SHEARING until Leave)
local shearing = false -- a sheep is currently being sheared (circles active)
local stationToken = 0 -- bumps every time the station ends, so a late "start" can tell it's stale
local currentSheep: Model? = nil
local previousHealth = 0
local shearTool: Tool? = nil
local healthConnection: RBXScriptConnection? = nil
local renderConnection: RBXScriptConnection? = nil
local savedWalkSpeed = 16
local savedFieldOfView = 70

type Circle = {
	waveId: number,
	pointId: string,
	offset: Vector3,
	damage: number,
	born: number,
	lifetime: number,
	size: number,
	color: Color3,
	frame: Frame,
	ring: Frame,
	button: TextButton,
	screenPosition: Vector2,
	popped: boolean,
	expired: boolean,
	removed: boolean,
}

local circles: { Circle } = {}

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

--// GUI ------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShearingGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 8
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local circleLayer = Instance.new("Frame")
circleLayer.Name = "CircleLayer"
circleLayer.BackgroundTransparency = 1
circleLayer.Size = UDim2.fromScale(1, 1)
circleLayer.ZIndex = 2
circleLayer.Parent = screenGui

local popupLayer = Instance.new("Frame")
popupLayer.Name = "PopupLayer"
popupLayer.BackgroundTransparency = 1
popupLayer.Size = UDim2.fromScale(1, 1)
popupLayer.ZIndex = 4
popupLayer.Parent = screenGui

local function addStroke(instance: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or BLACK
	stroke.Thickness = thickness
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	stroke.Parent = instance
	return stroke
end

-- Sheep name + health bar, bottom centre (raised so it clears the default inventory hotbar).
local hud = Instance.new("Frame")
hud.Name = "Hud"
hud.AnchorPoint = Vector2.new(0.5, 1)
hud.Position = UDim2.new(0.5, 0, 1, HEALTH_HUD_BOTTOM_OFFSET)
hud.Size = UDim2.fromOffset(360, 64)
hud.BackgroundTransparency = 1
hud.Visible = false
hud.ZIndex = 3
hud.Parent = screenGui

local sheepNameLabel = Instance.new("TextLabel")
sheepNameLabel.Name = "SheepName"
sheepNameLabel.BackgroundTransparency = 1
sheepNameLabel.Size = UDim2.new(1, 0, 0, 28)
sheepNameLabel.Font = FONT
sheepNameLabel.TextSize = 24
sheepNameLabel.TextColor3 = WHITE
sheepNameLabel.Text = ""
sheepNameLabel.ZIndex = 3
sheepNameLabel.Parent = hud
addStroke(sheepNameLabel, 3)

local healthTrack = Instance.new("Frame")
healthTrack.Name = "HealthTrack"
healthTrack.AnchorPoint = Vector2.new(0.5, 1)
healthTrack.Position = UDim2.fromScale(0.5, 1)
healthTrack.Size = UDim2.new(1, 0, 0, 28)
healthTrack.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
healthTrack.BorderSizePixel = 0
healthTrack.ZIndex = 3
healthTrack.Parent = hud

local healthTrackCorner = Instance.new("UICorner")
healthTrackCorner.CornerRadius = UDim.new(1, 0)
healthTrackCorner.Parent = healthTrack
addStroke(healthTrack, 3, BLACK)

local healthScale = Instance.new("UIScale")
healthScale.Parent = healthTrack

local healthFill = Instance.new("Frame")
healthFill.Name = "Fill"
healthFill.Size = UDim2.fromScale(1, 1)
healthFill.BackgroundColor3 = FULL_HEALTH_COLOR
healthFill.BorderSizePixel = 0
healthFill.ZIndex = 3
healthFill.Parent = healthTrack

local healthFillCorner = Instance.new("UICorner")
healthFillCorner.CornerRadius = UDim.new(1, 0)
healthFillCorner.Parent = healthFill

local healthText = Instance.new("TextLabel")
healthText.Name = "HealthText"
healthText.BackgroundTransparency = 1
healthText.Size = UDim2.fromScale(1, 1)
healthText.Font = FONT
healthText.TextSize = 16
healthText.TextColor3 = WHITE
healthText.Text = ""
healthText.ZIndex = 4
healthText.Parent = healthTrack
addStroke(healthText, 2)

-- Leave button, top right: ends the mini-game (the sheep keeps its health) and leaves the pen station.
local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveButton"
leaveButton.AnchorPoint = Vector2.new(1, 0)
leaveButton.Position = UDim2.new(1, -20, 0, 20)
leaveButton.Size = UDim2.fromOffset(112, 44)
leaveButton.AutoButtonColor = false
leaveButton.BackgroundColor3 = Color3.fromRGB(232, 78, 88)
leaveButton.Font = FONT
leaveButton.TextSize = 22
leaveButton.TextColor3 = WHITE
leaveButton.Text = "Leave"
leaveButton.Visible = false
leaveButton.ZIndex = 5
leaveButton.Parent = screenGui

local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = UDim.new(0, 10)
leaveCorner.Parent = leaveButton
addStroke(leaveButton, 2.5)

local leaveEdge = Instance.new("UIStroke")
leaveEdge.Color = Color3.fromRGB(150, 34, 48)
leaveEdge.Thickness = 3
leaveEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
leaveEdge.Parent = leaveButton

screenGui.Parent = playerGui

--// Small helpers -----------------------------------------------------------------

local function getUiScale(): number
	local camera = workspace.CurrentCamera
	return if camera then math.clamp(camera.ViewportSize.Y / 720, 0.75, 1.4) else 1
end

-- The game's own HUD (wool / money labels) is hidden while a sheep is being sheared.
local function setMainHudVisible(visible: boolean)
	local main = playerGui:FindFirstChild("Main")
	if main and main:IsA("ScreenGui") then
		main.Enabled = visible
	end
end

-- Floating text at a screen position that drifts upward and fades out.
local function spawnPopup(text: string, position: Vector2, color: Color3, textSize: number, rise: number, duration: number)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(position.X, position.Y)
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = FONT
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
end

local function updateHealthBar(current: number, maximum: number)
	local ratio = if maximum > 0 then math.clamp(current / maximum, 0, 1) else 0

	tweenService:Create(healthFill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
		BackgroundColor3 = LOW_HEALTH_COLOR:Lerp(FULL_HEALTH_COLOR, ratio),
	}):Play()

	healthText.Text = `{math.ceil(math.max(current, 0))} / {maximum}`

	healthScale.Scale = 1.1
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

-- Little wool spheres (the sheep torso's colour) that fly out from `origin` in the `outward` direction.
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

local function playShearAnimation()
	local tool = shearTool
	if not tool or tool.Parent ~= character then
		return
	end
	local toolAnimationController = tool:FindFirstChild("AnimationController") 
	local toolAnimator = toolAnimationController:FindFirstChild("Animator")
	local shearToolTrack = toolAnimator:LoadAnimation(shearToolAnim) :: AnimationTrack
	shearToolTrack.Priority = Enum.AnimationPriority.Action

	local characterAnimator = humanoid:FindFirstChild("Animator") 
	local shearRigTrack = characterAnimator:LoadAnimation(shearRigAnim) :: AnimationTrack
	shearRigTrack.Priority = Enum.AnimationPriority.Action

	-- Better shears snip faster (the server sets ShearSpeed from the shear's data).
	local speed = (player:GetAttribute("ShearSpeed") :: number?) or 1

	-- Electric shears crackle on every snip (other players see it via the tool's "Snips" attribute).
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "ElectricBurst" then
			descendant:Emit(18)
		end
	end

	if shearToolTrack and not shearToolTrack.IsPlaying then
		shearToolTrack:Play()
		shearToolTrack:AdjustSpeed(speed)
		shearToolTrack.Looped = false
		task.delay(shearToolTrack.Length, function()
			shearToolTrack:Stop()
		end)
		print(`Playing animation`)
	end
	if shearRigTrack and not shearRigTrack.IsPlaying then
		shearRigTrack:Play()
		shearRigTrack:AdjustSpeed(speed)
		shearRigTrack.Looped = false
		task.delay(shearRigTrack.Length, function()
			shearRigTrack:Stop()
		end)
		print(`playing animation`)
	end
end

--// Circles ------------------------------------------------------------------------
local function getTierColor(multiplier: number): Color3
	if multiplier >= 2 then
		return TIER_HIGH
	elseif multiplier > 1 then
		return TIER_MID
	end
	return TIER_LOW
end

local function fadeStrokes(instance: Instance, duration: number)
	for _, child in instance:GetChildren() do
		if child:IsA("UIStroke") then
			tweenService:Create(child, TweenInfo.new(duration), { Transparency = 1 }):Play()
		end
	end
end

local function removeCircle(circle: Circle, delay: number)
	circle.removed = true
	task.delay(delay, function()
		circle.frame:Destroy()
	end)
end

-- Pop: reports the hit to the server, flings wool off that spot and plays the burst effect.
local function popCircle(circle: Circle)
	if circle.popped or circle.expired or not shearing then
		return
	end
	circle.popped = true

	network.fireServer(network.RemoteEvents.ShearHit, circle.waveId, circle.pointId)
	playShearAnimation()
	spawnPopup(`+{circle.damage}`, circle.screenPosition + Vector2.new(0, -circle.size * 0.4), WHITE, 26, 60, 0.7)

	-- Wool flies out of the spot that was hit, away from the sheep's body.
	local sheepRoot = getSheepRoot()
	if sheepRoot then
		local worldPosition = sheepRoot.CFrame:PointToWorldSpace(circle.offset)
		local outward = worldPosition - sheepRoot.Position
		outward = if outward.Magnitude > 0.05 then outward.Unit else sheepRoot.CFrame.RightVector
		spawnWoolChunks(worldPosition, outward, WOOL_CHUNKS_PER_POP, 1)
	end

	circle.ring.Visible = false
	local scale = circle.frame:FindFirstChildOfClass("UIScale")
	if scale then
		tweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.7 }):Play()
	end
	tweenService:Create(circle.button, TweenInfo.new(0.18), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	fadeStrokes(circle.button, 0.18)

	removeCircle(circle, 0.25)
end

-- Ran out of time: the circle greys out and a "Miss" floats up.
local function expireCircle(circle: Circle)
	circle.expired = true
	circle.ring.Visible = false

	circle.button.BackgroundColor3 = Color3.fromRGB(110, 112, 122)
	tweenService:Create(circle.button, TweenInfo.new(0.25), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	fadeStrokes(circle.button, 0.25)

	spawnPopup("Miss", circle.screenPosition, Color3.fromRGB(200, 202, 212), 20, 30, 0.5)
	removeCircle(circle, 0.3)
end

local function createCircle(waveId: number, point: any, lifetime: number, sizeScale: number)
	local size = math.floor(BASE_CIRCLE_SIZE * sizeScale * getUiScale())
	local color = getTierColor(point.multiplier)

	local frame = Instance.new("Frame")
	frame.Name = `Circle_{point.id}`
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = circleLayer

	local frameScale = Instance.new("UIScale")
	frameScale.Scale = 0.2
	frameScale.Parent = frame

	-- Approach ring: starts big and shrinks onto the circle as its time runs out.
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(size * (1 + RING_EXTRA), size * (1 + RING_EXTRA))
	ring.BackgroundTransparency = 1
	ring.Parent = frame

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = color
	ringStroke.Thickness = 4
	ringStroke.Transparency = 0.1
	ringStroke.Parent = ring

	local button = Instance.new("TextButton")
	button.Name = "Hit"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	button.Font = FONT
	button.TextSize = math.floor(size * 0.4)
	button.TextColor3 = WHITE
	button.Text = tostring(point.damage)
	button.Parent = frame

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(1, 0)
	buttonCorner.Parent = button

	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.Color = WHITE
	outline.Thickness = 3
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Parent = button

	local textStroke = Instance.new("UIStroke")
	textStroke.Name = "TextStroke"
	textStroke.Color = BLACK
	textStroke.Thickness = 2
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Parent = button

	tweenService:Create(frameScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local circle: Circle = {
		waveId = waveId,
		pointId = point.id,
		offset = point.offset,
		damage = point.damage,
		born = os.clock(),
		lifetime = lifetime,
		size = size,
		color = color,
		frame = frame,
		ring = ring,
		button = button,
		screenPosition = Vector2.zero,
		popped = false,
		expired = false,
		removed = false,
	}
	table.insert(circles, circle)

	-- InputBegan (not Activated) so the pop lands the instant the mouse/finger goes down.
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			popCircle(circle)
		end
	end)
end

-- Every frame: keep each circle glued to its spot on the sheep, shrink its ring and time it out.
local function updateCircles()
	local sheepRoot = getSheepRoot()
	local camera = workspace.CurrentCamera
	if not sheepRoot or not camera then
		return
	end

	local now = os.clock()
	for index = #circles, 1, -1 do
		local circle = circles[index]
		if circle.removed and not circle.frame.Parent then
			table.remove(circles, index)
			continue
		end

		local worldPosition = sheepRoot.CFrame:PointToWorldSpace(circle.offset)
		local viewportPoint, onScreen = camera:WorldToViewportPoint(worldPosition)
		circle.screenPosition = Vector2.new(viewportPoint.X, viewportPoint.Y)
		circle.frame.Position = UDim2.fromOffset(viewportPoint.X, viewportPoint.Y)
		circle.frame.Visible = onScreen and viewportPoint.Z > 0

		if not circle.popped and not circle.expired then
			local progress = math.clamp((now - circle.born) / circle.lifetime, 0, 1)
			local ringSize = circle.size * (1 + RING_EXTRA * (1 - progress))
			circle.ring.Size = UDim2.fromOffset(ringSize, ringSize)

			if progress >= 1 then
				expireCircle(circle)
			end
		end
	end
end

local function clearCircles()
	for _, circle in circles do
		circle.frame:Destroy()
	end
	table.clear(circles)
end

--// Critical hit banner ---------------------------------------------------------------

local function showCritical(bonusDamage: number)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(viewport.X / 2, viewport.Y * 0.3)
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextSize = 54
	label.TextColor3 = Color3.fromRGB(255, 226, 70)
	label.Text = `CRITICAL!  +{bonusDamage}`
	label.ZIndex = 5
	label.Parent = popupLayer
	local stroke = addStroke(label, 4)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	tweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	-- A big shower of wool from the whole body.
	local sheepRoot = getSheepRoot()
	if sheepRoot then
		for _ = 1, WOOL_CHUNKS_PER_CRIT do
			local direction = Vector3.new(math.random() - 0.5, math.random() * 0.4, math.random() - 0.5)
			direction = if direction.Magnitude > 0.05 then direction.Unit else sheepRoot.CFrame.RightVector
			spawnWoolChunks(sheepRoot.Position + Vector3.new(0, 0.8, 0), direction, 1, 1.5)
		end
	end

	task.delay(0.7, function()
		local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenService:Create(label, fade, {
			Position = UDim2.fromOffset(viewport.X / 2, viewport.Y * 0.3 - 40),
			TextTransparency = 1,
		}):Play()
		tweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		task.wait(0.4)
		label:Destroy()
	end)
end

--// Station / shearing ------------------------------------------------------------------

-- Finds the active sheep Model by its unique id (waits briefly in case it hasn't replicated yet).
local function findSheepById(sheepId: number): Model?
	for _ = 1, 20 do
		for _, sheepModel in collectionService:GetTagged("Sheep") do
			if sheepModel:GetAttribute("id") == sheepId then
				return sheepModel :: Model
			end
		end
		task.wait(0.1)
	end
	return nil
end

-- Fallback names for the shears tool; normally the player's "ShearId" attribute (set by the server, changed
-- when they buy a shear in the shop) names the tool to use.
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

		leaveButton.Visible = true
	end

	frameCamera(sheepModel, sheepPosition, playerPosition)
end

-- Starts the circles mini-game on a sheep.
local function startMinigame(sheepModel: Model)
	shearing = true
	currentSheep = sheepModel
	setMainHudVisible(false)

	local maxHealth = sheepModel:GetAttribute("MaxShearHealth") :: number
	previousHealth = sheepModel:GetAttribute("ShearHealth") :: number
	updateHealthBar(previousHealth, maxHealth)

	local rarityColor = sheepModel:GetAttribute("RarityColor")
	sheepNameLabel.TextColor3 = if typeof(rarityColor) == "Color3" then rarityColor:Lerp(WHITE, 0.45) else WHITE
	sheepNameLabel.Text = `{sheepModel:GetAttribute("SheepName") or sheepModel.Name}  -  {sheepModel:GetAttribute("Rarity") or ""}`
	hud.Visible = true

	healthConnection = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		local health = sheepModel:GetAttribute("ShearHealth") :: number
		updateHealthBar(health, sheepModel:GetAttribute("MaxShearHealth") :: number)
		if health < previousHealth then
			emitWoolBurst(sheepModel)
		end
		previousHealth = health
	end)

	-- Hold the shears while working.
	shearTool = findShearTool()
	if shearTool then
		humanoid:EquipTool(shearTool)
	end

	renderConnection = runService.RenderStepped:Connect(updateCircles)
end

-- Stops the circles mini-game (sheep finished or player left) but leaves the camera/station alone.
endMinigame = function()
	if not shearing then
		return
	end
	shearing = false
	currentSheep = nil

	if healthConnection then
		healthConnection:Disconnect()
		healthConnection = nil
	end
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	clearCircles()
	hud.Visible = false
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
	leaveButton.Visible = false

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

leaveButton.MouseButton1Click:Connect(function()
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

-- Shearing ended (sheep finished, player left, or aborted): release the camera and movement.
network.connectEvent(network.RemoteEvents.DeactivateShearing, function(completed: boolean?, woolAmount: number?)
	endMinigame()

	if completed and woolAmount then
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		spawnPopup(`+{woolAmount} Wool`, Vector2.new(viewport.X / 2, viewport.Y * 0.4), WHITE, 44, 70, 1.2)
	end

	exitStation()
end)

network.connectEvent(network.RemoteEvents.ShearWave, function(waveId: number, lifetime: number, sizeScale: number, _critWindow: number, points: { any })
	if not shearing then
		return
	end

	for _, point in points do
		createCircle(waveId, point, lifetime, sizeScale)
	end
end)

network.connectEvent(network.RemoteEvents.ShearFeedback, function(kind: string, value: number)
	if kind == "Crit" and shearing then
		showCritical(value)
	end
end)
