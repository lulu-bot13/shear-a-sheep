--!strict

--[[
	The King Sheep's royal cape.

	The cape is a chain of hinged velvet segments (Cape.Segment1..N, each with a FlapL / FlapR side flap) under a
	Model tagged "RoyalCape". While the sheep stands, a slow wave rolls down the cape; while it walks, the wave
	speeds up, the tail end streams up behind it and the side flaps flare out. As the wool is sheared the Torso
	shrinks, so the whole cape settles lower and the flaps hug in, and it never floats above a shorn sheep.

	Everything is worked out from the cape's own joints, so the model can be resized (Model:ScaleTo) freely.
	Motor6D.Transform is local to this client, so it costs no network. Runs in PreSimulation, like SheepGrazeClient.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.KingCapeClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)

--// Configs
local CAPE_TAG = "RoyalCape"
local ROOT_JOINT_NAME = "CapeRoot" -- joins the cape to the Torso
local MAX_DISTANCE = 200 -- studs from the camera; further capes hold their pose instead of updating
local RETRY_SECONDS = 1 -- a cape still streaming in is looked at again after this long

local IDLE_WAVE_SPEED = 2.2 -- radians/s of the wave while standing
local WALK_WAVE_SPEED = 7.5 -- ...and at full walking speed
local WAVE_LAG = 0.9 -- radians of phase between neighbouring segments, so the wave travels down the cape
local IDLE_SWAY = math.rad(5) -- pitch of the cape's tail end at the top of the wave
local WALK_SWAY = math.rad(10)
local WALK_LIFT = math.rad(-16) -- the tail end streams up behind a walking sheep
local FLAP_IDLE_SWAY = math.rad(4)
local FLAP_WALK_SWAY = math.rad(9)
local FLAP_WALK_FLARE = math.rad(10) -- side flaps lift outwards while walking
local FLAP_SHORN_HUG = math.rad(16) -- side flaps fold in against a fully shorn body
local WALK_FULL_SPEED = 6 -- studs/s that counts as walking at full pace
local WALK_BLEND_SPEED = 4 -- how fast the cape eases between standing and walking

--// Types
type Hinge = {
	motor: Motor6D,
	index: number, -- 1 at the neck, counting down the cape
	side: number, -- -1 left flap, 1 right flap, 0 a centre segment
}

type Rig = {
	root: BasePart,
	torso: BasePart,
	rootMotor: Motor6D,
	fullTorsoSize: Vector3,
	segments: { Hinge },
	flaps: { Hinge },
	count: number,
}

type State = {
	rig: Rig?,
	retryAt: number,
	walk: number, -- 0 standing, 1 walking at full pace
	wave: number,
	lastPosition: Vector3?,
}

--// State
local states: { [Model]: State } = {}
local random = Random.new()
local shornHeightLoss = 1 - WoolData.ShornTorsoScale.Y

--// Rig building --------------------------------------------------------------------------

local function buildRig(cape: Model): Rig?
	local sheep = cape.Parent
	local root = sheep and sheep:FindFirstChild("HumanoidRootPart")
	local torso = sheep and sheep:FindFirstChild("Torso")
	if not root or not root:IsA("BasePart") or not torso or not torso:IsA("BasePart") then
		return nil
	end

	local rootMotor: Motor6D? = nil
	local segments: { Hinge } = {}
	local flaps: { Hinge } = {}
	local count = 0
	for _, descendant in cape:GetDescendants() do
		if not descendant:IsA("Motor6D") then
			continue
		end
		if not descendant.Part0 or not descendant.Part1 then
			return nil -- still streaming in
		end

		if descendant.Name == ROOT_JOINT_NAME then
			rootMotor = descendant
			continue
		end

		local index = descendant:GetAttribute("Index")
		local side = descendant:GetAttribute("Side")
		if type(index) ~= "number" then
			continue
		end
		if type(side) == "number" then
			table.insert(flaps, { motor = descendant, index = index, side = side })
		else
			table.insert(segments, { motor = descendant, index = index, side = 0 })
			count = math.max(count, index)
		end
	end

	if not rootMotor or count == 0 then
		return nil
	end

	-- The wool's untouched size: the server records it on the Torso the first time it shears this model.
	local recorded = torso:GetAttribute("WoolBaseSize")
	return {
		root = root,
		torso = torso,
		rootMotor = rootMotor :: Motor6D,
		fullTorsoSize = if typeof(recorded) == "Vector3" then recorded else torso.Size,
		segments = segments,
		flaps = flaps,
		count = count,
	}
end

local function releaseRig(rig: Rig)
	rig.rootMotor.Transform = CFrame.identity
	for _, hinge in rig.segments do
		hinge.motor.Transform = CFrame.identity
	end
	for _, hinge in rig.flaps do
		hinge.motor.Transform = CFrame.identity
	end
end

--// Posing ------------------------------------------------------------------------------

local function poseRig(rig: Rig, state: State, deltaTime: number)
	-- How much it's walking, from how far it moved (works whether physics or a script moves it).
	local position = rig.root.Position
	local speed = 0
	if state.lastPosition and deltaTime > 0 then
		local moved = position - state.lastPosition
		speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / deltaTime
	end
	state.lastPosition = position

	local targetWalk = math.clamp(speed / WALK_FULL_SPEED, 0, 1)
	state.walk += (targetWalk - state.walk) * math.min(1, deltaTime * WALK_BLEND_SPEED)
	local walk = state.walk
	state.wave += deltaTime * (IDLE_WAVE_SPEED + (WALK_WAVE_SPEED - IDLE_WAVE_SPEED) * walk)
	local wave = state.wave

	-- Shearing shrinks the Torso: slide the cape's anchor in by the same amount so it stays on the wool.
	local torsoScale = rig.torso.Size / rig.fullTorsoSize
	local shorn = math.clamp((1 - torsoScale.Y) / shornHeightLoss, 0, 1)
	local anchor = rig.rootMotor.C0
	local shift = anchor.Position * torsoScale - anchor.Position
	rig.rootMotor.Transform = CFrame.new(anchor.Rotation:VectorToObjectSpace(shift))

	-- Each joint bends a little, more towards the tail end, so the bends add up into a rolling wave.
	local sway = IDLE_SWAY + (WALK_SWAY - IDLE_SWAY) * walk
	for _, hinge in rig.segments do
		local reach = hinge.index / rig.count
		local pitch = reach * (sway * math.sin(wave - hinge.index * WAVE_LAG) + WALK_LIFT * walk)
		hinge.motor.Transform = CFrame.Angles(pitch, 0, 0)
	end

	local flapSway = FLAP_IDLE_SWAY + (FLAP_WALK_SWAY - FLAP_IDLE_SWAY) * walk
	for _, hinge in rig.flaps do
		local flutter = flapSway * math.sin(wave * 1.3 - hinge.index * WAVE_LAG + hinge.side)
		local outward = flutter + FLAP_WALK_FLARE * walk - FLAP_SHORN_HUG * shorn
		hinge.motor.Transform = CFrame.Angles(0, 0, hinge.side * outward) -- +side lifts the flap away from the body
	end
end

--// Tracking capes ------------------------------------------------------------------------

local function onCapeAdded(instance: Instance)
	if instance:IsA("Model") and not states[instance] then
		states[instance] = { retryAt = 0, walk = 0, wave = random:NextNumber(0, 100) }
	end
end

local function onCapeRemoved(instance: Instance)
	local state = states[instance :: Model]
	if state and state.rig then
		releaseRig(state.rig)
	end
	states[instance :: Model] = nil
end

for _, cape in collectionService:GetTagged(CAPE_TAG) do
	onCapeAdded(cape)
end
collectionService:GetInstanceAddedSignal(CAPE_TAG):Connect(onCapeAdded)
collectionService:GetInstanceRemovedSignal(CAPE_TAG):Connect(onCapeRemoved)

runService.PreSimulation:Connect(function(deltaTime: number)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()

	for cape, state in states do
		-- Templates (e.g. in ReplicatedStorage) are tagged too; only capes in the world move.
		if not cape:IsDescendantOf(workspace) then
			continue
		end

		if not state.rig then
			if now < state.retryAt then
				continue
			end
			state.rig = buildRig(cape)
			if not state.rig then
				state.retryAt = now + RETRY_SECONDS
				continue
			end
		end

		local rig = state.rig :: Rig
		if not rig.root:IsDescendantOf(workspace) then
			state.rig = nil -- the sheep was rebuilt or streamed out; find its joints again
			continue
		end

		if (rig.root.Position - cameraPosition).Magnitude <= MAX_DISTANCE then
			poseRig(rig, state, deltaTime)
		else
			state.lastPosition = nil
		end
	end
end)
