--[[
	Client side of hitbox shearing: draws the shear's range as a flat ring under the character while it is held,
	outlines the sheep a swing would reach, swings on click / tap, and flashes, throws wool off and pops the damage over
	each sheep hit. ShearHandler decides the hits.
	The wool chunks and flash highlights are pooled locally in ReplicatedStorage.ShearEffectPool.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer

--// Animations
local shearToolAnim = replicatedStorage.Assets.Animations.ShearTool
local shearRigAnim = replicatedStorage.Assets.Animations.ShearRig

--// Sound Effects
local uiSounds = soundService:WaitForChild("UISounds")
local shearSound = uiSounds:WaitForChild("Shear", 10) :: Sound?
local shearCompleteSound = soundService:WaitForChild("SoundGroup"):WaitForChild("ShearComplete", 10) :: Sound?

--// VFX
local poofTemplate = replicatedStorage.Assets.VFX.PoofAttachment :: Attachment

--// Configs
local RANGE_ATTRIBUTE = "ShearRange" -- set on every shear Tool by ShearShopHandler
local COOLDOWN_ATTRIBUTE = "ShearCooldown"
local DEFAULT_COOLDOWN = 0.35
local RING_THICKNESS = 0.15
local RING_COLOR = Color3.fromRGB(120, 200, 255)
local RING_TRANSPARENCY = 0.75
local RING_FLASH_TRANSPARENCY = 0.35 -- the ring brightens for a moment on every swing
local RING_FLASH_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GROUND_RAY_LENGTH = 50
local GROUND_RAY_PASSES = 5 -- sheep / players / walls the ground ray may pass through before giving up
local MIN_FLOOR_NORMAL_Y = 0.6 -- steeper surfaces are walls, not floor
local FEET_TOLERANCE = 0.5 -- studs the ring may sit above the character's feet (steps, uneven floor)
local DAMAGE_COLOR = Color3.fromRGB(255, 150, 150)
local DAMAGE_RISE = 2.5 -- studs the number floats up
local DAMAGE_SECONDS = 0.7
local DAMAGE_HEIGHT = 3 -- studs above the sheep's root the number starts
local ELECTRIC_BURST_COUNT = 18
local POOF_DEFAULT_EMIT_COUNT = 20 -- used when an emitter in the poof has no "EmitCount" attribute

--// Torso flash
local WOOL_PART_NAME = "Torso" -- the sheep's wool mesh
local FLASH_COLOR = Color3.new(1, 1, 1)
local FLASH_START_TRANSPARENCY = 0.35
local FLASH_OUTLINE_START_TRANSPARENCY = 0.3
local FLASH_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// Wool chunks: few and big, so they read clearly without spawning many parts
local WOOL_CHUNKS_PER_HIT = 3
local WOOL_CHUNKS_FINISH = 6 -- the blow that shears the sheep bare
local WOOL_CHUNK_MIN_SIZE = 1.2
local WOOL_CHUNK_MAX_SIZE = 1.8
local WOOL_CHUNK_LIFETIME = 1.2
local WOOL_CHUNK_SHRINK_SECONDS = 0.3
local WOOL_CHUNK_POOL_LIMIT = 36 -- chunks never exceed this; a burst past it is skipped
local WOOL_CHUNK_PREWARM = 12

--// Pool
local POOL_FOLDER_NAME = "ShearEffectPool"

--// In-range highlight: the player's sheep inside the ring get an outline so they know a swing will reach them
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local MAX_HEIGHT_DIFFERENCE = 6 -- matches ShearData.MaxHeightDifference on the server
local RANGE_CHECK_SECONDS = 0.1
local RANGE_HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local RANGE_FILL_TRANSPARENCY = 0.85
local MAX_RANGE_HIGHLIGHTS = 20 -- Roblox only draws ~31 highlights at once; the rest are left for hit flashes

--// State
local heldTool: Tool? = nil
local toolConnections: { RBXScriptConnection } = {}
local renderConnection: RBXScriptConnection? = nil
local nextSwingAt = 0
local nextRangeCheck = 0
local rangeHighlights: { [Model]: Highlight } = {}
local idleRangeHighlights: { Highlight } = {}

-- Created by this client, so it only exists locally; idle effects wait here instead of being destroyed.
local poolFolder = Instance.new("Folder")
poolFolder.Name = POOL_FOLDER_NAME
poolFolder.Parent = replicatedStorage

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- invisible trigger and zone parts are not floor

-- The hitbox ring: a flat cylinder (a cylinder's axis is its X, so it is turned to stand on end).
local ring = Instance.new("Part")
ring.Name = "ShearHitbox"
ring.Shape = Enum.PartType.Cylinder
ring.Material = Enum.Material.Neon
ring.Color = RING_COLOR
ring.Transparency = RING_TRANSPARENCY
ring.Anchored = true
ring.CanCollide = false
ring.CanQuery = false
ring.CanTouch = false
ring.CastShadow = false

-- A light tap felt on phones (and gamepads) when a sheep is sheared bare; nil where HapticEffect isn't supported.
local shearCompleteHaptic: HapticEffect? = nil
pcall(function()
	local haptic = Instance.new("HapticEffect")
	haptic.Type = Enum.HapticEffectType.UIClick
	haptic.Parent = script
	shearCompleteHaptic = haptic
end)

--// Animation ---------------------------------------------------------------------

--[[
	Each animator gets its track loaded ONCE and every swing replays it; loading per swing hits the 64 track limit.
	Plain (strong) tables on purpose: Roblox may drop an Instance key from a weak table while the Instance still
	exists, which silently emptied the old cache and reloaded a track on every swing.
]]--
local toolTracks: { [Tool]: AnimationTrack } = {} -- cleared when the tool is destroyed (shear swapped)
local rigTrack: AnimationTrack? = nil
local rigAnimator: Animator? = nil -- the animator rigTrack belongs to; a respawn brings a new one

local function loadTrack(animator: Animator, animation: Animation): AnimationTrack
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	return track
end

local function getRigTrack(): AnimationTrack?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	if animator ~= rigAnimator or not rigTrack then
		rigAnimator = animator
		rigTrack = loadTrack(animator, shearRigAnim)
	end
	return rigTrack
end

local function getToolTrack(tool: Tool): AnimationTrack?
	local track = toolTracks[tool]
	if track then
		return track
	end

	local controller = tool:FindFirstChild("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local newTrack = loadTrack(animator, shearToolAnim)
	toolTracks[tool] = newTrack
	tool.Destroying:Once(function()
		toolTracks[tool] = nil
	end)
	return newTrack
end

local function playSwingAnimation(tool: Tool)
	local characterTrack = getRigTrack()
	if characterTrack then
		characterTrack:Play()
	end

	local toolTrack = getToolTrack(tool)
	if toolTrack then
		toolTrack:Play()
	end
end

--// Hitbox ring -------------------------------------------------------------------

local function updateRingSize()
	local range = heldTool and heldTool:GetAttribute(RANGE_ATTRIBUTE)
	if type(range) == "number" then
		ring.Size = Vector3.new(RING_THICKNESS, range * 2, range * 2)
	end
end

local function hideRangeHighlight(sheep: Model)
	local highlight = rangeHighlights[sheep]
	if not highlight then
		return
	end

	rangeHighlights[sheep] = nil
	highlight.Adornee = nil
	highlight.Parent = poolFolder
	table.insert(idleRangeHighlights, highlight)
end

local function showRangeHighlight(sheep: Model)
	if rangeHighlights[sheep] then
		return
	end

	local highlight = table.remove(idleRangeHighlights)
	if not highlight then
		local newHighlight = Instance.new("Highlight")
		newHighlight.Name = "ShearRangeHighlight"
		newHighlight.FillColor = RANGE_HIGHLIGHT_COLOR
		newHighlight.OutlineColor = RANGE_HIGHLIGHT_COLOR
		newHighlight.FillTransparency = RANGE_FILL_TRANSPARENCY
		newHighlight.OutlineTransparency = 0
		newHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight = newHighlight
	end

	local active = highlight :: Highlight
	active.Adornee = sheep
	active.Parent = workspace
	rangeHighlights[sheep] = active
end

local function clearRangeHighlights()
	for sheep in rangeHighlights do
		hideRangeHighlight(sheep)
	end
end

-- Outlines the player's own sheep inside the hitbox, using the same flat-distance test as the server.
local function updateRangeHighlights(center: Vector3)
	local range = heldTool and heldTool:GetAttribute(RANGE_ATTRIBUTE)
	if type(range) ~= "number" then
		clearRangeHighlights()
		return
	end

	local inRange: { [Model]: boolean } = {}
	local count = 0
	for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
		if count >= MAX_RANGE_HIGHLIGHTS then
			break
		end
		if not sheep:IsA("Model") or sheep:GetAttribute(OWNER_ATTRIBUTE) ~= player.UserId or not sheep:IsDescendantOf(workspace) then
			continue
		end

		local root = sheep:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local offset = root.Position - center
		if math.abs(offset.Y) <= MAX_HEIGHT_DIFFERENCE and Vector3.new(offset.X, 0, offset.Z).Magnitude <= range then
			inRange[sheep] = true
			count += 1
			showRangeHighlight(sheep)
		end
	end

	for sheep in rangeHighlights do
		if not inRange[sheep] then
			hideRangeHighlight(sheep)
		end
	end
end

-- The sheep or character model this part belongs to, if any; standing next to one must not lift the ring onto it.
local function getMobModel(part: Instance): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") or collectionService:HasTag(model, SHEEP_TAG) then
			return model
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

-- Y of the floor under the character, never above its feet. Sheep, players and walls are skipped.
local function getGroundY(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	-- R6 reports a HipHeight of 0; its legs are always 2 studs.
	local hipHeight = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight else 2
	local feetY = root.Position.Y - root.Size.Y / 2 - hipHeight

	rayParams.FilterDescendantsInstances = { character, ring, poolFolder }
	local direction = Vector3.new(0, -GROUND_RAY_LENGTH, 0)
	for _ = 1, GROUND_RAY_PASSES do
		local result = workspace:Raycast(root.Position, direction, rayParams)
		if not result then
			break
		end

		local mob = getMobModel(result.Instance)
		if not mob and result.Normal.Y >= MIN_FLOOR_NORMAL_Y then
			return math.min(result.Position.Y, feetY + FEET_TOLERANCE)
		end
		rayParams:AddToFilter(mob or result.Instance)
	end
	return feetY
end

-- Keeps the ring flat on the ground under the character and the in-range outlines current.
local function updateRing()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		ring.Parent = nil
		clearRangeHighlights()
		return
	end

	local groundY = getGroundY(character, root)

	ring.CFrame = CFrame.new(root.Position.X, groundY + RING_THICKNESS / 2, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace

	local now = os.clock()
	if now >= nextRangeCheck then
		nextRangeCheck = now + RANGE_CHECK_SECONDS
		updateRangeHighlights(root.Position)
	end
end

local function flashRing()
	ring.Transparency = RING_FLASH_TRANSPARENCY
	tweenService:Create(ring, RING_FLASH_TWEEN, { Transparency = RING_TRANSPARENCY }):Play()
end

--// Swinging -----------------------------------------------------------------------

local function swing()
	local tool = heldTool
	local now = os.clock()
	if not tool or now < nextSwingAt then
		return
	end

	local cooldown = tool:GetAttribute(COOLDOWN_ATTRIBUTE)
	nextSwingAt = now + (if type(cooldown) == "number" then cooldown else DEFAULT_COOLDOWN)

	playSwingAnimation(tool)
	flashRing()
	network.fireServer(network.RemoteEvents.ShearSwing)
end

local function unequip()
	heldTool = nil
	for _, connection in toolConnections do
		connection:Disconnect()
	end
	table.clear(toolConnections)

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	ring.Parent = nil
	clearRangeHighlights()
end

local function equip(tool: Tool)
	unequip()
	heldTool = tool

	updateRingSize()
	table.insert(toolConnections, tool:GetAttributeChangedSignal(RANGE_ATTRIBUTE):Connect(updateRingSize))
	-- Activated covers mouse clicks, screen taps and the gamepad's tool button.
	table.insert(toolConnections, tool.Activated:Connect(swing))

	updateRing()
	renderConnection = runService.RenderStepped:Connect(updateRing)
end

local function isShear(instance: Instance): boolean
	return instance:IsA("Tool") and instance:GetAttribute(RANGE_ATTRIBUTE) ~= nil
end

local function onCharacterAdded(character: Model)
	unequip()

	character.ChildAdded:Connect(function(child: Instance)
		if isShear(child) then
			equip(child :: Tool)
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child == heldTool then
			unequip()
		end
	end)

	for _, child in character:GetChildren() do
		if isShear(child) then
			equip(child :: Tool)
		end
	end
end

--// Effect pool ----------------------------------------------------------------------

local idleChunks: { Part } = {}
local idleFlashes: { Highlight } = {}
local chunkCount = 0 -- chunks created so far, idle or flying

local function createChunk(): Part
	chunkCount += 1
	local chunk = Instance.new("Part")
	chunk.Name = "WoolChunk"
	chunk.Shape = Enum.PartType.Ball
	chunk.Material = Enum.Material.SmoothPlastic
	chunk.Anchored = true
	chunk.CanCollide = false
	chunk.CanTouch = false
	chunk.CanQuery = false
	chunk.CastShadow = false
	chunk.Parent = poolFolder
	return chunk
end

-- A free chunk, or nil once WOOL_CHUNK_POOL_LIMIT are all flying.
local function acquireChunk(): Part?
	local chunk = table.remove(idleChunks)
	if chunk then
		return chunk
	end
	return if chunkCount < WOOL_CHUNK_POOL_LIMIT then createChunk() else nil
end

local function releaseChunk(chunk: Part)
	chunk.Anchored = true
	chunk.AssemblyLinearVelocity = Vector3.zero
	chunk.Parent = poolFolder
	table.insert(idleChunks, chunk)
end

local function acquireFlash(): Highlight
	local flash = table.remove(idleFlashes)
	if flash then
		return flash
	end

	local newFlash = Instance.new("Highlight")
	newFlash.Name = "ShearFlash"
	newFlash.FillColor = FLASH_COLOR
	newFlash.OutlineColor = FLASH_COLOR
	newFlash.DepthMode = Enum.HighlightDepthMode.Occluded
	return newFlash
end

local function releaseFlash(flash: Highlight)
	flash.Adornee = nil
	flash.Parent = poolFolder
	table.insert(idleFlashes, flash)
end

for _ = 1, WOOL_CHUNK_PREWARM do
	table.insert(idleChunks, createChunk())
end

--// Hit feedback -------------------------------------------------------------------

-- The sheep's wool flashes white for a moment.
local function flashTorso(sheep: Model)
	local torso = sheep:FindFirstChild(WOOL_PART_NAME)
	if not torso or not torso:IsA("BasePart") then
		return
	end

	local flash = acquireFlash()
	flash.Adornee = torso
	flash.FillTransparency = FLASH_START_TRANSPARENCY
	flash.OutlineTransparency = FLASH_OUTLINE_START_TRANSPARENCY
	flash.Parent = workspace

	local tween = tweenService:Create(flash, FLASH_TWEEN, { FillTransparency = 1, OutlineTransparency = 1 })
	tween.Completed:Once(function()
		releaseFlash(flash)
	end)
	tween:Play()
end

-- Big wool chunks in the sheep's wool colour burst off it towards the camera, then shrink away.
local function throwWool(position: Vector3, color: Color3, count: number)
	local camera = workspace.CurrentCamera
	local toCamera = if camera then camera.CFrame.Position - position else Vector3.zero
	toCamera = Vector3.new(toCamera.X, 0, toCamera.Z)
	local outward = if toCamera.Magnitude > 0.05 then toCamera.Unit else Vector3.xAxis

	for _ = 1, count do
		local chunk = acquireChunk()
		if not chunk then
			return
		end

		local scatter = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5) * 1.6
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.5, math.random() - 0.5)
		local size = WOOL_CHUNK_MIN_SIZE + math.random() * (WOOL_CHUNK_MAX_SIZE - WOOL_CHUNK_MIN_SIZE)

		chunk.Size = Vector3.one * size
		chunk.Color = color
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 0.8, 0) + scatter)
		chunk.Anchored = false
		chunk.Parent = workspace
		chunk.AssemblyLinearVelocity = (outward + spread * 0.8).Unit * (10 + math.random() * 6) + Vector3.new(0, 8 + math.random() * 4, 0)

		task.delay(WOOL_CHUNK_LIFETIME - WOOL_CHUNK_SHRINK_SECONDS, function()
			local shrink = tweenService:Create(chunk, TweenInfo.new(WOOL_CHUNK_SHRINK_SECONDS), { Size = Vector3.one * 0.05 })
			shrink.Completed:Once(function()
				releaseChunk(chunk)
			end)
			shrink:Play()
		end)
	end
end

-- A damage number that floats up from over the sheep and fades out.
local function showDamage(position: Vector3, damage: number)
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position + Vector3.new(0, DAMAGE_HEIGHT, 0)
	anchor.Parent = workspace.Terrain

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(3, 1.4)
	billboard.LightInfluence = 0
	billboard.AlwaysOnTop = true
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = DAMAGE_COLOR
	label.Text = `-{damage}`
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label

	local tweenInfo = TweenInfo.new(DAMAGE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenService:Create(billboard, tweenInfo, { StudsOffsetWorldSpace = Vector3.new(0, DAMAGE_RISE, 0) }):Play()
	tweenService:Create(label, tweenInfo, { TextTransparency = 1 }):Play()
	tweenService:Create(stroke, tweenInfo, { Transparency = 1 }):Play()
	debris:AddItem(anchor, DAMAGE_SECONDS + 0.1)
end

-- Bursts a copy of the poof attachment's emitters where a sheep was sheared bare.
local function playPoof(position: Vector3)
	local poof = poofTemplate:Clone()
	poof.Parent = workspace.Terrain
	poof.WorldPosition = position

	local lifetime = 0
	for _, descendant in poof:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount")
			descendant:Emit(if type(emitCount) == "number" then emitCount else POOF_DEFAULT_EMIT_COUNT)
			lifetime = math.max(lifetime, descendant.Lifetime.Max)
		end
	end
	debris:AddItem(poof, lifetime + 0.5)
end

local function onShearHit(hits: { { sheep: Model?, position: Vector3, damage: number, color: Color3 } })
	local finishedAny = false
	for _, hit in hits do
		showDamage(hit.position, hit.damage)

		-- No sheep means this blow sheared it bare (it is already gone), so it gets the bigger burst and the poof.
		local sheep = hit.sheep
		if sheep and sheep:IsDescendantOf(workspace) then
			flashTorso(sheep)
			throwWool(hit.position, hit.color, WOOL_CHUNKS_PER_HIT)
		else
			throwWool(hit.position, hit.color, WOOL_CHUNKS_FINISH)
			playPoof(hit.position)
			finishedAny = true
		end
	end

	if shearSound then
		shearSound:Play()
	end
	if finishedAny and shearCompleteSound then
		shearCompleteSound:Play()
	end
	if finishedAny and shearCompleteHaptic then
		shearCompleteHaptic:Play()
	end

	-- Electric shears crackle on every hit (other players see it through the tool's "Snips" attribute).
	if heldTool then
		for _, descendant in heldTool:GetDescendants() do
			if descendant:IsA("ParticleEmitter") and descendant.Name == "ElectricBurst" then
				descendant:Emit(ELECTRIC_BURST_COUNT)
			end
		end
	end
end

--// Setup ---------------------------------------------------------------------------

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShearHit, onShearHit)
