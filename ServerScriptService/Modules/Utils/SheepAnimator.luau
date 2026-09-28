--!strict

--[[
	Procedural walk-cycle animator for sheep rigs. Rather than depending on a
	published Animation asset id (which would only work for the one place
	file it was authored in / registered to during this Studio session),
	this drives each leg Motor6D directly with a sine-wave gait plus a small
	head bob and tail wag while the sheep is walking, and eases every joint
	back to its authored rest pose when it stops or gets seated for
	shearing. This keeps the animation working identically in Studio, in a
	playtest, and in the published/live game.

	One shared Heartbeat connection drives every registered sheep, so adding
	more sheep never adds more connections.

	Location: ServerScriptService.Modules.Utils.SheepAnimator
]]--

local runService = game:GetService("RunService")

--// Configuration
local GAIT_CYCLES_PER_SECOND = 1.6
local STEP_ANGLE = math.rad(28)
local HEAD_BOB_ANGLE = math.rad(6)
local TAIL_WAG_ANGLE = math.rad(10)
local BLEND_SPEED = 8 -- rate (per second) the pose eases toward its current target

type Rig = {
	root: BasePart,
	rest: { [string]: CFrame },
	motors: { [string]: Motor6D },
	phase: number,
	walking: boolean,
}

local rigs: { [Model]: Rig } = {}

local SheepAnimator = {}

--[[
	Registers a sheep model for animation, capturing its currently-authored
	Motor6D offsets as the rest pose to animate around and blend back to.
	Safe to call more than once for the same model (a no-op after the first).
]]--
function SheepAnimator.register(model: Model)
	if rigs[model] then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local rest: { [string]: CFrame } = {}
	local motors: { [string]: Motor6D } = {}
	for _, child in root:GetChildren() do
		if child:IsA("Motor6D") then
			rest[child.Name] = child.C0
			motors[child.Name] = child
		end
	end

	if next(motors) == nil then
		return -- nothing to animate (no rig)
	end

	rigs[model] = {
		root = root,
		rest = rest,
		motors = motors,
		phase = math.random() * math.pi * 2,
		walking = false,
	}
end

-- Stops animating a sheep. Call this before destroying/pooling its model.
function SheepAnimator.unregister(model: Model)
	rigs[model] = nil
end

--[[
	Instantly snaps every joint back to its captured rest pose (no blending).
	Call this before unregistering a sheep that's about to be pooled for
	reuse, so the NEXT registration captures the same correct authored pose
	as its rest -- otherwise a sheep unregistered mid-stride would have its
	slightly-off current pose baked in as the new "rest", drifting a little
	further every time that instance gets reused.
]]--
function SheepAnimator.snapToRest(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end

	for name, motor in rig.motors do
		local restC0 = rig.rest[name]
		if restC0 then
			motor.C0 = restC0
		end
	end
end

-- Switches a registered sheep between its walk cycle and its (blended-to) rest pose.
function SheepAnimator.setWalking(model: Model, walking: boolean)
	local rig = rigs[model]
	if rig then
		rig.walking = walking
	end
end

function SheepAnimator.isRegistered(model: Model): boolean
	return rigs[model] ~= nil
end

local function blendToward(motor: Motor6D, restC0: CFrame, localOffset: CFrame, alpha: number)
	local goal = restC0 * localOffset
	motor.C0 = motor.C0:Lerp(goal, alpha)
end

local function step(dt: number)
	for model, rig in rigs do
		if not model.Parent or not rig.root.Parent then
			rigs[model] = nil
			continue
		end

		local alpha = math.clamp(BLEND_SPEED * dt, 0, 1)

		if rig.walking then
			rig.phase += dt * GAIT_CYCLES_PER_SECOND * math.pi * 2
			local swing = math.sin(rig.phase)
			local swingOpposite = -swing

			local restFrontLeft = rig.rest["Front-Left"]
			if rig.motors["Front-Left"] and restFrontLeft then
				blendToward(rig.motors["Front-Left"], restFrontLeft, CFrame.Angles(swing * STEP_ANGLE, 0, 0), alpha)
			end

			local restBackRight = rig.rest["Back-Right"]
			if rig.motors["Back-Right"] and restBackRight then
				blendToward(rig.motors["Back-Right"], restBackRight, CFrame.Angles(swing * STEP_ANGLE, 0, 0), alpha)
			end

			local restFrontRight = rig.rest["Front-Right"]
			if rig.motors["Front-Right"] and restFrontRight then
				blendToward(rig.motors["Front-Right"], restFrontRight, CFrame.Angles(swingOpposite * STEP_ANGLE, 0, 0), alpha)
			end

			local restBackLeft = rig.rest["Back-Left"]
			if rig.motors["Back-Left"] and restBackLeft then
				blendToward(rig.motors["Back-Left"], restBackLeft, CFrame.Angles(swingOpposite * STEP_ANGLE, 0, 0), alpha)
			end

			local restHead = rig.rest["Head"]
			if rig.motors["Head"] and restHead then
				blendToward(rig.motors["Head"], restHead, CFrame.Angles(math.sin(rig.phase * 0.5) * HEAD_BOB_ANGLE, 0, 0), alpha)
			end

			local restTail = rig.rest["Tail"]
			if rig.motors["Tail"] and restTail then
				blendToward(rig.motors["Tail"], restTail, CFrame.Angles(0, math.sin(rig.phase) * TAIL_WAG_ANGLE, 0), alpha)
			end
		else
			for name, motor in rig.motors do
				local restC0 = rig.rest[name]
				if restC0 then
					motor.C0 = motor.C0:Lerp(restC0, alpha)
				end
			end
		end
	end
end

runService.Heartbeat:Connect(step)

return SheepAnimator
