--!strict

--[[
	Clone: copies of the player, each holding their shear, run to the nearest unclaimed sheep on their plot and shear it.
	Location: ServerScriptService.Modules.Abilities.Clone
]]--

--// Services
local physicsService = game:GetService("PhysicsService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local AbilityUtil = require(script.Parent.AbilityUtil)
local PlotHandler = require(script.Parent.Parent.Controllers.PlotHandler)
local ShearHandler = require(script.Parent.Parent.Controllers.ShearHandler)
local ShearShopHandler = require(script.Parent.Parent.Controllers.ShearShopHandler)
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)

--// Instances
local animations = replicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")

--// Configs
local ABILITY_ID = "Clone"
local CLONES_FOLDER_NAME = "AbilityClones"
local COLLISION_GROUP = "Clones"
local TRANSPARENCY = 0.4 -- every visible part of a clone is at least this see-through
local AREA_PADDING = 2 -- studs clones keep inside the SheepArea's edge
local STOP_FRACTION = 0.6 -- of the shear range: a clone stops walking this close to its sheep
local FOLLOW_DISTANCE = 6 -- studs an idle clone (no sheep left) keeps from the player
local MOVING_SPEED = 0.5 -- studs/s above which the clone plays its run animation
local GROUND_RAY_HEIGHT = 30
local SWING_ANIMATION = "ShearRig" -- the player's swing in Assets.Animations
local TOOL_SWING_ANIMATION = "ShearTool" -- the shear's own snip, played on its AnimationController
local STRIP_CLASSES = { "BaseScript", "Tool", "ForceField", "BillboardGui", "SurfaceGui", "Sound", "ProximityPrompt", "Highlight" }

type CloneUnit = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	target: Model?,
	runTrack: AnimationTrack?,
	idleTrack: AnimationTrack?,
	swingTrack: AnimationTrack?,
	toolTrack: AnimationTrack?,
	connection: RBXScriptConnection?,
}

local Clone = {}

-- Clones walk through players, sheep and each other; the groups may not exist yet if this loads before PlayerSetup.
for _, group in { COLLISION_GROUP, "Players", "Sheep" } do
	if not physicsService:IsCollisionGroupRegistered(group) then
		physicsService:RegisterCollisionGroup(group)
	end
	physicsService:CollisionGroupSetCollidable(COLLISION_GROUP, group, false)
end
physicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)

--// Helpers -------------------------------------------------------------------------

local function getClonesFolder(): Folder
	local existing = workspace:FindFirstChild(CLONES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = CLONES_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function shouldStrip(instance: Instance): boolean
	for _, className in STRIP_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local function getAnimation(parent: Instance?, name: string): Animation?
	local found = parent and parent:FindFirstChild(name)
	if found and found:IsA("Animation") then
		return found
	end
	return found and found:FindFirstChildWhichIsA("Animation", true)
end

-- The run (else walk) and idle animations from the character's Animate script, so clones move like the player.
local function getMoveAnimations(character: Model): (Animation?, Animation?)
	local animate = character:FindFirstChild("Animate")
	if not animate then
		return nil, nil
	end
	local run = getAnimation(animate:FindFirstChild("run"), "RunAnim") or getAnimation(animate:FindFirstChild("walk"), "WalkAnim")
	local idle = getAnimation(animate:FindFirstChild("idle"), "Animation1")
	return run, idle
end

-- The SheepArea's box on the player's plot, or nil if they have none.
local function getArea(player: Player): (CFrame?, Vector3?)
	local plot = PlotHandler.getPlayerPlot(player)
	local area = plot and plot:FindFirstChild(FarmData.SheepAreaName)
	if area and area:IsA("BasePart") then
		return area.CFrame, area.Size
	elseif area and area:IsA("Model") then
		return area:GetBoundingBox()
	end
	return nil, nil
end

local function clampToArea(point: Vector3, boxCFrame: CFrame?, size: Vector3?): Vector3
	if not boxCFrame or not size then
		return point
	end
	local localPoint = boxCFrame:PointToObjectSpace(point)
	local halfX = math.max(size.X / 2 - AREA_PADDING, 0)
	local halfZ = math.max(size.Z / 2 - AREA_PADDING, 0)
	local clamped = Vector3.new(math.clamp(localPoint.X, -halfX, halfX), localPoint.Y, math.clamp(localPoint.Z, -halfZ, halfZ))
	return boxCFrame:PointToWorldSpace(clamped)
end

local function findGround(point: Vector3, params: RaycastParams): Vector3?
	local result = workspace:Raycast(point + Vector3.new(0, GROUND_RAY_HEIGHT, 0), Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), params)
	return if result then result.Position else nil
end

-- Studs from the ground up to the root's centre for this rig.
local function getStandHeight(humanoid: Humanoid, root: BasePart): number
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	return legs + root.Size.Y / 2
end

