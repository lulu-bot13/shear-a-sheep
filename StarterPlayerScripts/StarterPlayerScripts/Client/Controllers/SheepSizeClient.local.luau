--!strict

--[[
	Plays HugeSpawnVFX where a Huge sheep is about to land, gives Huge sheep a glow, and announces one spawning on your plot.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SheepSizeClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local announcements = require(script.Parent.Parent.Modules.Announcements)
local network = require(replicatedStorage.Shared.Utils.Network)

--// References
local vfxFolder = replicatedStorage.Assets:FindFirstChild("VFX")
local hugeSpawnTemplate = vfxFolder and vfxFolder:FindFirstChild("HugeSpawnVFX")
if not hugeSpawnTemplate or not hugeSpawnTemplate:IsA("BasePart") then
	warn("SheepSizeClient: no Assets.VFX.HugeSpawnVFX part in ReplicatedStorage, so Huge spawns get no effect.")
	hugeSpawnTemplate = nil
end

--// Configs
local SHEEP_TAG = "Sheep"
local AURA_NAME = "SizeAura"
local ANNOUNCED_TIERS = { Huge = true } -- mirrors the server's SheepSizeData ids
local FRESH_SECONDS = 3 -- older sheep are ones streaming in, not new spawns
local ROOT_TIMEOUT = 5
local LIGHT_RANGE = 10 -- studs
local LIGHT_BRIGHTNESS = 1.5
local PARTICLE_RATE = 4 -- per second
local PILLAR_FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GLOW_FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- up and back: 0.6s
local SHAKE_BIND_NAME = "HugeSpawnShake"
local SHAKE_STRENGTH = 0.3 -- studs, plot owner only
local SHAKE_SECONDS = 0.3

--// State
local localPlayer = players.LocalPlayer
local tracked: { [Instance]: boolean } = {}
local random = Random.new()

--// Helpers -------------------------------------------------------------------------

local function addAura(root: BasePart, color: Color3)
	local aura = Instance.new("Attachment")
	aura.Name = AURA_NAME

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = aura

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.Rate = PARTICLE_RATE
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.3, 1)
	sparkles.Parent = aura

	aura.Parent = root
end

local function announce(sheep: Instance, color: Color3)
	local tier = sheep:GetAttribute("SizeTier")
	local name = sheep:GetAttribute("SheepName")
	local weight = sheep:GetAttribute("Weight")
	if type(tier) ~= "string" or type(name) ~= "string" then
		return
	end

	-- SheepName already carries the size prefix; only that word is coloured.
	local coloredName = string.gsub(name, tier, `<font color="#{color:ToHex()}">{string.upper(tier)}</font>`, 1)
	local weightText = if type(weight) == "number" then ` ({weight} kg)` else ""
	announcements.show("ClaimAlert", `A {coloredName} appeared!{weightText}`, true)
end

local function onSheepAdded(sheep: Instance)
	local tier = sheep:GetAttribute("SizeTier")
	local color = sheep:GetAttribute("SizeColor")
	if type(tier) ~= "string" or not ANNOUNCED_TIERS[tier] or typeof(color) ~= "Color3" then
		return
	end
	tracked[sheep] = true

	local spawnedAt = sheep:GetAttribute("SpawnedAt")
	if sheep:GetAttribute("OwnerId") == localPlayer.UserId
		and type(spawnedAt) == "number"
		and workspace:GetServerTimeNow() - spawnedAt <= FRESH_SECONDS
	then
		announce(sheep, color)
	end

	task.spawn(function()
		local root = sheep:FindFirstChild("HumanoidRootPart") or sheep:WaitForChild("HumanoidRootPart", ROOT_TIMEOUT)
		if tracked[sheep] and root and root:IsA("BasePart") and not root:FindFirstChild(AURA_NAME) then
			addAura(root, color)
		end
	end)
end

-- The tag comes off as a bare sheep vanishes, or when it streams out or is pooled away.
local function onSheepRemoved(sheep: Instance)
	if not tracked[sheep] then
		return
	end
	tracked[sheep] = nil

	local root = sheep:FindFirstChild("HumanoidRootPart")
	local aura = root and root:FindFirstChild(AURA_NAME)
	if aura then
		aura:Destroy()
	end
end

--// Huge spawn effect -----------------------------------------------------------------

local shaking = false
local shakeEndsAt = 0

local function getNumber(instance: Instance, attribute: string, default: number): number
	local value = instance:GetAttribute(attribute)
	return if type(value) == "number" then value else default
end

-- Bound after the camera scripts so the offset never builds up frame to frame.
local function updateShake()
	local camera = workspace.CurrentCamera
	local left = shakeEndsAt - os.clock()
	if not camera or left <= 0 then
		runService:UnbindFromRenderStep(SHAKE_BIND_NAME)
		shaking = false
		return
	end
	camera.CFrame *= CFrame.new(random:NextUnitVector() * SHAKE_STRENGTH * left / SHAKE_SECONDS)
end

local function shakeCamera()
	shakeEndsAt = os.clock() + SHAKE_SECONDS
	if not shaking then
		shaking = true
		runService:BindToRenderStep(SHAKE_BIND_NAME, Enum.RenderPriority.Camera.Value + 1, updateShake)
	end
end

-- Beam Transparency can't be tweened, so a NumberValue eases each keypoint towards fully clear.
local function fadeBeam(beam: Beam)
	local keypoints = beam.Transparency.Keypoints
	local alpha = Instance.new("NumberValue")
	alpha:GetPropertyChangedSignal("Value"):Connect(function()
		local faded = {}
		for index, keypoint in keypoints do
			faded[index] = NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value + (1 - keypoint.Value) * alpha.Value, keypoint.Envelope)
		end
		beam.Transparency = NumberSequence.new(faded)
	end)

	local tween = tweenService:Create(alpha, PILLAR_FADE, { Value = 1 })
	tween.Completed:Connect(function()
		alpha:Destroy()
		beam.Enabled = false
	end)
	tween:Play()
