--!strict

--[[
	King Sheep effects: the golden pillar it arrives in, the charge-up and blast when it's defeated, poofs and flying wool.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.KingSheepVFX
]]--

--// Services
local debris = game:GetService("Debris")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local cutscene = require(script.Parent.KingSheepCutscene)
local settings = require(script.Parent.Settings)

--// Instances
local vfxFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX", 10)
local pillarTemplate = if vfxFolder then vfxFolder:FindFirstChild("HugeSpawnVFX") else nil
local poofTemplate = if vfxFolder then vfxFolder:FindFirstChild("PoofAttachment") else nil
if not pillarTemplate or not pillarTemplate:IsA("BasePart") then
	warn("KingSheepVFX: ReplicatedStorage.Assets.VFX.HugeSpawnVFX is missing, so the King Sheep's pillar and burst are skipped.")
	pillarTemplate = nil
end
if not poofTemplate or not poofTemplate:IsA("Attachment") then
	warn("KingSheepVFX: ReplicatedStorage.Assets.VFX.PoofAttachment is missing; build it in Studio.")
	poofTemplate = nil
end

--// Configs
local REVEAL_SCALE = 3 -- HugeSpawnVFX was built for a Huge sheep; the King is far bigger
local DEFEAT_SCALE = 3.5
local EMIT_BOOST = 2 -- particle counts on the King's effects, times the template's EmitCount
local POOF_DEFAULT_EMIT_COUNT = 20
local SHAKE_RANGE = 140 -- studs from the camera; closer players feel the arrival and the blast outside a cutscene
local GOLD = Color3.fromRGB(255, 205, 64)
local WHITE_GOLD = Color3.fromRGB(255, 246, 214)
local WOOL_COLOR = Color3.fromRGB(250, 248, 240)
local WOOL_PUFF_LIFETIME = 1.4
local RING_THICKNESS = 0.2
local CHARGE_SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 205, 64),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 120, 190),
	Color3.fromRGB(120, 210, 255),
}

export type RevealTarget = {
	position: Vector3, -- the ground at its feet
	height: number,
}

export type DefeatTarget = {
	boss: Model?,
	center: Vector3,
	height: number,
	explodeAt: number, -- seconds until the blast
}

--// State
local random = Random.new()

local KingSheepVFX = {}

local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "WorldBossEffects"
effectsFolder.Parent = workspace
KingSheepVFX.folder = effectsFolder

--// Helpers ------------------------------------------------------------------------

local function getNumber(instance: Instance, attribute: string, default: number): number
	local value = instance:GetAttribute(attribute)
	return if type(value) == "number" then value else default
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = tweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function scaleSequence(sequence: NumberSequence, scale: number): NumberSequence
	local keypoints = {}
	for index, keypoint in sequence.Keypoints do
		keypoints[index] = NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * scale, keypoint.Envelope * scale)
	end
	return NumberSequence.new(keypoints)
end

-- Grows a cloned effect's particles, beams, lights and attachment offsets by `scale`.
local function scaleEffect(effect: Instance, scale: number)
	if effect:IsA("BasePart") then
		effect.Size *= scale
	end
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Size = scaleSequence(descendant.Size, scale)
			descendant.Speed = NumberRange.new(descendant.Speed.Min * scale, descendant.Speed.Max * scale)
		elseif descendant:IsA("Beam") then
			descendant.Width0 *= scale
			descendant.Width1 *= scale
		elseif descendant:IsA("Attachment") then
			descendant.Position *= scale
		elseif descendant:IsA("PointLight") then
			descendant.Range = math.min(descendant.Range * scale, 60)
		end
	end
end

