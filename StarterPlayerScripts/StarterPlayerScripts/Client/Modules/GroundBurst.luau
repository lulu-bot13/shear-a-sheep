--[[
	Makes the ground erupt at a point: rings of pooled rock chunks in the ground's own material burst up, sink back, with dust, a shockwave and camera shake.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.GroundBurst
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Configs
local SHEEP_TAG = "Sheep"
local PARK_CFRAME = CFrame.new(0, 10000, 0) -- idle parts wait out of sight here instead of being reparented
local POOL_LIMIT = 160 -- chunks + debris alive at once; a burst past this just shows fewer
local PREWARM_CHUNKS = 24
local GROUND_RAY_HEIGHT = 6 -- studs above the burst the ground is searched from
local GROUND_RAY_DEPTH = 20
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SHAKE_BIND_NAME = "GroundBurstShake"
local FALLBACK_COLOR = Color3.fromRGB(120, 105, 90)

export type Options = {
	ignore: { Instance }?, -- also skipped when finding the ground
	chunkCount: number?, -- across all rings
	rings: number?,
	innerRadius: number?, -- studs from the centre to the first ring
	radius: number?, -- studs from the centre to the last ring
	height: number?, -- studs the chunks stick out of the ground at their peak
	chunkSize: number?, -- average chunk width
	lifetime: number?, -- seconds from the hit until the last chunk is back underground
	riseSeconds: number?,
	sinkSeconds: number?,
	waveSpeed: number?, -- studs per second the eruption travels outward ring by ring
	debrisCount: number?, -- small rocks thrown into the air
	dustCount: number?, -- dust particles
	shockwaveRadius: number?, -- 0 for none
	shake: number?, -- camera shake strength in studs, 0 for none
	shakeRange: number?, -- studs from the burst the camera still shakes
	shakeSeconds: number?,
}

local DEFAULTS = {
	chunkCount = 16,
	rings = 1,
	innerRadius = 4,
	radius = 6,
	height = 3,
	chunkSize = 2.5,
	lifetime = 1.6,
	riseSeconds = 0.18,
	sinkSeconds = 0.45,
	waveSpeed = 60,
	debrisCount = 8,
	dustCount = 20,
	shockwaveRadius = 12,
	shake = 0,
	shakeRange = 60,
	shakeSeconds = 0.35,
}

--// State
local random = Random.new()
local idleParts: { Part } = {}
local partCount = 0
local shakeStrength = 0
local shakeEndsAt = 0
local shakeDuration = 1

local poolFolder = Instance.new("Folder")
poolFolder.Name = "GroundBurstPool"
poolFolder.Parent = workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

local GroundBurst = {}

--// Pool --------------------------------------------------------------------------

local function createPart(): Part
	partCount += 1
	local part = Instance.new("Part")
	part.Name = "BurstChunk"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = PARK_CFRAME
	part.Parent = poolFolder
	return part
end

local function acquirePart(): Part?
	local part = table.remove(idleParts)
	if part then
		return part
	end
	return if partCount < POOL_LIMIT then createPart() else nil
end

local function releasePart(part: Part)
	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.Transparency = 0
	part.CFrame = PARK_CFRAME
	table.insert(idleParts, part)
end

for _ = 1, PREWARM_CHUNKS do
	table.insert(idleParts, createPart())
end

--// Ground --------------------------------------------------------------------------

-- Characters and sheep stand on the ground; refreshed once per burst rather than per chunk.
local function refreshGroundFilter(extra: { Instance }?)
	local ignore: { Instance } = { poolFolder }
	for _, player in players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
		table.insert(ignore, sheep)
	end
	if extra then
		table.move(extra, 1, #extra, #ignore + 1, ignore)
	end
	groundParams.FilterDescendantsInstances = ignore
end

-- The ground under a point, and its material and colour; nil when there is nothing there.
local function findGround(point: Vector3): (Vector3?, Enum.Material, Color3)
	local origin = point + Vector3.new(0, GROUND_RAY_HEIGHT, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -(GROUND_RAY_HEIGHT + GROUND_RAY_DEPTH), 0), groundParams)
	if not result then
		return nil, Enum.Material.Slate, FALLBACK_COLOR
	end

	local hit = result.Instance
	local color = if hit:IsA("Terrain")
		then hit:GetMaterialColor(result.Material)
		elseif hit:IsA("BasePart") then hit.Color
		else FALLBACK_COLOR
	return result.Position, result.Material, color
end

--// Pieces ----------------------------------------------------------------------------

-- One chunk tilted away from the centre: pokes up out of the ground, holds, then sinks back.
local function playChunk(center: Vector3, angle: number, ringRadius: number, delay: number, settings: typeof(DEFAULTS))
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local ground, material, color = findGround(center + outward * ringRadius)
	if not ground then
		return
	end

	local part = acquirePart()
	if not part then
		return
	end

	local width = settings.chunkSize * random:NextNumber(0.7, 1.3)
	local height = settings.height * random:NextNumber(0.75, 1.25)
	local length = height * 2 -- the buried half keeps the chunk from floating when it tilts
	part.Size = Vector3.new(width, length, width * random:NextNumber(0.7, 1.1))
	part.Material = material
	part.Color = color

	-- Tilted outward so the ring looks pushed open from the middle.
	local tilt = CFrame.Angles(-math.rad(random:NextNumber(15, 35)), random:NextNumber(-0.3, 0.3), random:NextNumber(-0.2, 0.2))
	local facing = CFrame.lookAt(ground, ground + outward) * tilt
	local raised = facing * CFrame.new(0, height - length / 2, 0)
	local buried = facing * CFrame.new(0, -length / 2 - 0.2, 0)
	part.CFrame = buried

	local holdSeconds = math.max(settings.lifetime - delay - settings.riseSeconds - settings.sinkSeconds, 0)
	local rise = tweenService:Create(part, TweenInfo.new(settings.riseSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = raised,
	})
	local sink = tweenService:Create(
		part,
		TweenInfo.new(settings.sinkSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, holdSeconds),
		{ CFrame = buried }
	)
	rise.Completed:Once(function()
		sink:Play()
	end)
	sink.Completed:Once(function()
		releasePart(part)
	end)
	task.delay(delay, function()
		rise:Play()
	end)
end

-- Small rocks flung up and out that shrink away before they would land.
local function playDebris(center: Vector3, material: Enum.Material, color: Color3, count: number, spread: number)
	for _ = 1, count do
		local part = acquirePart()
		if not part then
			return
		end

		local size = random:NextNumber(0.5, 1.1)
		local angle = random:NextNumber(0, math.pi * 2)
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		part.Size = Vector3.one * size
		part.Material = material
		part.Color = color
		part.CFrame = CFrame.new(center + outward * random:NextNumber(0, spread) + Vector3.new(0, 0.5, 0))
			* CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0)
		part.Anchored = false
		part.AssemblyLinearVelocity = outward * random:NextNumber(10, 24) + Vector3.new(0, random:NextNumber(40, 60), 0)
		part.AssemblyAngularVelocity = Vector3.new(random:NextNumber(-10, 10), random:NextNumber(-10, 10), random:NextNumber(-10, 10))

		local airSeconds = random:NextNumber(0.45, 0.6)
		local shrink = tweenService:Create(part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, airSeconds), {
			Size = Vector3.one * 0.05,
		})
		shrink.Completed:Once(function()
			releasePart(part)
		end)
		shrink:Play()
	end