--// Building ------------------------------------------------------------------------

-- A script-free, see-through copy of the character with no tools or gui, ready to be cloned again.
local function buildTemplate(character: Model): Model?
	local wasArchivable = character.Archivable
	character.Archivable = true
	local template = character:Clone()
	character.Archivable = wasArchivable
	if not template then
		return nil
	end

	for _, descendant in template:GetDescendants() do
		if shouldStrip(descendant) then
			descendant:Destroy()
		end
	end
	for _, descendant in template:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CollisionGroup = COLLISION_GROUP
			descendant.CanTouch = false
			descendant.CanQuery = false -- mouse aim and ground rays pass through clones
			if descendant.Transparency < 1 then
				descendant.Transparency = math.max(descendant.Transparency, TRANSPARENCY)
			end
		elseif descendant:IsA("Decal") then
			descendant.Transparency = math.max(descendant.Transparency, TRANSPARENCY)
		end
	end
	return template
end

-- A show-only copy of the player's shear welded into the clone's right hand (under the hand, so it is never equipped).
local function attachShears(model: Model, tool: Tool?): Tool?
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if not tool or not hand or not hand:IsA("BasePart") then
		return nil
	end

	local copy = tool:Clone()
	local handle = copy:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		copy:Destroy()
		return nil
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CollisionGroup = COLLISION_GROUP
		end
	end

	local attachment = hand:FindFirstChild("RightGripAttachment")
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = if attachment and attachment:IsA("Attachment")
		then attachment.CFrame
		else CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	weld.C1 = copy.Grip
	weld.Parent = handle
	copy.Parent = hand
	return copy
end

