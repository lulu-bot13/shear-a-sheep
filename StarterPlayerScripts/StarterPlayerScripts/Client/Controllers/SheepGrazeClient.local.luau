--!strict

--[[
	Grazing animation: while a sheep's "Grazing" attribute is true (set by the server's SheepWanderHandler),
	it dips its body, lowers its head to the grass and nibbles, wagging its tail. When the attribute clears
	(time to walk, or a player starts shearing) the head comes back up.

	Why procedural instead of a published Animation: the sheep come on two rig layouts (older species have
	their joints turned 90 degrees; newer ones have upright joints plus separate Wool / Face / Spikes parts),
	so one keyframed animation would bend them in different directions. Here every pose is worked out from
	the sheep's own joints and part sizes, so each species puts its mouth right on the ground, and new
	species work with no extra setup. Motor6D.Transform is local to this client, so it costs no network.

	Runs in PreSimulation (after the Animator), layered on top of whatever the walk animation is doing.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SheepGrazeClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

--// Configs
local SHEEP_TAG = "Sheep"
local GRAZING_ATTRIBUTE = "Grazing"
local MAX_DISTANCE = 160 -- studs from the camera; further sheep hold their pose instead of updating
local BEND_DOWN_SECONDS = 0.7
local BEND_UP_SECONDS = 0.45

local HEAD_PITCH = math.rad(55) -- nose-down tilt of the head
local HEAD_FORWARD = 0.35 -- the head reaches forward by this fraction of its length
local GROUND_GAP = 0.08 -- studs kept between the lowest point of the head and the hooves
local BODY_PITCH = math.rad(7) -- the front of the body dips this much, pivoting at the rump

local CHEW_PITCH = math.rad(7) -- each nibble lifts the nose this much
local CHEW_SPEED = 10 -- radians/s of the nibble wave
local CHEW_PAUSE_SPEED = 1.1 -- radians/s of the slower wave that breaks nibbling into bursts
local TAIL_WAG = math.rad(16)
local TAIL_SPEED = 6

-- Parts are grouped by name; anything not listed (legs) stays put.
local HEAD_PARTS = { Head = true, Face = true }
local BODY_PARTS = { Torso = true, Wool = true, Spikes = true }
local TAIL_PARTS = { Tail = true, Sphere = true }
local LEG_PARTS = { ["Front-Left"] = true, ["Front-Right"] = true, ["Back-Left"] = true, ["Back-Right"] = true }

--// Types
type Joint = {
	motor: Motor6D,
	group: "head" | "body" | "tail",
	frame: CFrame, -- the joint's rest frame (Part0 * C0) in root space
	frameInverse: CFrame,
	written: CFrame?, -- last Transform this script set, to tell it apart from the Animator's
}

type Rig = {
	root: BasePart,
	joints: { Joint },
	headCenter: Vector3,
	headDrop: Vector3, -- extra move that puts the tilted head's lowest point on the grass
	bodyPivot: Vector3,
	tailPivot: Vector3,
}

type State = {
	alpha: number, -- 0 standing, 1 head fully down
	phase: number, -- random offset so a flock doesn't nibble in sync
	rig: Rig?,
	noRig: boolean?, -- couldn't build one; don't keep trying
}

--// State
local states: { [Model]: State } = {}
local random = Random.new()

--// Rig building --------------------------------------------------------------------------

local function rotateAbout(pivot: Vector3, rotation: CFrame): CFrame
	return CFrame.new(pivot) * rotation * CFrame.new(-pivot)
end

local function getCorners(cframe: CFrame, size: Vector3): { Vector3 }
	local half = size / 2
	local corners = {}
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(corners, cframe:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z)))
			end
		end
	end
	return corners
end

-- Root-space box of a part at rest: min and max corners.
local function getBounds(cframe: CFrame, size: Vector3): (Vector3, Vector3)
	local low = Vector3.one * math.huge
	local high = -low
	for _, corner in getCorners(cframe, size) do
		low = low:Min(corner)
		high = high:Max(corner)
	end
	return low, high
