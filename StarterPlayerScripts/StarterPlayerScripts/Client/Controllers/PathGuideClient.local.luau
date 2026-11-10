--!strict

--[[
	When the character spawns far from its plot, draws a TutorialBeam trail along Base.Paths (MainAvenue, then the plot's branch)
	to the plot's SpawnArea, and removes it once the player arrives. Client only; the beams live in Terrain.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PathGuideClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Configs
local WAIT_SECONDS = 10
local FAR_DISTANCE = 40 -- studs from the plot's SpawnArea a fresh character must be for the trail to show
local ARRIVE_DISTANCE = 12 -- the trail goes away this close to the SpawnArea
local SPAWN_SETTLE_SECONDS = 1.5 -- lets the server's join teleport land before measuring
local GUIDE_TIMEOUT = 120 -- seconds before an unfollowed trail gives up
local GROUND_LIFT = 0.3 -- studs above the path surface
local FEET_DEPTH = 2.8 -- studs from an R15/R6 root down to just above the floor
local MERGE_DISTANCE = 1 -- waypoints closer than this are merged
local MAX_SEGMENTS = 6
local BEAM_ROTATION = CFrame.fromOrientation(0, 0, math.rad(90)) -- lays the beam flat, as in TutorialClient
local FALLBACK_COLOR = Color3.fromRGB(255, 220, 90)

--// Instances
local player = players.LocalPlayer
local base = workspace:WaitForChild("Base", WAIT_SECONDS)
local paths = base and base:WaitForChild("Paths", WAIT_SECONDS)
local plotsFolder = base and base:WaitForChild("Plots", WAIT_SECONDS)
local assets = replicatedStorage:WaitForChild("Assets", WAIT_SECONDS)
local vfx = assets and assets:WaitForChild("VFX", WAIT_SECONDS)
local beamTemplate = vfx and vfx:WaitForChild("TutorialBeam", WAIT_SECONDS)
if not paths or not plotsFolder then
	warn("PathGuideClient: workspace.Base.Paths or Base.Plots is missing; build them in Studio. The trail is off.")
end
if not beamTemplate or not beamTemplate:IsA("Beam") then
	warn("PathGuideClient: ReplicatedStorage.Assets.VFX.TutorialBeam is missing, so the trail uses a plain beam.")
	beamTemplate = nil
end

--// State
type Segment = { beam: Beam, from: Attachment, to: Attachment }
local segments: { Segment } = {}
local renderConnection: RBXScriptConnection? = nil
local guideEndsAt = 0
local guideToken = 0

--// Beams --------------------------------------------------------------------------------

local function createSegment(index: number): Segment
	local from = Instance.new("Attachment")
	from.Name = `PathGuideStart{index}`
	from.Parent = workspace.Terrain
	local to = Instance.new("Attachment")
	to.Name = `PathGuideEnd{index}`
	to.Parent = workspace.Terrain

	local beam: Beam
	if beamTemplate then
		beam = (beamTemplate :: Beam):Clone()
	else
		beam = Instance.new("Beam")
		beam.Color = ColorSequence.new(FALLBACK_COLOR)
		beam.Width0, beam.Width1 = 3, 3
		beam.LightEmission = 1
		beam.TextureSpeed = 1
	end
	beam.Name = `PathGuide{index}`
	beam.FaceCamera = false -- the ends' rotation lays it flat
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Enabled = false
	beam.Parent = workspace.Terrain
	return { beam = beam, from = from, to = to }
end

for index = 1, MAX_SEGMENTS do
	segments[index] = createSegment(index)
end

local function hideTrail()
	for _, segment in segments do
		segment.beam.Enabled = false
	end
end

local function drawTrail(points: { Vector3 })
	for index, segment in segments do
		local start, finish = points[index], points[index + 1]
		if not start or not finish then
			segment.beam.Enabled = false
			continue
		end
		local flat = Vector3.new(finish.X - start.X, 0, finish.Z - start.Z)
		local heading = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
		segment.from.WorldCFrame = CFrame.lookAt(start, start - heading) * BEAM_ROTATION
		segment.to.WorldCFrame = CFrame.lookAt(finish, finish - heading) * BEAM_ROTATION
		segment.beam.Enabled = true
	end
end

--// Route --------------------------------------------------------------------------------

-- The two ends of a path part's long horizontal axis, on its top surface.
local function getCenterLine(part: BasePart): (Vector3, Vector3)
	local cframe, size = part.CFrame, part.Size
	local axis = if size.X >= size.Z then cframe.RightVector * (size.X / 2) else cframe.LookVector * (size.Z / 2)
	local top = cframe.UpVector * (size.Y / 2 + GROUND_LIFT)
	return cframe.Position - axis + top, cframe.Position + axis + top
end

local function closestOnSegment(a: Vector3, b: Vector3, point: Vector3): Vector3
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < 1e-6 then
		return a
	end
	return a + ab * math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
end

-- The biggest part in a path model (its walkway rather than the trims).
local function getWalkway(model: Instance?): BasePart?
	if not model then
		return nil
	end
	if model:IsA("BasePart") then
		return model
	end
	local best: BasePart? = nil
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and (not best or child.Size.Magnitude > best.Size.Magnitude) then
			best = child
		end
	end
	return best
end

local function getPlotSpawn(): BasePart?
	local plotName = player:GetAttribute("PlotName")
	local plot = if type(plotName) == "string" and plotsFolder then plotsFolder:FindFirstChild(plotName) else nil
	local spawnArea = plot and plot:FindFirstChild("SpawnArea")
	return if spawnArea and spawnArea:IsA("BasePart") then spawnArea else nil
end

-- Player -> MainAvenue -> the plot's branch -> SpawnArea; straight to the SpawnArea when the paths haven't streamed in.
local function buildRoute(from: Vector3, spawnArea: BasePart): { Vector3 }
	local goal = spawnArea.Position + Vector3.new(0, spawnArea.Size.Y / 2 + GROUND_LIFT, 0)
	local points = { from }
	local function add(point: Vector3)
		if (point - points[#points]).Magnitude > MERGE_DISTANCE then
			table.insert(points, point)
		end
	end

	local plotName = player:GetAttribute("PlotName")
	local branches = paths and paths:FindFirstChild("PlotBranches")
	local avenue = getWalkway(paths and paths:FindFirstChild("MainAvenue"))
	local branch = getWalkway(if branches and type(plotName) == "string" then branches:FindFirstChild(`To_{plotName}`) else nil)

	if avenue and branch then
		local branchStart, branchEnd = getCenterLine(branch)
		if (branchStart - goal).Magnitude < (branchEnd - goal).Magnitude then
			branchStart, branchEnd = branchEnd, branchStart -- branchEnd is the plot end
		end
		local avenueA, avenueB = getCenterLine(avenue)
		local onBranch = closestOnSegment(branchStart, branchEnd, from)
		local onAvenue = closestOnSegment(avenueA, avenueB, from)

		if (from - onBranch).Magnitude <= (from - onAvenue).Magnitude then
			add(onBranch)
		else
			add(onAvenue)
			add(closestOnSegment(avenueA, avenueB, branchStart))
			add(branchStart)
		end
		add(branchEnd)
	end
	add(goal)
	return points
end

--// Guide --------------------------------------------------------------------------------

local function stopGuide()
	guideToken += 1
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	hideTrail()
end

local function updateGuide()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local spawnArea = getPlotSpawn()
	if not root or not root:IsA("BasePart") or not spawnArea or os.clock() > guideEndsAt then
		stopGuide()
		return
	end
	if (root.Position - spawnArea.Position).Magnitude <= ARRIVE_DISTANCE then
		stopGuide()
		return
	end
	drawTrail(buildRoute(root.Position - Vector3.new(0, FEET_DEPTH, 0), spawnArea))
end

local function startGuide()
	guideEndsAt = os.clock() + GUIDE_TIMEOUT
	if not renderConnection then
		renderConnection = runService.RenderStepped:Connect(updateGuide)
	end
end

-- After a spawn settles, shows the trail if the character is still far from its plot.
local function onCharacterAdded(character: Model)
	stopGuide()
	local token = guideToken
	if player:GetAttribute("PlotName") == nil then
		player:GetAttributeChangedSignal("PlotName"):Wait()
	end
	task.wait(SPAWN_SETTLE_SECONDS)
	if token ~= guideToken or player.Character ~= character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", WAIT_SECONDS)
	local spawnArea = getPlotSpawn()
	if root and root:IsA("BasePart") and spawnArea and (root.Position - spawnArea.Position).Magnitude > FAR_DISTANCE then
		startGuide()
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(stopGuide)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end