local function newPart(shape: Enum.PartType, color: Color3, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = effectsFolder
	return part
end

-- An invisible anchored part to hold lights and particles.
local function newHolder(position: Vector3, size: number): Part
	local holder = newPart(Enum.PartType.Ball, WHITE_GOLD, Vector3.one * size, CFrame.new(position))
	holder.Transparency = 1
	return holder
end

local function isNearCamera(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= SHAKE_RANGE
end

-- A flat neon ring on the ground that races outwards and fades.
local function shockwave(ground: Vector3, diameter: number, color: Color3, seconds: number)
	local disc = newPart(Enum.PartType.Cylinder, color, Vector3.new(RING_THICKNESS, 2, 2),
		CFrame.new(ground + Vector3.new(0, RING_THICKNESS, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	disc.Transparency = 0.15
	tween(disc, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(RING_THICKNESS, diameter, diameter),
		Transparency = 1,
	})
	debris:AddItem(disc, seconds)
end

-- Beam Transparency can't be tweened, so a NumberValue eases each keypoint towards fully clear.
local function fadeBeam(beam: Beam, seconds: number)
	local keypoints = beam.Transparency.Keypoints
	local alpha = Instance.new("NumberValue")
	alpha:GetPropertyChangedSignal("Value"):Connect(function()
		local faded = {}
		for index, keypoint in keypoints do
			faded[index] = NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value + (1 - keypoint.Value) * alpha.Value, keypoint.Envelope)
		end
		beam.Transparency = NumberSequence.new(faded)
	end)
	local fadeTween = tween(alpha, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
	fadeTween.Completed:Connect(function()
		alpha:Destroy()
		beam.Enabled = false
	end)
end

--[[
	The HugeSpawnVFX pillar and burst grown by `scale`: the pillar rises to `pillarHeight` over its windup, then the burst,
	glow flash and landing particles fire (each keeps its own EmitDelay). `landingOnly` skips the pillar and starts at the burst.
]]
local function playPillar(ground: Vector3, scale: number, pillarHeight: number, landingOnly: boolean)
	if not pillarTemplate then
		return
	end
	local effect = pillarTemplate:Clone() :: BasePart
	local windup = getNumber(effect, "WindupSeconds", 0.7)
	local skipped = if landingOnly then windup else 0
	scaleEffect(effect, scale)
	effect.CFrame = CFrame.new(ground)
	effect.Parent = effectsFolder

	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local count = settings.effectCount(getNumber(descendant, "EmitCount", 0) * EMIT_BOOST)
			local delay = getNumber(descendant, "EmitDelay", 0) - skipped
			if delay < 0 then
				continue
			end
			task.delay(delay, function()
				if descendant.Parent then
					descendant:Emit(count)
				end
			end)
		end
	end

	local found = effect:FindFirstChild("Pillar", true)
	local pillar = if found and found:IsA("Beam") then found else nil
	if pillar and landingOnly then
		pillar.Enabled = false
	elseif pillar then
		local top = pillar.Attachment1
		if top then
			top.Position = Vector3.new(top.Position.X, pillarHeight, top.Position.Z)
		end
		local width0, width1 = pillar.Width0, pillar.Width1
		pillar.Width0, pillar.Width1 = 0, 0
		pillar.Enabled = true
		tween(pillar, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Width0 = width0, Width1 = width1 })
	end

	task.delay(windup - skipped, function()
		if not effect.Parent then
			return
		end
		if pillar and pillar.Enabled then
			fadeBeam(pillar, 0.6)
		end
		local burst = effect:FindFirstChild("Burst")
		local glow = burst and burst:FindFirstChild("Glow")
		if glow and glow:IsA("PointLight") then
			tween(glow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Brightness = getNumber(effect, "LightBrightness", 6) * 1.5,
			})
		end
	end)
	debris:AddItem(effect, getNumber(effect, "Duration", 2.2) - skipped + 1)
end

-- A short-lived light that flares up and fades.
local function lightFlash(position: Vector3, brightness: number, range: number, seconds: number)
	local holder = newHolder(position, 1)
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = holder
	tween(light, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 })
	debris:AddItem(holder, seconds)
end

-- Gold, white, pink and blue sparkles thrown up and raining down.
local function confetti(position: Vector3, count: number, power: number)
	local holder = newHolder(position, 2)
	for index, color in CONFETTI_COLORS do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = CHARGE_SPARK_TEXTURE
		emitter.Color = ColorSequence.new(color)
		emitter.LightEmission = if index == 1 then 0.8 else 0.3
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.8, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Lifetime = NumberRange.new(1.4, 2.4)
		emitter.Speed = NumberRange.new(power * 0.55, power)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = Vector3.new(0, -power * 0.9, 0)
		emitter.Drag = 1.2
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-260, 260)
		emitter.Rate = 0
		emitter.Enabled = false
		emitter.Parent = holder
		emitter:Emit(settings.effectCount(math.ceil(count / #CONFETTI_COLORS)))
	end
	debris:AddItem(holder, 3)
end

-- Hides every visible piece of the model on this client only (the server removes it a moment later).
local function hideModel(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			(descendant :: any).LocalTransparencyModifier = 1
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail")
			or descendant:IsA("BillboardGui") or descendant:IsA("Highlight")
		then
			(descendant :: any).Enabled = false
		end
	end
end

--// Public API ------------------------------------------------------------------

-- Wool puffs flung out from `position`.
function KingSheepVFX.throwWool(position: Vector3, count: number, power: number?)
	local strength = power or 1
	for _ = 1, settings.effectCount(count) do
		local puff = Instance.new("Part")
		puff.Shape = Enum.PartType.Ball
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = WOOL_COLOR
		puff.Size = Vector3.one * (1 + random:NextNumber())
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CastShadow = false
		puff.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		puff.Parent = effectsFolder
		local angle = random:NextNumber(0, math.pi * 2)
		puff.AssemblyLinearVelocity = (Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(14, 24)
			+ Vector3.new(0, random:NextNumber(25, 40), 0)) * strength
		debris:AddItem(puff, WOOL_PUFF_LIFETIME)
	end
end

-- One PoofAttachment cloud at `position`, its counts times `boost`.
function KingSheepVFX.poof(position: Vector3, boost: number?)
	if not poofTemplate then
		return
	end
	local poof = poofTemplate:Clone() :: Attachment
	poof.Parent = workspace.Terrain
	poof.WorldPosition = position

	local lifetime = 0
	for _, descendant in poof:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = getNumber(descendant, "EmitCount", POOF_DEFAULT_EMIT_COUNT) * (boost or 1)
			descendant:Emit(settings.effectCount(math.floor(emitCount + 0.5)))
			lifetime = math.max(lifetime, descendant.Lifetime.Max)
		end
	end
	debris:AddItem(poof, lifetime + 0.5)
end

-- The arrival: a golden pillar rises at its feet, then bursts with a shockwave, a thunder crack and a royal bleat.
function KingSheepVFX.playReveal(target: RevealTarget)
	local ground, height = target.position, math.max(target.height, 4)
	playPillar(ground, REVEAL_SCALE, height * 2.5, false)
	local windup = if pillarTemplate then getNumber(pillarTemplate, "WindupSeconds", 0.7) else 0.7

	task.delay(windup, function()
		shockwave(ground, height * 3.4, GOLD, 0.7)
		shockwave(ground, height * 2.2, WHITE_GOLD, 0.5)
		lightFlash(ground + Vector3.new(0, height * 0.5, 0), 10, 50, 1.2)
		KingSheepVFX.throwWool(ground, 16, 1.2)
		cutscene.playSound("Weather", "ThunderStrike", 1.1, 1.6)
		if isNearCamera(ground) then
			cutscene.shake(0.6, 0.5)
		end
	end)
	task.delay(windup + 0.3, function()
		cutscene.playSound("Sheep", "SheepBlat", 0.55, 2)
	end)
end

--[[
	The defeat: the King glows gold and trembles while sparks rush into it, then bursts at `explodeAt` in a blast of light,
	shockwaves, poofs, wool and confetti, and is hidden on this client (the server removes it right after).
]]
function KingSheepVFX.playDefeat(target: DefeatTarget)
	local center, height = target.center, math.max(target.height, 4)
	local ground = center - Vector3.new(0, height / 2, 0)
	local boss = target.boss
	local explodeAt = math.max(target.explodeAt, 0.2)

	-- Charge-up: a gold glow on the model, sparks drawn into it and a light that swells.
	local highlight: Highlight? = nil
	local basePivot: CFrame? = nil
	if boss and boss.Parent then
		local glow = Instance.new("Highlight")
		glow.FillColor = GOLD
		glow.OutlineColor = WHITE_GOLD
		glow.FillTransparency = 1
		glow.OutlineTransparency = 1
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Parent = boss
		tween(glow, TweenInfo.new(explodeAt, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { FillTransparency = 0.1, OutlineTransparency = 0 })
		highlight = glow
		basePivot = boss:GetPivot()
	end

	local holder = newHolder(center, height * 1.3)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = CHARGE_SPARK_TEXTURE
	sparks.Color = ColorSequence.new(GOLD, WHITE_GOLD)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.2) })
	sparks.Lifetime = NumberRange.new(0.45, 0.6)
	sparks.Speed = NumberRange.new(height * 1.1, height * 1.4)
	sparks.Shape = Enum.ParticleEmitterShape.Sphere
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	sparks.Rate = 0
	sparks.Enabled = false
	sparks.Parent = holder
	local chargeLight = Instance.new("PointLight")
	chargeLight.Color = GOLD
	chargeLight.Range = 40
	chargeLight.Brightness = 0
	chargeLight.Shadows = false
	chargeLight.Parent = holder
	tween(chargeLight, TweenInfo.new(explodeAt, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 7 })
	cutscene.playSound("Sheep", "SheepBlat", 0.45, 2)

	local startedAt = os.clock()
	local lastBurst = 0
	local trembling: RBXScriptConnection? = nil
	trembling = runService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		if elapsed >= explodeAt then
			if trembling then
				trembling:Disconnect()
			end
			return
		end
		local progress = elapsed / explodeAt
		if elapsed - lastBurst >= 0.08 then
			lastBurst = elapsed
			sparks:Emit(settings.effectCount(math.ceil(2 + progress * 8)))
		end
		if boss and basePivot and boss.Parent then
			boss:PivotTo(basePivot * CFrame.new(random:NextUnitVector() * progress * progress * 0.45))
		end
	end)

	task.delay(explodeAt, function()
		if trembling then
			trembling:Disconnect()
		end
		if boss and boss.Parent then
			if basePivot then
				boss:PivotTo(basePivot)
			end
			hideModel(boss)
		end
		if highlight then
			highlight:Destroy()
		end
		holder:Destroy()

		local blast = newPart(Enum.PartType.Ball, WHITE_GOLD, Vector3.one * 2, CFrame.new(center))
		blast.Transparency = 0.05
		tween(blast, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * height * 1.9, Transparency = 1 })
		debris:AddItem(blast, 0.6)

		shockwave(ground, height * 4.2, GOLD, 0.8)
		shockwave(ground, height * 3, WHITE_GOLD, 0.6)
		task.delay(0.12, shockwave, ground, height * 5, GOLD, 1)
		playPillar(ground, DEFEAT_SCALE, height * 2, true)
		KingSheepVFX.poof(center, 2)
		for index = 1, 6 do
			local angle = index * math.pi / 3
			KingSheepVFX.poof(center + Vector3.new(math.cos(angle), random:NextNumber(-0.3, 0.3), math.sin(angle)) * height * 0.45, 1.5)
		end
		KingSheepVFX.throwWool(center, 36, 1.3)
		confetti(center, 80, height * 3)
		lightFlash(center, 14, 60, 1.3)
		cutscene.playSound("AbilitySounds", "Smash", 0.8, 1.6)
		cutscene.playSound("Weather", "ThunderStrike", 1.4, 1.2)
		if not cutscene.isPlaying() and isNearCamera(center) then
			cutscene.shake(1.2, 0.7)
		end
	end)
end

return KingSheepVFX
