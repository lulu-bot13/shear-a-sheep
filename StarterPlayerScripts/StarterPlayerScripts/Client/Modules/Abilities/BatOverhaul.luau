--[[
	Bat Overhaul's effect for everyone: bats swarm over the caster's plot while copies of their shears snip wool off each sheep, then it all flies off.
	The server holds the sheep and shears them on the same timeline; the bats also cover the screen of the caster and anyone on that plot.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Abilities.BatOverhaul
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Instances
local localPlayer = players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local shearTemplates = replicatedStorage:WaitForChild("Assets"):FindFirstChild("Shears")

--// Configs
local BAT_IMAGE = "rbxassetid://85493305397361"
local SHEEP_TAG = "Sheep"
local SWARM_SOUND_NAME = "BatSwarm" -- optional Sounds in SoundService.UISounds
local LEAVE_SOUND_NAME = "BatLeave"
local BATS_SOUND_NAME = "Bats" -- in SoundService.AbilitySounds; plays through the whole effect
local FLAP_SPEED = 22 -- radians per second of the wing-beat squash
local FLAP_SQUASH = 0.35 -- share of a bat's height each beat squashes away
local ARRIVE_JITTER = 0.3 -- seconds each bat may set off late, so they don't move as one block

--// World bats
local MIN_BATS, BATS_PER_SHEEP, MAX_BATS = 16, 2, 48
local BAT_MIN_SIZE, BAT_MAX_SIZE = 2.5, 4.5 -- studs
local BAT_MIN_HEIGHT, BAT_MAX_HEIGHT = 3, 9 -- studs above their spot
local BAT_MIN_ORBIT, BAT_MAX_ORBIT = 1.5, 7 -- studs they circle their spot at
local BAT_MIN_SPEED, BAT_MAX_SPEED = 1.5, 3.5 -- radians per second around their spot
local BAT_SPREAD = 0.7 -- radians either side of the swarm's direction each bat flies in and off at
local FLY_DISTANCE, FLY_HEIGHT = 70, 30 -- how far off the plot they come from and go to
local AREA_PADDING = 4

--// Shears
local MAX_SHEARS = 24
local SHEAR_HEIGHT = 3.5 -- studs above the sheep's pivot
local SHEAR_ORBIT = 1.2
local SHEAR_SPIN = math.rad(400) -- radians per second
local SHEAR_SNIP_ANGLE = math.rad(25)
local SHEAR_POP_SECONDS = 0.35 -- they burst out of the sheep this long before the bats settle

--// Wool tufts
local TUFTS_PER_SHEEP = 2
local MAX_TUFTS_PER_PULSE = 40
local TUFT_SECONDS = 0.45
local TUFT_SHRINK_SECONDS = 0.25

--// Screen cover
local COVER_RANGE = 20 -- studs past the plot's edge a character still gets their screen covered
local SCREEN_COLUMNS, SCREEN_ROWS = 7, 4 -- one bat per cell so the whole screen is covered
local SCREEN_EXTRA_BATS = 10
local SCREEN_MIN_SIZE, SCREEN_MAX_SIZE = 0.28, 0.42 -- of the screen's height
local SCREEN_WANDER = 0.06 -- of the screen, how far each bat drifts around its spot

type Timeline = { startsAt: number, arrive: number, swarm: number, leave: number }

type SheepEntry = {
	sheep: Model,
	id: any,
	base: Vector3,
	color: Color3,
}

type Bat = {
	attachment: Attachment,
	image: ImageLabel,
	spot: Vector3,
	orbit: number,
	speed: number,
	height: number,
	phase: number,
	delay: number,
	from: Vector3,
	to: Vector3,
}

type FlyingShear = {
	model: PVInstance,
	entry: SheepEntry,
	phase: number,
	to: Vector3,
	shown: boolean,
}

type ScreenBat = {
	image: ImageLabel,
	size: number,
	spot: Vector2,
	phase: number,
	delay: number,
	from: Vector2,
	to: Vector2,
}

--// State
local random = Random.new()

local effectFolder = Instance.new("Folder")
effectFolder.Name = "BatOverhaulEffects"
effectFolder.Parent = workspace

local BatOverhaul = {}

--// Helpers -------------------------------------------------------------------------

local function isValid(entry: SheepEntry): boolean
	local sheep = entry.sheep
	return sheep.Parent ~= nil and collectionService:HasTag(sheep, SHEEP_TAG) and sheep:GetAttribute("id") == entry.id
end

-- Where the sheep is now, or where it was once it has been sheared away.
local function getSheepPosition(entry: SheepEntry): Vector3
	return if isValid(entry) then entry.sheep:GetPivot().Position else entry.base
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function easeIn(t: number): number
	return t * t
end

-- Eased 0-1 through flying in and through flying off, for something that sets off `delay` seconds late.
local function getProgress(elapsed: number, delay: number, timeline: Timeline): (number, number)
	local arriving = math.clamp((elapsed - delay) / math.max(timeline.arrive - delay, 0.05), 0, 1)
	local leaveStart = timeline.arrive + timeline.swarm + delay
	local leaving = math.clamp((elapsed - leaveStart) / math.max(timeline.leave - delay, 0.05), 0, 1)
	return easeOut(arriving), easeIn(leaving)
end

local function getFlap(elapsed: number, phase: number): number
	return 1 - FLAP_SQUASH * math.abs(math.sin(elapsed * FLAP_SPEED + phase))
end

-- Plays a copy of the sound from the world point so it is 3D; nothing happens if the sound isn't set up.
local function playSoundAt(name: string, position: Vector3)
	local folder = soundService:FindFirstChild("UISounds")
	local sound = folder and folder:FindFirstChild(name)
	if not sound or not sound:IsA("Sound") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local copy = sound:Clone()
	copy.Parent = attachment
	copy:Play()
	debris:AddItem(attachment, math.max(copy.TimeLength, 1) + 0.5)
end

-- A copy of the Bats sound at the plot that starts in `delay` seconds; destroying the returned attachment stops it.
local function startBatsSound(position: Vector3, delay: number): Attachment?
	local abilitySounds = soundService:FindFirstChild("AbilitySounds")
	local template = abilitySounds and abilitySounds:FindFirstChild(BATS_SOUND_NAME)
	if not template or not template:IsA("Sound") then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = template:Clone()
	sound.Parent = attachment
	task.delay(delay, function()
		if sound.Parent then
			sound:Play()
		end
	end)
	return attachment
end

local function buildEntries(list: { any }): { SheepEntry }
	local entries: { SheepEntry } = {}
	for _, item in list do
		local sheep = type(item) == "table" and item.sheep
		if typeof(sheep) ~= "Instance" or not sheep:IsA("Model") then
			continue -- streamed out on this client
		end
		table.insert(entries, {
			sheep = sheep,
			id = sheep:GetAttribute("id"),
			base = sheep:GetPivot().Position,
			color = if typeof(item.color) == "Color3" then item.color else Color3.new(1, 1, 1),
		})
	end
	return entries
end

-- The plot's SheepArea from the server, or a box around the sheep when it has none.
local function getArea(info: any, entries: { SheepEntry }): (CFrame, Vector3)
	if typeof(info.areaCFrame) == "CFrame" and typeof(info.areaSize) == "Vector3" then
		return info.areaCFrame, info.areaSize
	end

	local low, high = entries[1].base, entries[1].base
	for _, entry in entries do
		low, high = low:Min(entry.base), high:Max(entry.base)
	end
	local padding = Vector3.new(AREA_PADDING * 2, 0, AREA_PADDING * 2)
	return CFrame.new((low + high) / 2), high - low + padding
end

local function getRandomAreaPoint(areaCFrame: CFrame, areaSize: Vector3): Vector3
	local halfX = math.max(areaSize.X / 2 - AREA_PADDING, 0)
	local halfZ = math.max(areaSize.Z / 2 - AREA_PADDING, 0)
	return areaCFrame:PointToWorldSpace(Vector3.new(random:NextNumber(-halfX, halfX), areaSize.Y / 2, random:NextNumber(-halfZ, halfZ)))
end

-- A point far off the plot and up in the sky, roughly in the swarm's direction.
local function getSkyPoint(center: Vector3, angle: number, heightScale: number): Vector3
	local spread = angle + random:NextNumber(-BAT_SPREAD, BAT_SPREAD)
	local distance = FLY_DISTANCE * random:NextNumber(0.8, 1.2)
	return center + Vector3.new(math.cos(spread) * distance, FLY_HEIGHT * heightScale * random:NextNumber(0.8, 1.2), math.sin(spread) * distance)
end

--// World bats ----------------------------------------------------------------------

local function createBatBillboard(position: Vector3, size: number): (Attachment, ImageLabel)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(size, size)
	billboard.LightInfluence = 0
	billboard.Parent = attachment

	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = UDim2.fromScale(1, 1)
	image.BackgroundTransparency = 1
	image.Image = BAT_IMAGE
	image.Parent = billboard

	attachment.Parent = workspace.Terrain
	return attachment, image
end

-- Half circle over a sheep, half over random spots on the plot so it is all covered.
local function createBats(entries: { SheepEntry }, areaCFrame: CFrame, areaSize: Vector3, inAngle: number, outAngle: number): { Bat }
	local center = areaCFrame.Position
	local bats: { Bat } = {}
	for index = 1, math.clamp(#entries * BATS_PER_SHEEP, MIN_BATS, MAX_BATS) do
		local spot = if index % 2 == 1
			then entries[random:NextInteger(1, #entries)].base
			else getRandomAreaPoint(areaCFrame, areaSize)
		local from = getSkyPoint(center, inAngle, 1)
		local attachment, image = createBatBillboard(from, random:NextNumber(BAT_MIN_SIZE, BAT_MAX_SIZE))
		table.insert(bats, {
			attachment = attachment,
			image = image,
			spot = spot,
			orbit = random:NextNumber(BAT_MIN_ORBIT, BAT_MAX_ORBIT),
			speed = random:NextNumber(BAT_MIN_SPEED, BAT_MAX_SPEED) * (if random:NextNumber() < 0.5 then -1 else 1),
			height = random:NextNumber(BAT_MIN_HEIGHT, BAT_MAX_HEIGHT),
			phase = random:NextNumber(0, math.pi * 2),
			delay = random:NextNumber(0, ARRIVE_JITTER),
			from = from,
			to = getSkyPoint(center, outAngle, 1.5),
		})
	end
	return bats
end

local function updateBat(bat: Bat, elapsed: number, timeline: Timeline)
	local angle = bat.phase + bat.speed * elapsed
	local hover = bat.spot
		+ Vector3.new(math.cos(angle) * bat.orbit, bat.height + math.sin(elapsed * 3 + bat.phase) * 0.8, math.sin(angle) * bat.orbit)
	local arriving, leaving = getProgress(elapsed, bat.delay, timeline)
	bat.attachment.WorldPosition = bat.from:Lerp(hover, arriving):Lerp(bat.to, leaving)
	bat.image.Size = UDim2.fromScale(1, getFlap(elapsed, bat.phase))
	bat.image.ImageTransparency = math.clamp((leaving - 0.6) / 0.4, 0, 1)
end

--// Shears --------------------------------------------------------------------------

local function prepareParts(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
end

local function buildPlaceholderShear(): BasePart
	local blade = Instance.new("Part")
	blade.Name = "BatOverhaulShear"
	blade.Size = Vector3.new(0.3, 0.2, 1.6)
	blade.Color = Color3.fromRGB(190, 195, 205)
	blade.Material = Enum.Material.Metal
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanQuery = false
	blade.CanTouch = false
	blade.CastShadow = false
	return blade
end

-- A show-only copy of the caster's shear Tool from Assets.Shears, as a Model pivoting on its Handle.
local function buildShear(shearId: any): PVInstance
	local template = type(shearId) == "string" and shearTemplates and shearTemplates:FindFirstChild(shearId)
	if not template or not template:IsA("Tool") or not template:FindFirstChild("Handle") then
		return buildPlaceholderShear()
	end

	local copy = template:Clone()
	local model = Instance.new("Model")
	model.Name = "BatOverhaulShear"
	for _, child in copy:GetChildren() do
		child.Parent = model
	end
	copy:Destroy()
	prepareParts(model)

	local handle = model:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		model.PrimaryPart = handle
	end
	return model
end

local function createShears(entries: { SheepEntry }, shearId: any, center: Vector3, outAngle: number): { FlyingShear }
	local shears: { FlyingShear } = {}
	for index = 1, math.min(#entries, MAX_SHEARS) do
		table.insert(shears, {
			model = buildShear(shearId),
			entry = entries[index],
			phase = random:NextNumber(0, math.pi * 2),
			to = getSkyPoint(center, outAngle, 1.5),
			shown = false,
		})
	end
	return shears
end

-- They burst out of the sheep just before the bats settle, circle and snip over it, then fly off with the bats.
local function updateShear(shear: FlyingShear, elapsed: number, timeline: Timeline)
	local popping = math.clamp((elapsed - (timeline.arrive - SHEAR_POP_SECONDS)) / SHEAR_POP_SECONDS, 0, 1)
	if popping <= 0 then
		return
	end
	if not shear.shown then
		shear.shown = true
		shear.model.Parent = effectFolder
	end

	local sheepPosition = getSheepPosition(shear.entry)
	local angle = shear.phase + elapsed * 4
	local hover = sheepPosition
		+ Vector3.new(math.cos(angle) * SHEAR_ORBIT, SHEAR_HEIGHT + math.sin(elapsed * 6 + shear.phase) * 0.4, math.sin(angle) * SHEAR_ORBIT)
	local _, leaving = getProgress(elapsed, 0, timeline)
	local position = sheepPosition:Lerp(hover, easeOut(popping)):Lerp(shear.to, leaving)
	local turn = CFrame.Angles(0, SHEAR_SPIN * elapsed + shear.phase, SHEAR_SNIP_ANGLE * math.sin(elapsed * 14 + shear.phase))
	shear.model:PivotTo(CFrame.new(position) * turn)
end

--// Wool tufts ----------------------------------------------------------------------

local function throwTuft(from: Vector3, color: Color3)
	local tuft = Instance.new("Part")
	tuft.Name = "WoolTuft"
	tuft.Shape = Enum.PartType.Ball
	tuft.Material = Enum.Material.SmoothPlastic
	tuft.Anchored = true
	tuft.CanCollide = false
	tuft.CanQuery = false
	tuft.CanTouch = false
	tuft.CastShadow = false
	tuft.Size = Vector3.one * random:NextNumber(0.5, 1)
	tuft.Color = color
	tuft.CFrame = CFrame.new(from)
	tuft.Parent = effectFolder

	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(2, 4)
	local target = from + Vector3.new(math.cos(angle) * distance, random:NextNumber(1, 3), math.sin(angle) * distance)
	local fly = tweenService:Create(tuft, TweenInfo.new(TUFT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(target),
	})
	local shrink = tweenService:Create(tuft, TweenInfo.new(TUFT_SHRINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = Vector3.one * 0.05,
	})
	fly.Completed:Once(function()
		shrink:Play()
	end)
	shrink.Completed:Once(function()
		tuft:Destroy()
	end)
	fly:Play()
end

-- Wool flies off each sheep on the server's snip pulses.
local function scheduleTufts(entries: { SheepEntry }, firstPulseIn: number, swarm: number, pulses: number)
	local perSheep = math.clamp(math.floor(MAX_TUFTS_PER_PULSE / #entries), 1, TUFTS_PER_SHEEP)
	for pulse = 1, pulses do
		task.delay(math.max(firstPulseIn + swarm * (pulse - 1) / pulses, 0), function()
			for _, entry in entries do
				if isValid(entry) then
					for _ = 1, perSheep do
						throwTuft(getSheepPosition(entry), entry.color)
					end
				end
			end
		end)
	end
end

--// Screen cover --------------------------------------------------------------------

local function shouldCoverScreen(caster: Player?, areaCFrame: CFrame, areaSize: Vector3): boolean
	if caster == localPlayer then
		return true
	end
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local offset = areaCFrame:PointToObjectSpace(root.Position)
	return math.abs(offset.X) <= areaSize.X / 2 + COVER_RANGE and math.abs(offset.Z) <= areaSize.Z / 2 + COVER_RANGE
end

-- Just past the screen's edge, straight out from the middle through `spot`.
local function getOffScreenPoint(spot: Vector2): Vector2
	local direction = spot - Vector2.new(0.5, 0.5)
	direction = if direction.Magnitude > 0.01 then direction.Unit else Vector2.new(0, -1)
	return Vector2.new(0.5, 0.5) + direction * 1.2
end

local function createScreenBats(): (ScreenGui, { ScreenBat })
	local gui = Instance.new("ScreenGui")
	gui.Name = "BatOverhaul"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50

	local bats: { ScreenBat } = {}
	local cells = SCREEN_COLUMNS * SCREEN_ROWS
	for index = 1, cells + SCREEN_EXTRA_BATS do
		local spot = if index <= cells
			then Vector2.new(
				((index - 1) % SCREEN_COLUMNS + random:NextNumber(0.2, 0.8)) / SCREEN_COLUMNS,
				((index - 1) // SCREEN_COLUMNS + random:NextNumber(0.2, 0.8)) / SCREEN_ROWS
			)
			else Vector2.new(random:NextNumber(), random:NextNumber())
		local from = getOffScreenPoint(spot)
		local size = random:NextNumber(SCREEN_MIN_SIZE, SCREEN_MAX_SIZE)

		local image = Instance.new("ImageLabel")
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.BackgroundTransparency = 1
		image.Image = BAT_IMAGE
		image.SizeConstraint = Enum.SizeConstraint.RelativeYY
		image.Size = UDim2.fromScale(size, size)
		image.Position = UDim2.fromScale(from.X, from.Y)
		image.Rotation = random:NextNumber(-15, 15)
		image.ZIndex = index
		image.Parent = gui

		table.insert(bats, {
			image = image,
			size = size,
			spot = spot,
			phase = random:NextNumber(0, math.pi * 2),
			delay = random:NextNumber(0, ARRIVE_JITTER),
			from = from,
			to = Vector2.new(spot.X + random:NextNumber(-0.4, 0.4), -0.5),
		})
	end

	gui.Parent = playerGui
	return gui, bats
end

local function updateScreenBat(bat: ScreenBat, elapsed: number, timeline: Timeline)
	local wander = Vector2.new(math.sin(elapsed * 1.7 + bat.phase), math.cos(elapsed * 1.3 + bat.phase)) * SCREEN_WANDER
	local arriving, leaving = getProgress(elapsed, bat.delay, timeline)
	local position = bat.from:Lerp(bat.spot + wander, arriving):Lerp(bat.to, leaving)
	bat.image.Position = UDim2.fromScale(position.X, position.Y)
	bat.image.Size = UDim2.fromScale(bat.size, bat.size * getFlap(elapsed, bat.phase))
end

--// Effect --------------------------------------------------------------------------

function BatOverhaul.onEffect(caster: Player?, info: any)
	if type(info) ~= "table" or type(info.sheep) ~= "table" or type(info.startsAt) ~= "number" then
		return
	end
	local arrive, swarm, leave, pulses = info.arriveSeconds, info.swarmSeconds, info.leaveSeconds, info.snipPulses
	if type(arrive) ~= "number" or type(swarm) ~= "number" or type(leave) ~= "number" or type(pulses) ~= "number" then
		return
	end

	local entries = buildEntries(info.sheep)
	if #entries == 0 then
		return
	end

	local timeline: Timeline = { startsAt = info.startsAt, arrive = arrive, swarm = swarm, leave = leave }
	local areaCFrame, areaSize = getArea(info, entries)
	local center = areaCFrame.Position
	local inAngle = random:NextNumber(0, math.pi * 2)
	local outAngle = inAngle + math.pi + random:NextNumber(-1, 1) -- they leave out the far side
	local bats = createBats(entries, areaCFrame, areaSize, inAngle, outAngle)
	local shears = createShears(entries, if caster then caster:GetAttribute("ShearId") else nil, center, outAngle)
	local screenGui: ScreenGui?, screenBats: { ScreenBat } = nil, {}
	if shouldCoverScreen(caster, areaCFrame, areaSize) then
		screenGui, screenBats = createScreenBats()
	end

	local secondsToStart = timeline.startsAt - workspace:GetServerTimeNow()
	local total = arrive + swarm + leave
	local batsSound = startBatsSound(center, math.max(secondsToStart, 0))
	task.delay(math.max(secondsToStart, 0), playSoundAt, SWARM_SOUND_NAME, center)
	task.delay(math.max(secondsToStart + arrive + swarm, 0), playSoundAt, LEAVE_SOUND_NAME, center)
	scheduleTufts(entries, secondsToStart + arrive, swarm, math.max(math.floor(pulses), 1))

	local connection: RBXScriptConnection
	connection = runService.RenderStepped:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - timeline.startsAt
		if elapsed >= total then
			connection:Disconnect()
			for _, bat in bats do
				bat.attachment:Destroy()
			end
			for _, shear in shears do
				shear.model:Destroy()
			end
			if screenGui then
				screenGui:Destroy()
			end
			if batsSound then
				batsSound:Destroy()
			end
			return
		end

		for _, bat in bats do
			updateBat(bat, elapsed, timeline)
		end
		for _, shear in shears do
			updateShear(shear, elapsed, timeline)
		end
		for _, bat in screenBats do
			updateScreenBat(bat, elapsed, timeline)
		end
	end)
end

return BatOverhaul
