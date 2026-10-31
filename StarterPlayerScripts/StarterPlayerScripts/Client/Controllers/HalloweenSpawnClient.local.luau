--!strict

--[[
	Opens HalloweenSpawnVFX's pit under a sheep spawned during Halloween and raises the sheep out of the floor.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.HalloweenSpawnClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// References
local vfxFolder = replicatedStorage.Assets:FindFirstChild("VFX")
local spawnTemplate = vfxFolder and vfxFolder:FindFirstChild("HalloweenSpawnVFX")
if not spawnTemplate or not spawnTemplate:IsA("Model") then
	warn("HalloweenSpawnClient: no Assets.VFX.HalloweenSpawnVFX model in ReplicatedStorage, so Halloween spawns get no pit.")
	spawnTemplate = nil
end

--// Configs
local PIT_PARTS = { "Pit", "Rim", "InnerGlow" } -- flat cylinders that grow from nothing to their FullSize
local CLOSED_DIAMETER = 0.001 -- the smallest size a part can have
local RISE_EASING = Enum.EasingStyle.Quad
local GLOW_FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- up and back: 0.6s
local WOBBLE_DEGREES = 5 -- side to side while it climbs, settling as it comes out
local WOBBLE_SPEED = 14 -- radians per second

type SpawnInfo = {
	floor: CFrame,
	emerged: CFrame,
	sheep: Model?, -- nil while it hasn't streamed in
	scale: number,
	openSeconds: number,
	riseSeconds: number,
}

--// Helpers -------------------------------------------------------------------------

local function getNumber(instance: Instance, attribute: string, default: number): number
	local value = instance:GetAttribute(attribute)
	return if type(value) == "number" then value else default
end

local function setHudVisible(sheep: Model, visible: boolean)
	local root = sheep:FindFirstChild("HumanoidRootPart")
	local hud = root and root:FindFirstChild("SheepHUD")
	if hud and hud:IsA("BillboardGui") then
		hud.Enabled = visible
	end
end

--// Pit ---------------------------------------------------------------------------------

-- Each emitter either bursts EmitCount at EmitDelay, or runs from LoopStart to LoopEnd.
local function scheduleParticles(effect: Model)
	for _, descendant in effect:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local count = descendant:GetAttribute("EmitCount")
		if type(count) == "number" then
			task.delay(getNumber(descendant, "EmitDelay", 0), function()
				if descendant.Parent then
					descendant:Emit(count)
				end
			end)
		end

		local loopStart, loopEnd = descendant:GetAttribute("LoopStart"), descendant:GetAttribute("LoopEnd")
		if type(loopStart) == "number" and type(loopEnd) == "number" then
			task.delay(loopStart, function()
				descendant.Enabled = true
			end)
			task.delay(loopEnd, function()
				descendant.Enabled = false
			end)
		end
	end
end

-- Tweens the pit discs between closed (keeping their thin X) and their FullSize times `scale`.
local function tweenPit(effect: Model, scale: number, open: boolean, info: TweenInfo)
	for _, name in PIT_PARTS do
		local part = effect:FindFirstChild(name, true)
		local fullSize = part and part:GetAttribute("FullSize")
		if not part or not part:IsA("BasePart") or typeof(fullSize) ~= "Vector3" then
			continue
		end

		local full = fullSize * scale -- ScaleTo grows the parts but not their FullSize attribute
		local closed = Vector3.new(full.X, CLOSED_DIAMETER, CLOSED_DIAMETER)
		if open then
			part.Size = closed
		end
		tweenService:Create(part, info, { Size = if open then full else closed }):Play()
	end
end

-- The sheep starts its own height under the floor and climbs to `emerged`, wobbling less as it comes out.
local function raiseSheep(sheep: Model, emerged: CFrame, openSeconds: number, riseSeconds: number)
	local _, boxSize = sheep:GetBoundingBox()
	local depth = boxSize.Y
	setHudVisible(sheep, false)
	sheep:PivotTo(emerged - Vector3.new(0, depth, 0)) -- the server already holds it here, anchored

	task.wait(openSeconds)
	local startedAt = os.clock()
	local connection: RBXScriptConnection
	connection = runService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		local alpha = math.min(elapsed / math.max(riseSeconds, 0.01), 1)

		-- The server clears Rising (and puts it at `emerged`) once it is out; stop fighting it then.
		if alpha >= 1 or not sheep.Parent or sheep:GetAttribute("Rising") ~= true then
			connection:Disconnect()
			if sheep.Parent then
				if sheep:GetAttribute("Rising") == true then
					sheep:PivotTo(emerged)
				end
				setHudVisible(sheep, true)
			end
			return
		end

		local eased = tweenService:GetValue(alpha, RISE_EASING, Enum.EasingDirection.Out)
		local wobble = math.rad(WOBBLE_DEGREES) * math.sin(elapsed * WOBBLE_SPEED) * (1 - eased)
		sheep:PivotTo((emerged - Vector3.new(0, depth * (1 - eased), 0)) * CFrame.Angles(0, 0, wobble))
	end)
end

--[[
	0: the pit opens. OpenSeconds: the sheep starts rising. OpenSeconds + RiseSeconds: it is out, the glow flashes
	and the pit closes. Duration: the effect is gone.
]]
local function playSpawn(spawnInfo: SpawnInfo)
	if type(spawnInfo) ~= "table" or typeof(spawnInfo.floor) ~= "CFrame" or typeof(spawnInfo.emerged) ~= "CFrame" then
		return
	end
	local scale = if type(spawnInfo.scale) == "number" then spawnInfo.scale else 1
	local openSeconds = spawnInfo.openSeconds
	local riseSeconds = spawnInfo.riseSeconds
	local sheep = spawnInfo.sheep

	if typeof(sheep) == "Instance" and sheep:IsA("Model") then
		task.spawn(raiseSheep, sheep, spawnInfo.emerged, openSeconds, riseSeconds)
	end

	if not spawnTemplate then
		return
	end
	local effect = spawnTemplate:Clone() :: Model
	effect:ScaleTo(effect:GetScale() * scale)
	effect:PivotTo(spawnInfo.floor)

	tweenPit(effect, scale, true, TweenInfo.new(openSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	effect.Parent = workspace
	scheduleParticles(effect)

	task.delay(openSeconds + riseSeconds, function()
		if not effect.Parent then
			return
		end
		local root = effect.PrimaryPart
		local burst = root and root:FindFirstChild("Burst")
		local glow = burst and burst:FindFirstChild("Glow")
		if glow and glow:IsA("PointLight") then
			tweenService:Create(glow, GLOW_FLASH, { Brightness = getNumber(effect, "LightBrightness", 4) }):Play()
		end
		local closeSeconds = getNumber(effect, "CloseSeconds", 0.5)
		tweenPit(effect, scale, false, TweenInfo.new(closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	end)

	task.delay(getNumber(effect, "Duration", 3.05), function()
		effect:Destroy()
	end)
end

--// Setup -------------------------------------------------------------------------------

network.waitUntilReadyAsync()
network.connectEvent(network.RemoteEvents.HalloweenSheepSpawn, playSpawn)