end

-- A flat ground-coloured disc that races outward and fades.
local function playShockwave(ground: Vector3, color: Color3, radius: number, seconds: number)
	local part = acquirePart()
	if not part then
		return
	end

	local flat = CFrame.new(ground + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's round faces point along X
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color:Lerp(Color3.new(1, 1, 1), 0.35)
	part.Transparency = 0.3
	part.Size = Vector3.new(0.2, 2, 2)
	part.CFrame = flat

	local tween = tweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	})
	tween.Completed:Once(function()
		part.Shape = Enum.PartType.Block
		releasePart(part)
	end)
	tween:Play()
end

local function playDust(ground: Vector3, color: Color3, count: number, spread: number)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = ground + Vector3.new(0, 0.5, 0)
	attachment.Parent = workspace.Terrain

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.45))
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, spread * 0.15),
		NumberSequenceKeypoint.new(1, spread * 0.45),
	})
	dust.Lifetime = NumberRange.new(0.8, 1.3)
	dust.Speed = NumberRange.new(spread * 0.8, spread * 1.6)
	dust.SpreadAngle = Vector2.new(180, 15) -- flat outward puff along the ground
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Drag = 4
	dust.Acceleration = Vector3.new(0, 3, 0)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-40, 40)
	dust.LightInfluence = 0.6
	dust.Enabled = false
	dust.Parent = attachment
	dust:Emit(count)

	task.delay(1.5, function()
		attachment:Destroy()
	end)