local function loadTrack(animator: Animator?, animation: Animation?, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	if not animator or not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

local function spawnUnit(template: Model, cframe: CFrame, tool: Tool?, runAnim: Animation?, idleAnim: Animation?, walkSpeed: number): CloneUnit?
	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil
	end

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.BreakJointsOnDeath = false
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = walkSpeed
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	local shears = attachShears(model, tool)
	model:PivotTo(cframe)
	model.Parent = getClonesFolder()
	root:SetNetworkOwner(nil)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end
	local controller = shears and shears:FindFirstChild("AnimationController")
	local toolAnimator = controller and controller:FindFirstChildOfClass("Animator")

	local unit: CloneUnit = {
		model = model,
		humanoid = humanoid,
		root = root,
		target = nil,
		runTrack = loadTrack(animator, runAnim, Enum.AnimationPriority.Movement, true),
		idleTrack = loadTrack(animator, idleAnim, Enum.AnimationPriority.Idle, true),
		swingTrack = loadTrack(animator, getAnimation(animations, SWING_ANIMATION), Enum.AnimationPriority.Action, false),
		toolTrack = loadTrack(toolAnimator, getAnimation(animations, TOOL_SWING_ANIMATION), Enum.AnimationPriority.Action, false),
		connection = nil,
	}
	if unit.idleTrack then
		unit.idleTrack:Play()
	end
	unit.connection = humanoid.Running:Connect(function(speed: number)
		local runTrack = unit.runTrack
		if not runTrack then
			return
		end
		if speed > MOVING_SPEED and not runTrack.IsPlaying then
			runTrack:Play()
		elseif speed <= MOVING_SPEED and runTrack.IsPlaying then
			runTrack:Stop()
		end
	end)
	return unit
end

--// Behaviour -----------------------------------------------------------------------

local function isValidTarget(player: Player, sheep: Model?): boolean
	if not sheep or not sheep.Parent then
		return false
	end
	local id = sheep:GetAttribute("id")
	local health = sheep:GetAttribute("ShearHealth")
	return type(id) == "number"
		and SheepHandler.getSheep(id) == sheep
		and SheepHandler.getOwnerId(sheep) == player.UserId
		and type(health) == "number"
		and health > 0
end

local function getSheepPosition(sheep: Model): Vector3?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- The nearest of the player's sheep no other clone is after; any nearest one if every sheep is taken.
local function pickTarget(player: Player, position: Vector3, claimed: { [Model]: boolean }): Model?
	local best: Model?, bestDistance = nil, math.huge
	local shared: Model?, sharedDistance = nil, math.huge
	for _, sheep in SheepHandler.getAllSheep() do
		if not isValidTarget(player, sheep) then
			continue
		end
		local sheepPosition = getSheepPosition(sheep)
		if not sheepPosition then
			continue
		end

		local distance = (sheepPosition - position).Magnitude
		if not claimed[sheep] and distance < bestDistance then
			best, bestDistance = sheep, distance
		end
		if distance < sharedDistance then
			shared, sharedDistance = sheep, distance
		end
	end
	return best or shared
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function swing(player: Player, unit: CloneUnit, range: number, damage: number)
	local targets = ShearHandler.getSheepInRange(player, unit.root.Position, range)
	if #targets == 0 then
		return
	end
	if unit.swingTrack then
		unit.swingTrack:Play()
	end
	if unit.toolTrack then
		unit.toolTrack:Play()
	end
	ShearHandler.shearSheep(player, targets, damage)
end

local function updateUnit(player: Player, unit: CloneUnit, claimed: { [Model]: boolean }, range: number, damage: number, boxCFrame: CFrame?, size: Vector3?)
	local position = unit.root.Position
	if not isValidTarget(player, unit.target) then
		unit.target = pickTarget(player, position, claimed)
	end

	local target = unit.target
	local targetPosition = target and getSheepPosition(target)
	if target and targetPosition then
		claimed[target] = true
		local offset = flat(targetPosition - position)
		if offset.Magnitude > range * STOP_FRACTION then
			unit.humanoid:MoveTo(clampToArea(targetPosition, boxCFrame, size))
		else
			unit.humanoid:MoveTo(position)
			if offset.Magnitude > 0.1 then
				unit.root.CFrame = CFrame.lookAt(position, position + offset)
			end
		end
	else
		local playerRoot = AbilityUtil.getRoot(player)
		if playerRoot and flat(playerRoot.Position - position).Magnitude > FOLLOW_DISTANCE then
			unit.humanoid:MoveTo(clampToArea(playerRoot.Position, boxCFrame, size))
		end
	end

	swing(player, unit, range, damage)
end

local function despawn(player: Player, units: { CloneUnit })
	local positions: { Vector3 } = {}
	for _, unit in units do
		if unit.connection then
			unit.connection:Disconnect()
		end
		if unit.root.Parent then
			table.insert(positions, unit.root.Position)
		end
		unit.model:Destroy()
	end
	if #positions > 0 then
		network.fireAllClients(network.RemoteEvents.AbilityEffect, player, ABILITY_ID, "Despawn", positions)
	end
end

--// Ability -------------------------------------------------------------------------

local function spawnClones(player: Player, character: Model, stats: { [string]: number }, params: RaycastParams): { CloneUnit }
	local units: { CloneUnit } = {}
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = AbilityUtil.getRoot(player)
	if not humanoid or not root then
		return units
	end

	local template = buildTemplate(character)
	if not template then
		return units
	end

	local runAnim, idleAnim = getMoveAnimations(character)
	local tool = ShearShopHandler.getTool(player)
	local boxCFrame, size = getArea(player)
	local standHeight = getStandHeight(humanoid, root)
	local count = math.max(math.floor(stats.count), 0)
	local look = flat(root.CFrame.LookVector)
	local facing = if look.Magnitude > 0.01 then look.Unit else Vector3.zAxis

	for index = 1, count do
		local angle = (index - 0.5) / count * math.pi * 2
		local offset = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(facing) * stats.spawnRadius
		local point = clampToArea(root.Position + offset, boxCFrame, size)
		local ground = findGround(point, params)
		local position = if ground then ground + Vector3.new(0, standHeight, 0) else Vector3.new(point.X, root.Position.Y, point.Z)
		local unit = spawnUnit(template, CFrame.lookAt(position, position + facing), tool, runAnim, idleAnim, stats.walkSpeed)
		if unit then
			table.insert(units, unit)
		end
	end
	template:Destroy()
	return units
end

function Clone.run(player: Player, ability: AbilityData.AbilityInfo)
	local stats = ability.stats
	local character = player.Character
	if not character or not AbilityUtil.isStillActive(player, character) then
		return
	end

	-- The ground ray skips characters and other clones, and sheep through the Players group, which doesn't collide with them.
	local ignore: { Instance } = { getClonesFolder() }
	for _, other in players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.CollisionGroup = "Players"
	params.RespectCanCollide = true

	local units = spawnClones(player, character, stats, params)
	if #units == 0 then
		return
	end

	local spawnPositions: { Vector3 } = {}
	for _, unit in units do
		table.insert(spawnPositions, unit.root.Position)
	end
	network.fireAllClients(network.RemoteEvents.AbilityEffect, player, ABILITY_ID, "Spawn", spawnPositions)

	local success, err = pcall(function()
		local boxCFrame, size = getArea(player)
		local endsAt = os.clock() + ability.duration
		while os.clock() < endsAt and AbilityUtil.isStillActive(player, character) do
			local range = ShearShopHandler.getShear(player).range + ShearData.RangeTolerance
			local damage = ShearHandler.getShearDamage(player) * stats.damageMultiplier
			local claimed: { [Model]: boolean } = {}
			for _, unit in units do
				if unit.root.Parent and unit.model.Parent then
					updateUnit(player, unit, claimed, range, damage, boxCFrame, size)
				end
			end
			task.wait(stats.swingInterval)
		end
	end)

	despawn(player, units)
	if not success then
		error(err, 0)
	end
end

return Clone
