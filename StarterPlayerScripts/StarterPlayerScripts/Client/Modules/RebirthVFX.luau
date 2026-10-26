--!strict

--[[
	Plays the rebirth "level up" burst: clones the Studio-built RebirthVFX part, spins its rings and helix sparks, then cleans up.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.RebirthVFX
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Configs
local TEMPLATE_NAME = "RebirthVFX"
local ROOT_HEIGHT = 0.5 -- the template's center sits this far above the ground point
local RING_PLANE_HEIGHT = 0.08
local R6_LEG_HEIGHT = 2
local CLEANUP_SECONDS = 0.8 -- lets the last particles finish before the clone is destroyed
local MIN_RADIUS = 0.05
local MIN_SIZE = 0.01
local FADE_TRANSPARENCY = 0.6 -- half-transparent neon looks grey, so parts shrink instead of fully fading
local GEM_LIFT = 0.3
local GEM_TILT = math.rad(45)
local GEM_SPIN = 12

-- Defaults for the tuning attributes on the template's root part.
local DEFAULTS = {
	Duration = 0.75,
	OuterRadius = 4.5,
	OuterSpin = 900,
	InnerRadius = 2.6,
	InnerSpin = -1300,
	InnerRise = 5.5,
	HelixRadius = 3.4,
	HelixHeight = 6.5,
	HelixTurns = 1.75,
	LightBrightness = 6,
}

export type Target = Model | BasePart | CFrame | Vector3
export type Options = {
	timeScale: number?, -- slow-motion debugging, 0.01-1
}

type RingPart = {
	part: BasePart,
	angle: number,
	size: Vector3,
	isGem: boolean,
}

type Ring = {
	parts: { RingPart },
	dashCount: number,
	fill: number,
}

type Spark = {
	part: BasePart,
	dir: number,
	phase: number,
	trail: Trail?,
	glitter: ParticleEmitter?,
}

type Stream = {
	emitter: ParticleEmitter,
	stopAt: number,
}

local RebirthVFX = {}

--// Helpers ---------------------------------------------------------------------

local function easeOutCubic(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local function fadeAfter(u: number, from: number): number
	return math.clamp((u - from) / (1 - from), 0, 1)
end

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- ReplicatedStorage.Assets.VFX first, then Workspace.
local function findTemplate(): BasePart?
	local assets = replicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local template = (vfx and vfx:FindFirstChild(TEMPLATE_NAME)) or workspace:FindFirstChild(TEMPLATE_NAME)
	return if template and template:IsA("BasePart") then template else nil
end

local function characterGround(character: Model): Vector3?
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local legs = if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight else R6_LEG_HEIGHT
	return root.Position - Vector3.new(0, root.Size.Y / 2 + legs, 0)
end

-- Bottom of the part's world-space bounding box, so tilted parts still land on the right spot.
local function partBottom(part: BasePart): Vector3
	local cframe, size = part.CFrame, part.Size
	local halfHeight = (math.abs(cframe.RightVector.Y) * size.X + math.abs(cframe.UpVector.Y) * size.Y + math.abs(cframe.LookVector.Y) * size.Z) / 2
	return part.Position - Vector3.new(0, halfHeight, 0)
end

-- nil once an Instance target has been removed.
local function resolveGround(target: Target): Vector3?
	if typeof(target) == "Vector3" then
		return target :: Vector3
	elseif typeof(target) == "CFrame" then
		return (target :: CFrame).Position
	end

	local instance = target :: Instance
	if not instance:IsDescendantOf(workspace) then
		return nil
	elseif instance:IsA("BasePart") then
		return partBottom(instance :: BasePart)
	elseif instance:IsA("Model") then
		return characterGround(instance :: Model)
	end
	return nil
end

local function collectRing(folder: Instance?): Ring
	local ring: Ring = { parts = {}, dashCount = 0, fill = 1 }
	if not folder then
		return ring
	end

	ring.fill = numberAttribute(folder, "Fill", 1)
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "Dash" or child.Name == "Gem") then
			table.insert(ring.parts, {
				part = child,
				angle = numberAttribute(child, "Angle", 0),
				size = child.Size,
				isGem = child.Name == "Gem",
			})
			if child.Name == "Dash" then
				ring.dashCount += 1
			end
		end
	end
	return ring
end

local function collectSparks(folder: Instance?): { Spark }
	local sparks: { Spark } = {}
	if not folder then
		return sparks
	end

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Spark" then
			table.insert(sparks, {
				part = child,
				dir = numberAttribute(child, "Dir", 1),
				phase = numberAttribute(child, "Phase", 0),
				trail = child:FindFirstChildOfClass("Trail"),
				glitter = child:FindFirstChild("Glitter") :: ParticleEmitter?,
			})
		end
	end
	return sparks
end

local function updateRing(ring: Ring, plane: CFrame, radius: number, spin: number, fade: number, effectTime: number)
	local keep = 1 - fade
	local dashWidth = math.max(radius * (2 * math.pi / math.max(ring.dashCount, 1)) * ring.fill, MIN_SIZE)
	local minSize = Vector3.one * MIN_SIZE

	for _, entry in ring.parts do
		local placed = plane * CFrame.Angles(0, entry.angle + spin, 0)
		if entry.isGem then
			entry.part.Size = (entry.size * keep):Max(minSize)
			entry.part.CFrame = placed * CFrame.new(0, GEM_LIFT, -radius) * CFrame.Angles(GEM_TILT, effectTime * GEM_SPIN, GEM_TILT)
		else
			entry.part.Size = Vector3.new(dashWidth, math.max(entry.size.Y * keep, MIN_SIZE), math.max(entry.size.Z * keep, MIN_SIZE))
			entry.part.CFrame = placed * CFrame.new(0, 0, -radius)
		end
		entry.part.Transparency = fade * FADE_TRANSPARENCY
	end
end

--// API -------------------------------------------------------------------------

-- target is a character, a BasePart, or a ground CFrame / Vector3. Instance targets are followed until removed.
function RebirthVFX.play(target: Target, options: Options?)
	local template = findTemplate()
	if not template then
		warn("RebirthVFX: template not found in ReplicatedStorage.Assets.VFX or Workspace")
		return
	end

	local ground = resolveGround(target)
	if not ground then
		return
	end

	local timeScale = math.clamp(options and options.timeScale or 1, 0.01, 1)
	local tuning: { [string]: number } = {}
	for name, default in DEFAULTS do
		tuning[name] = numberAttribute(template, name, default)
	end
	local duration = tuning.Duration / timeScale
	local follows = typeof(target) == "Instance"

	local effect = template:Clone()
	local pillar = effect:FindFirstChild("Pillar") :: BasePart?
	local pillarOffset = if pillar then effect.CFrame:ToObjectSpace(pillar.CFrame) else CFrame.identity

	local burst = effect:FindFirstChild("Burst")
	local glow = burst and burst:FindFirstChild("Glow") :: PointLight?
	local outerRing = collectRing(effect:FindFirstChild("OuterRing"))
	local innerRing = collectRing(effect:FindFirstChild("InnerRing"))
	local sparks = collectSparks(effect:FindFirstChild("Helix"))

	local function update(u: number, groundPoint: Vector3)
		local effectTime = u * tuning.Duration
		local rootCFrame = CFrame.new(groundPoint + Vector3.new(0, ROOT_HEIGHT, 0))
		effect.CFrame = rootCFrame
		if pillar then
			pillar.CFrame = rootCFrame * pillarOffset
		end

		local plane = CFrame.new(groundPoint + Vector3.new(0, RING_PLANE_HEIGHT, 0))
		local grow = easeOutBack(math.clamp(u / 0.28, 0, 1))
		local climb = easeOutCubic(u)

		updateRing(
			outerRing,
			plane,
			math.max(tuning.OuterRadius * grow, MIN_RADIUS),
			math.rad(tuning.OuterSpin) * effectTime,
			fadeAfter(u, 0.55),
			effectTime
		)
		updateRing(
			innerRing,
			plane * CFrame.new(0, tuning.InnerRise * climb, 0),
			math.max(tuning.InnerRadius * grow * (1 - 0.45 * climb), MIN_RADIUS),
			math.rad(tuning.InnerSpin) * effectTime,
			fadeAfter(u, 0.45),
			effectTime
		)

		-- Conical double helix with a 3-lobed wobble.
		local sparkFade = fadeAfter(u, 0.7)
		local sparkSize = (0.6 - 0.35 * climb) * (1 - 0.9 * sparkFade)
		for _, spark in sparks do
			local theta = spark.phase + spark.dir * 2 * math.pi * tuning.HelixTurns * climb
			local radius = tuning.HelixRadius * (1 - 0.6 * climb) * (1 + 0.15 * math.sin(3 * theta))
			local height = 0.3 + tuning.HelixHeight * climb + 0.35 * math.sin(2 * theta)
			spark.part.Size = Vector3.one * sparkSize
			spark.part.CFrame = CFrame.new(groundPoint + Vector3.new(math.cos(theta) * radius, height, math.sin(theta) * radius))
			spark.part.Transparency = sparkFade * FADE_TRANSPARENCY
		end

		if glow then
			glow.Brightness = tuning.LightBrightness * math.min(u / 0.08, 1) * (1 - u) ^ 2
		end
	end

	-- Place everything before parenting so nothing streaks from the template's spot.
	update(0, ground)
	effect.Parent = workspace

	local emitters: { ParticleEmitter } = {}
	local streams: { Stream } = {}
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.TimeScale = timeScale
			table.insert(emitters, descendant)

			local emitCount = descendant:GetAttribute("EmitCount")
			local streamFor = descendant:GetAttribute("StreamFor")
			if type(emitCount) == "number" then
				descendant:Emit(emitCount)
			elseif type(streamFor) == "number" then
				descendant.Enabled = true
				table.insert(streams, { emitter = descendant, stopAt = streamFor })
			end
		end
	end

	for _, spark in sparks do
		if spark.trail then
			spark.trail:Clear()
			spark.trail.Enabled = true
		end
		if spark.glitter then
			spark.glitter.Enabled = true
		end
	end

	local elapsed = 0
	local connection: RBXScriptConnection
	local finished = false

	local function finish()
		if finished then
			return
		end
		finished = true
		connection:Disconnect()

		for _, emitter in emitters do
			emitter.Enabled = false
		end
		for _, descendant in effect:GetDescendants() do
			if descendant:IsA("Trail") then
				descendant.Enabled = false
			elseif descendant:IsA("BasePart") then
				descendant.Transparency = 1
			end
		end
		effect.Transparency = 1
		if glow then
			glow.Brightness = 0
		end

		task.delay(CLEANUP_SECONDS / timeScale, function()
			effect:Destroy()
		end)
	end

	connection = runService.PreRender:Connect(function(deltaTime: number)
		if not effect.Parent then
			finish()
			return
		end

		if follows then
			local current = resolveGround(target)
			if not current then
				finish()
				return
			end
			ground = current
		end

		elapsed += deltaTime
		local u = math.min(elapsed / duration, 1)
		update(u, ground :: Vector3)

		for _, stream in streams do
			if stream.emitter.Enabled and u >= stream.stopAt then
				stream.emitter.Enabled = false
			end
		end

		if u >= 1 then
			finish()
		end
	end)
end

return RebirthVFX
