--!strict

--[[
	Animates the plot builds that PlotBuildHandler flags with the Unlocked attribute. A locked build is invisible;
	when it unlocks it appears scattered above its spot, drops in with a bounce and fades to opaque.
	Builds that are already unlocked when first seen are shown as they are, with no animation.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PlotBuildsClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Configs
local BUILD_TAG = "RebirthBuild"
local UNLOCKED_ATTRIBUTE = "Unlocked"
local DROP_SECONDS = 1.1
local FADE_SECONDS = 0.5
local SCATTER_RADIUS = 7
local DROP_HEIGHT = 12
local SCATTER_YAW = math.rad(35)

type Build = {
	instance: PVInstance,
	target: CFrame,
	parts: { [BasePart]: number },
	decals: { [Decal]: number },
	guis: { SurfaceGui | BillboardGui },
	startTime: number,
	offset: Vector3,
	yaw: number,
	connection: RBXScriptConnection?,
}

--// State
local builds: { [Instance]: Build } = {}
local active: { [Build]: boolean } = {}
local renderConnection: RBXScriptConnection? = nil
local random = Random.new()

local function setGuisEnabled(build: Build, enabled: boolean)
	for _, gui in build.guis do
		gui.Enabled = enabled
	end
end

local function setFade(build: Build, alpha: number)
	local inverse = 1 - alpha
	for part, base in build.parts do
		part.Transparency = base + (1 - base) * inverse
	end
	for decal, base in build.decals do
		decal.Transparency = base + (1 - base) * inverse
	end
end

local function hide(build: Build)
	active[build] = nil
	setFade(build, 0)
	setGuisEnabled(build, false)
	build.instance:PivotTo(build.target)
end

local function show(build: Build)
	active[build] = nil
	setFade(build, 1)
	setGuisEnabled(build, true)
	build.instance:PivotTo(build.target)
end

local function step()
	local now = os.clock()
	for build in active do
		local alpha = (now - build.startTime) / DROP_SECONDS
		if alpha >= 1 then
			show(build)
			continue
		end

		local glide = tweenService:GetValue(alpha, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local fall = tweenService:GetValue(alpha, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		local fadeAlpha = math.min(alpha * DROP_SECONDS / FADE_SECONDS, 1)
		local fade = tweenService:GetValue(fadeAlpha, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		local offset = build.offset
		local position = build.target.Position
			+ Vector3.new(offset.X * (1 - glide), offset.Y * (1 - fall), offset.Z * (1 - glide))
		local spin = CFrame.Angles(0, build.yaw * (1 - glide), 0)
		build.instance:PivotTo(CFrame.new(position) * spin * build.target.Rotation)
		setFade(build, fade)
	end

	if next(active) == nil and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function play(build: Build)
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(random:NextNumber()) * SCATTER_RADIUS
	build.offset = Vector3.new(math.cos(angle) * distance, DROP_HEIGHT, math.sin(angle) * distance)
	build.yaw = random:NextNumber(-SCATTER_YAW, SCATTER_YAW)
	build.startTime = os.clock()
	active[build] = true

	if not renderConnection then
		renderConnection = runService.PreRender:Connect(step)
	end
end

local function refresh(build: Build, animate: boolean)
	if build.instance:GetAttribute(UNLOCKED_ATTRIBUTE) == true then
		if animate then
			play(build)
		else
			show(build)
		end
	else
		hide(build)
	end
end

local function register(instance: Instance)
	if builds[instance] or not instance:IsA("PVInstance") then
		return
	end

	local build: Build = {
		instance = instance,
		target = instance:GetPivot(),
		parts = {},
		decals = {},
		guis = {},
		startTime = 0,
		offset = Vector3.zero,
		yaw = 0,
		connection = nil,
	}
	build.connection = instance:GetAttributeChangedSignal(UNLOCKED_ATTRIBUTE):Connect(function()
		refresh(build, true)
	end)

	local function track(item: Instance)
		if item:IsA("BasePart") then
			build.parts[item] = item.Transparency
		elseif item:IsA("Decal") then
			build.decals[item] = item.Transparency
		elseif item:IsA("SurfaceGui") or item:IsA("BillboardGui") then
			table.insert(build.guis, item)
		end
	end
	track(instance)
	for _, descendant in instance:GetDescendants() do
		track(descendant)
	end

	builds[instance] = build
	refresh(build, false)
end

local function unregister(instance: Instance)
	local build = builds[instance]
	if build then
		if build.connection then
			build.connection:Disconnect()
		end
		active[build] = nil
		builds[instance] = nil
	end
end

--// Setup ---------------------------------------------------------------------------

collectionService:GetInstanceAddedSignal(BUILD_TAG):Connect(register)
collectionService:GetInstanceRemovedSignal(BUILD_TAG):Connect(unregister)
for _, instance in collectionService:GetTagged(BUILD_TAG) do
	register(instance)
end