end

--[[
	The pillar grows and windup particles play at once; when the sheep lands (after WindupSeconds) the pillar fades,
	the glow flashes and the plot owner's camera shakes. Landing particles keep their own EmitDelay.
	`landingOnly` (a Halloween rise stands in for the windup) skips the pillar and windup particles and starts at the landing.
]]
local function playHugeSpawn(groundCFrame: CFrame, ownerId: number, landingOnly: boolean?)
	if not hugeSpawnTemplate or typeof(groundCFrame) ~= "CFrame" then
		return
	end

	local effect = hugeSpawnTemplate:Clone() :: BasePart
	local windup = getNumber(effect, "WindupSeconds", 0.7)
	local skipped = if landingOnly then windup else 0
	effect.CFrame = groundCFrame
	effect.Parent = workspace

	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local count = getNumber(descendant, "EmitCount", 0)
			local delay = getNumber(descendant, "EmitDelay", 0) - skipped
			if delay < 0 then
				continue -- a windup particle
			elseif delay > 0 then
				task.delay(delay, function()
					if descendant.Parent then
						descendant:Emit(count)
					end
				end)
			else
				descendant:Emit(count)
			end
		end
	end

	local found = effect:FindFirstChild("Pillar", true)
	local pillar = if found and found:IsA("Beam") then found else nil
	if pillar and landingOnly then
		pillar.Enabled = false
	elseif pillar then
		local top = pillar.Attachment1
		if top then
			top.Position = Vector3.new(top.Position.X, getNumber(effect, "PillarHeight", top.Position.Y), top.Position.Z)
		end
		local width0, width1 = pillar.Width0, pillar.Width1
		pillar.Width0, pillar.Width1 = 0, 0
		pillar.Enabled = true
		tweenService:Create(pillar, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Width0 = width0, Width1 = width1 }):Play()
	end

	task.delay(windup - skipped, function()
		if not effect.Parent then
			return
		end
		if pillar and pillar.Enabled then
			fadeBeam(pillar)
		end
		local burst = effect:FindFirstChild("Burst")
		local glow = burst and burst:FindFirstChild("Glow")
		if glow and glow:IsA("PointLight") then
			tweenService:Create(glow, GLOW_FLASH, { Brightness = getNumber(effect, "LightBrightness", 6) }):Play()
		end
		if ownerId == localPlayer.UserId then
			shakeCamera()
		end
	end)

	task.delay(getNumber(effect, "Duration", 2.2) - skipped, function()
		effect:Destroy()
	end)
end

-- A Huge sheep rising out of a Halloween pit gets the landing burst as it comes out.
local function onHalloweenSpawn(spawnInfo: any)
	if type(spawnInfo) ~= "table" or spawnInfo.sizeTier ~= "Huge" then
		return
	end
	task.delay(spawnInfo.openSeconds + spawnInfo.riseSeconds, playHugeSpawn, spawnInfo.floor, spawnInfo.ownerId, true)
end

--// Setup -------------------------------------------------------------------------------

for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
	onSheepAdded(sheep)
end
collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(onSheepRemoved)

network.waitUntilReadyAsync()
network.connectEvent(network.RemoteEvents.HugeSheepSpawn, playHugeSpawn)
network.connectEvent(network.RemoteEvents.HalloweenSheepSpawn, onHalloweenSpawn)