end

--// Camera shake ----------------------------------------------------------------------

-- Bound after the camera scripts so the offset never builds up frame to frame.
local function updateShake()
	local camera = workspace.CurrentCamera
	local left = shakeEndsAt - os.clock()
	if not camera or left <= 0 then
		runService:UnbindFromRenderStep(SHAKE_BIND_NAME)
		shakeStrength = 0
		return
	end

	local strength = shakeStrength * (left / shakeDuration) ^ 2
	local offset = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)) * strength
	camera.CFrame *= CFrame.new(offset)
end

local function shakeCamera(origin: Vector3, strength: number, range: number, seconds: number)
	local camera = workspace.CurrentCamera
	if not camera or strength <= 0 then
		return
	end

	local distance = (camera.Focus.Position - origin).Magnitude
	if distance > range then
		return
	end

	local scaled = strength * (1 - distance / range)
	if shakeStrength <= 0 then
		runService:BindToRenderStep(SHAKE_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateShake)
	end
	shakeStrength = math.max(shakeStrength, scaled)
	shakeDuration = seconds
	shakeEndsAt = os.clock() + seconds
end

--// API ---------------------------------------------------------------------------------

function GroundBurst.play(position: Vector3, options: Options?)
	local settings = table.clone(DEFAULTS)
	if options then
		for key, value in options :: any do
			(settings :: any)[key] = value
		end
	end

	refreshGroundFilter(options and options.ignore)
	local ground, material, color = findGround(position)
	local center = ground or position

	local rings = math.max(math.floor(settings.rings), 1)
	local chunkCount = math.max(math.floor(settings.chunkCount), 0)
	local outerRadius = math.max(settings.radius, settings.innerRadius)
	local ringRadii: { number } = {}
	local radiusSum = 0
	for ring = 1, rings do
		local ringRadius = if rings == 1 then outerRadius else settings.innerRadius + (outerRadius - settings.innerRadius) * (ring - 1) / (rings - 1)
		ringRadii[ring] = ringRadius
		radiusSum += ringRadius
	end

	-- Outer rings are longer, so they get more chunks and keep the same spacing.
	for _, ringRadius in ringRadii do
		local share = chunkCount * ringRadius / math.max(radiusSum, 0.01)
		local count = if chunkCount > 0 then math.max(math.floor(share + 0.5), 1) else 0
		local offset = random:NextNumber(0, math.pi * 2)
		local delay = ringRadius / math.max(settings.waveSpeed, 1)
		for index = 1, count do
			local angle = offset + (index - 1) / count * math.pi * 2 + random:NextNumber(-0.12, 0.12)
			playChunk(center, angle, ringRadius * random:NextNumber(0.92, 1.08), delay, settings)
		end
	end

	if settings.debrisCount > 0 then
		playDebris(center, material, color, settings.debrisCount, outerRadius)
	end
	if settings.dustCount > 0 then
		playDust(center, color, settings.dustCount, math.max(outerRadius, 2))
	end
	if settings.shockwaveRadius > 0 then
		playShockwave(center, color, settings.shockwaveRadius, math.min(settings.lifetime, 0.6))
	end
	if settings.shake > 0 then
		shakeCamera(center, settings.shake, settings.shakeRange, settings.shakeSeconds)
	end
end

return GroundBurst
