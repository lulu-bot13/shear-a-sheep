--!strict

--[[
	Blue highlight, crackling sparks and a glow on "Charged" sheep (spawned in a thunderstorm, 3x wool) near the camera.
	Visuals are pooled and capped at MAX_VISUALS sheep in range; the server sets the attribute.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ChargedSheep
]]--

--// Services
local collectionService = game:GetService("CollectionService")

--// Configs
local SHEEP_TAG = "Sheep"
local CHARGED_ATTRIBUTE = "Charged"
local SPAWNED_AT_ATTRIBUTE = "SpawnedAt" -- set by SheepHandler
local FRESH_SECONDS = 3 -- only sheep spawned this recently get struck; older ones are just streaming in
local MAX_DISTANCE = 140 -- studs from the camera
local MAX_VISUALS = 20 -- Highlights are capped per client, so far sheep go without
local RANGE_CHECK_SECONDS = 0.5
local SPARK_TEXTURE = "rbxassetid://111255893302524" -- a small electric spark; empty uses the default particle
local CHARGE_COLOR = Color3.fromRGB(90, 190, 255)

--// Types
type Visual = {
	highlight: Highlight,
	attachment: Attachment,
	sparks: ParticleEmitter,
	glow: PointLight,
}

type Entry = {
	sheep: Model,
	connection: RBXScriptConnection,
	charged: boolean,
	visual: Visual?,
}

local ChargedSheep = {}

--// Instances
local highlightFolder = Instance.new("Folder") -- kept off the sheep so a pooled model never carries one away
highlightFolder.Name = "ChargedHighlights"

--// State
local entries: { [Model]: Entry } = {}
local chargedCount = 0
local rangeLoopRunning = false
local visualCount = 0
local idleVisuals: { Visual } = {}
local onCharged: ((Model) -> ())? = nil
local started = false

local maxDistanceSquared = MAX_DISTANCE * MAX_DISTANCE

--// Visual pool -----------------------------------------------------------------

local function makeVisual(): Visual
	local highlight = Instance.new("Highlight")
	highlight.FillColor = CHARGE_COLOR
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = CHARGE_COLOR
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded

	local attachment = Instance.new("Attachment")
	attachment.Name = "ChargedSparks"

	local sparks = Instance.new("ParticleEmitter")
	if SPARK_TEXTURE ~= "" then
		sparks.Texture = SPARK_TEXTURE
	end
	sparks.Shape = Enum.ParticleEmitterShape.Sphere
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.12, 0.3)
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255), CHARGE_COLOR)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Brightness = 3
	sparks.Rate = 18
	sparks.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Color = CHARGE_COLOR
	glow.Range = 8
	glow.Brightness = 1.5
	glow.Parent = attachment

	return { highlight = highlight, attachment = attachment, sparks = sparks, glow = glow }
end

local function attachVisual(entry: Entry, root: BasePart)
	local visual = table.remove(idleVisuals) or makeVisual()
	if not highlightFolder.Parent then
		highlightFolder.Parent = workspace.CurrentCamera
	end
	visual.highlight.Adornee = entry.sheep
	visual.highlight.Parent = highlightFolder
	visual.attachment.Parent = root
	entry.visual = visual
	visualCount += 1
end

local function releaseVisual(entry: Entry)
	local visual = entry.visual
	if not visual then
		return
	end
	entry.visual = nil
	visualCount -= 1
	visual.highlight.Adornee = nil
	visual.highlight.Parent = nil

	-- If the sheep was removed by replication, the attachment went with it and is locked; make a new one next time.
	if pcall(function()
		visual.attachment.Parent = nil
	end) then
		table.insert(idleVisuals, visual)
	else
		visual.highlight:Destroy()
	end
end

--// Range check -----------------------------------------------------------------

local function getRoot(sheep: Model): BasePart?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function refreshVisuals()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position
	for _, entry in entries do
		if not entry.charged then
			continue
		end
		local root = getRoot(entry.sheep)
		local offset = if root then root.Position - cameraPosition else nil
		local inRange = offset ~= nil and offset:Dot(offset) <= maxDistanceSquared

		if not inRange then
			releaseVisual(entry)
		elseif root and not entry.visual and visualCount < MAX_VISUALS then
			attachVisual(entry, root)
		end
	end
end

-- Only runs while some sheep is charged, so a normal day costs nothing.
local function runRangeLoop()
	rangeLoopRunning = true
	while chargedCount > 0 do
		refreshVisuals()
		task.wait(RANGE_CHECK_SECONDS)
	end
	rangeLoopRunning = false
end

--// Tracking --------------------------------------------------------------------

local function setCharged(entry: Entry, charged: boolean, fresh: boolean)
	if entry.charged == charged then
		return
	end
	entry.charged = charged

	if charged then
		chargedCount += 1
		if not rangeLoopRunning then
			task.spawn(runRangeLoop)
		end
		if fresh and onCharged then
			onCharged(entry.sheep)
		end
	else
		chargedCount -= 1
		releaseVisual(entry)
	end
end

local function onSheepAdded(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local sheep = instance

	local entry: Entry
	entry = {
		sheep = sheep,
		charged = false,
		connection = sheep:GetAttributeChangedSignal(CHARGED_ATTRIBUTE):Connect(function()
			setCharged(entry, sheep:GetAttribute(CHARGED_ATTRIBUTE) == true, true)
		end),
	}
	entries[sheep] = entry
	local spawnedAt = sheep:GetAttribute(SPAWNED_AT_ATTRIBUTE)
	local fresh = type(spawnedAt) == "number" and workspace:GetServerTimeNow() - spawnedAt <= FRESH_SECONDS
	setCharged(entry, sheep:GetAttribute(CHARGED_ATTRIBUTE) == true, fresh)
end

-- Fires when the sheep vanishes (back to the server's pool) or streams out.
local function onSheepRemoved(instance: Instance)
	local entry = entries[instance :: Model]
	if not entry then
		return
	end
	entry.connection:Disconnect()
	setCharged(entry, false, false)
	entries[instance :: Model] = nil
end

--// API -------------------------------------------------------------------------

-- Starts tracking; `onNewlyCharged` runs for each sheep that turns Charged after this point (not for ones already there).
function ChargedSheep.start(onNewlyCharged: (Model) -> ())
	if started then
		return
	end
	started = true

	for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
		onSheepAdded(sheep)
	end
	onCharged = onNewlyCharged
	collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
	collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(onSheepRemoved)
end

return ChargedSheep