end

-- Where a part sits relative to the root in the rest pose, following Motor6Ds (either direction) from the root.
local function getRestOffset(part: BasePart, root: BasePart, motors: { Motor6D }, depth: number?): CFrame?
	if part == root then
		return CFrame.identity
	end
	local level = depth or 0
	if level > 6 then
		return nil
	end
	for _, motor in motors do
		if motor.Part1 == part and motor.Part0 then
			local parentOffset = getRestOffset(motor.Part0, root, motors, level + 1)
			if parentOffset then
				return parentOffset * motor.C0 * motor.C1:Inverse()
			end
		elseif motor.Part0 == part and motor.Part1 == root then
			return (motor.C0 * motor.C1:Inverse()):Inverse()
		end
	end
	return nil
end

local function buildRig(sheep: Model): Rig?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end

	local motors: { Motor6D } = {}
	for _, descendant in sheep:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			table.insert(motors, descendant)
		end
	end

	local joints: { Joint } = {}
	local head: BasePart? = nil
	local headRest: CFrame? = nil
	local groundY: number? = nil
	local bodyLow: Vector3?, bodyHigh: Vector3? = nil, nil
	local tailRest: CFrame?, tailSize: Vector3? = nil, nil

	for _, motor in motors do
		local part1 = motor.Part1 :: BasePart
		local part0Offset = getRestOffset(motor.Part0 :: BasePart, root, motors)
		if not part0Offset or part1 == root then
			continue
		end

		local frame = part0Offset * motor.C0
		local rest = frame * motor.C1:Inverse()
		local name = part1.Name

		local group: ("head" | "body" | "tail")? = if HEAD_PARTS[name] then "head"
			elseif BODY_PARTS[name] then "body"
			elseif TAIL_PARTS[name] then "tail"
			else nil

		if group then
			table.insert(joints, { motor = motor, group = group, frame = frame, frameInverse = frame:Inverse() })
		end

		if name == "Head" then
			head = part1
			headRest = rest
		elseif name == "Torso" then
			bodyLow, bodyHigh = getBounds(rest, part1.Size)
		elseif group == "tail" then
			tailRest, tailSize = rest, part1.Size
		elseif LEG_PARTS[name] then
			local low = getBounds(rest, part1.Size)
			groundY = math.min(groundY or math.huge, low.Y)
		end
	end

	if not head or not headRest or #joints == 0 then
		return nil
	end

	-- No legs found: fall back to where the Humanoid stands.
	if not groundY then
		local humanoid = sheep:FindFirstChildOfClass("Humanoid")
		groundY = -root.Size.Y / 2 - (if humanoid then humanoid.HipHeight else 2)
	end

	-- Tilt the head about its centre, then move it so its lowest point (even mid-nibble) just meets the grass.
	local headCenter = headRest.Position
	local headSize = (head :: BasePart).Size
	local headCorners = getCorners(headRest, headSize)
	local function lowestAt(pitch: number): number
		local tilt = rotateAbout(headCenter, CFrame.Angles(-pitch, 0, 0))
		local lowest = math.huge
		for _, corner in headCorners do
			lowest = math.min(lowest, tilt:PointToWorldSpace(corner).Y)
		end
		return lowest
	end
	local lowest = math.min(lowestAt(HEAD_PITCH), lowestAt(HEAD_PITCH - CHEW_PITCH))
	local headLow, headHigh = getBounds(headRest, headSize)
	local headLength = headHigh.Z - headLow.Z
	local headDrop = Vector3.new(0, (groundY :: number) + GROUND_GAP - lowest, -headLength * HEAD_FORWARD)

	-- The body tips forward around its rump (sheep face -Z, so the rump is the box's +Z end).
	local bodyPivot = if bodyLow and bodyHigh
		then Vector3.new((bodyLow.X + bodyHigh.X) / 2, (bodyLow.Y + bodyHigh.Y) / 2, bodyHigh.Z)
		else Vector3.new(0, 0, root.Size.Z / 2)

	local tailPivot = if tailRest and tailSize
		then tailRest.Position + Vector3.new(0, tailSize.Y * 0.35, 0)
		else bodyPivot

	return {
		root = root,
		joints = joints,
		headCenter = headCenter,
		headDrop = headDrop,
		bodyPivot = bodyPivot,
		tailPivot = tailPivot,
	}
end

--// Posing ------------------------------------------------------------------------------

-- Transform values can come back from the engine very slightly rounded, so compare with a tolerance.
local function isSame(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3
		and a.LookVector:Dot(b.LookVector) > 0.99999
		and a.UpVector:Dot(b.UpVector) > 0.99999
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

-- Puts every graze-driven joint back to rest (or back to whatever the Animator set this frame).
local function releaseRig(rig: Rig)
	for _, joint in rig.joints do
		if joint.written and isSame(joint.motor.Transform, joint.written) then
			joint.motor.Transform = CFrame.identity
		end
		joint.written = nil
	end
end

local function poseRig(rig: Rig, amount: number, clock: number)
	-- Nibbling: quick nods that come in bursts, only ever lifting the nose so it never sinks into the ground.
	local burst = 0.35 + 0.65 * math.max(0, math.sin(clock * CHEW_PAUSE_SPEED))
	local chew = CHEW_PITCH * (0.5 + 0.5 * math.sin(clock * CHEW_SPEED)) * burst * amount

	local headMove = CFrame.new(rig.headDrop * amount)
		* rotateAbout(rig.headCenter, CFrame.Angles(-(HEAD_PITCH * amount - chew), 0, 0))
	local bodyMove = rotateAbout(rig.bodyPivot, CFrame.Angles(-BODY_PITCH * amount, 0, 0))
	local tailMove = bodyMove
		* rotateAbout(rig.tailPivot, CFrame.Angles(0, TAIL_WAG * math.sin(clock * TAIL_SPEED) * amount, 0))

	for _, joint in rig.joints do
		local move = if joint.group == "head" then headMove elseif joint.group == "body" then bodyMove else tailMove

		-- If the Animator wrote this joint this frame (walk fading in), layer on top of it; otherwise start from rest.
		local current = joint.motor.Transform
		local base = if joint.written and isSame(current, joint.written) then CFrame.identity else current

		-- A root-space move, expressed in the joint's own frame.
		local transform = joint.frameInverse * move * joint.frame * base
		joint.motor.Transform = transform
		joint.written = transform
	end
end

--// Tracking sheep ------------------------------------------------------------------------

local function onSheepAdded(instance: Instance)
	if instance:IsA("Model") and not states[instance] then
		states[instance] = { alpha = 0, phase = random:NextNumber(0, 100) }
	end
end

local function onSheepRemoved(instance: Instance)
	local state = states[instance :: Model]
	if state and state.rig then
		releaseRig(state.rig)
	end
	states[instance :: Model] = nil
end

for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
	onSheepAdded(sheep)
end
collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(onSheepRemoved)

runService.PreSimulation:Connect(function(deltaTime: number)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local clock = os.clock()

	for sheep, state in states do
		local wantsDown = sheep:GetAttribute(GRAZING_ATTRIBUTE) == true
		if state.alpha == 0 and not wantsDown then
			continue
		end

		if wantsDown then
			state.alpha = math.min(1, state.alpha + deltaTime / BEND_DOWN_SECONDS)
		else
			state.alpha = math.max(0, state.alpha - deltaTime / BEND_UP_SECONDS)
		end

		if not state.rig and not state.noRig then
			state.rig = buildRig(sheep)
			state.noRig = state.rig == nil
		end
		local rig = state.rig
		if not rig then
			continue
		end

		if state.alpha == 0 then
			releaseRig(rig)
		elseif (rig.root.Position - cameraPosition).Magnitude <= MAX_DISTANCE then
			poseRig(rig, smooth(state.alpha), clock + state.phase)
		end
	end
end)
