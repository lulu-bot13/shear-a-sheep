--!strict

--[[
	Ability Shack effects above the podium: the slot-machine reel, the spinning hologram with a rarity-sized burst, and a light version for onlookers.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.AbilityShackVFX
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Configs
local FONT = Enum.Font.FredokaOne
local FX_FOLDER_NAME = "AbilityShackFX"
local OUTLINE_COLOR = Color3.fromRGB(20, 20, 28)
local REEL_HEIGHT = 7 -- studs above the podium's top
local REEL_SIZE = UDim2.fromScale(9, 3.6) -- studs
local REEL_STEPS = 26
local REEL_FIRST_INTERVAL = 0.04
local REEL_SLOWDOWN = 0.42 -- extra seconds the last step waits; earlier steps ease into it
local REEL_LAND_SECONDS = 0.45
local HOLOGRAM_SIZE = Vector3.new(7, 2.6, 0.05)
local HOLOGRAM_HEIGHT = 3.4
local HOLOGRAM_RISE_SECONDS = 0.45
local HOLOGRAM_SPIN = 1.6 -- radians per second
local HOLOGRAM_BOB = 0.25
local COLUMN_HEIGHT = 16
local FADE_SECONDS = 0.35
local SPECTATOR_SECONDS = 2.5
local TICK_SOUND_ID = ""
local WIN_SOUND_IDS: { [string]: string } = { Common = "", Rare = "", Epic = "", Legendary = "", Mythic = "" }

-- How big each rarity's celebration is. flash is the screen flash's starting transparency (1 = none).
type Tier = { particles: number, ring: number, seconds: number, column: boolean, flash: number, light: number }
local TIERS: { [string]: Tier } = {
	Common = { particles = 0, ring = 5, seconds = 2.5, column = false, flash = 1, light = 2 },
	Rare = { particles = 25, ring = 7, seconds = 2.8, column = false, flash = 1, light = 3 },
	Epic = { particles = 50, ring = 9, seconds = 3.2, column = false, flash = 1, light = 4 },
	Legendary = { particles = 90, ring = 13, seconds = 3.8, column = true, flash = 0.6, light = 6 },
	Mythic = { particles = 150, ring = 18, seconds = 4.5, column = true, flash = 0.35, light = 9 },
}

export type Entry = {
	id: string,
	name: string,
	rarity: string,
	color: Color3,
}

--// State
local random = Random.new()
local sounds: { [string]: Sound } = {}
local spectatorAnchor: BasePart? = nil
local flashFrame: Frame? = nil

local AbilityShackVFX = {}

-- How long playReel takes, so onlookers' effects can wait for the roller's reel.
AbilityShackVFX.REEL_SECONDS = REEL_LAND_SECONDS
for step = 1, REEL_STEPS do
	AbilityShackVFX.REEL_SECONDS += REEL_FIRST_INTERVAL + REEL_SLOWDOWN * (step / REEL_STEPS) ^ 3
end

--// Helpers ---------------------------------------------------------------------

local function getFolder(): Folder
	local existing = workspace:FindFirstChild(FX_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = FX_FOLDER_NAME
	folder.Parent = workspace
	return folder
end

local function makePart(size: Vector3, cframe: CFrame, color: Color3?, transparency: number?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.new(1, 1, 1)
	part.Transparency = transparency or 1
	part.Size = size
	part.CFrame = cframe
	return part
end

-- A flat neon disc or column; cylinders run along X, so they're turned to stand on Y.
local function makeCylinder(length: number, width: number, cframe: CFrame, color: Color3, transparency: number): Part
	local part = makePart(Vector3.new(length, width, width), cframe * CFrame.Angles(0, 0, math.rad(90)), color, transparency)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function makeLabel(parent: Instance, text: string, color: Color3, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Size = size
	label.Position = position

	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE_COLOR
	stroke.Thickness = 2
	stroke.Parent = label

	label.Parent = parent
	return label
end

local function fadeLabels(root: Instance)
	local info = TweenInfo.new(FADE_SECONDS)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			tweenService:Create(descendant, info, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("UIStroke") then
			tweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end
end

local function playSound(id: string?, speed: number?)
	if not id or id == "" then
		return
	end

	local sound = sounds[id]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.SoundId = id
		newSound.Parent = soundService
		sounds[id] = newSound
		sound = newSound
	end
	sound.PlaybackSpeed = speed or 1
	sound:Play()
end

local function flash(color: Color3, transparency: number)
	if transparency >= 1 then
		return
	end

	local frame = flashFrame
	if not frame or not frame.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "AbilityShackFlash"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 10

		local newFrame = Instance.new("Frame")
		newFrame.Size = UDim2.fromScale(1, 1)
		newFrame.BorderSizePixel = 0
		newFrame.Active = false
		newFrame.Parent = gui
		gui.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
		flashFrame = newFrame
		frame = newFrame
	end

	local current = frame :: Frame
	current.BackgroundColor3 = color
	current.BackgroundTransparency = transparency
	tweenService:Create(current, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

local function burst(base: CFrame, color: Color3, count: number, parent: Instance): Part?
	if count <= 0 then
		return nil
	end

	local emitterPart = makePart(Vector3.new(2, 0.2, 2), base)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Lifetime = NumberRange.new(0.8, 1.5)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Drag = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Parent = emitterPart
	emitterPart.Parent = parent
	emitter:Emit(count)
	return emitterPart
end

--// Public API ------------------------------------------------------------------

-- Cycles names from `pool` above the podium, slowing down until it lands on `result`. Yields until it has landed.
function AbilityShackVFX.playReel(top: Vector3, pool: { Entry }, result: Entry)
	local anchor = makePart(Vector3.one * 0.2, CFrame.new(top + Vector3.new(0, REEL_HEIGHT, 0)))
	local billboard = Instance.new("BillboardGui")
	billboard.Size = REEL_SIZE
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BackgroundTransparency = 0.15
	frame.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = frame
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Thickness = 4
	frameStroke.Parent = frame

	local white = Color3.new(1, 1, 1)
	local above = makeLabel(frame, "", white, UDim2.fromScale(0.75, 0.2), UDim2.fromScale(0.5, 0.17))
	local current = makeLabel(frame, "", white, UDim2.fromScale(0.9, 0.42), UDim2.fromScale(0.5, 0.5))
	local below = makeLabel(frame, "", white, UDim2.fromScale(0.75, 0.2), UDim2.fromScale(0.5, 0.83))
	above.TextTransparency = 0.55
	below.TextTransparency = 0.55
	local currentScale = Instance.new("UIScale")
	currentScale.Parent = current
	anchor.Parent = getFolder()

	-- Step i shows sequence[i] in the middle with its neighbours above and below; it lands on result at the last step.
	local sequence: { Entry } = {}
	for index = 1, REEL_STEPS + 1 do
		local pick = if #pool > 0 then pool[random:NextInteger(1, #pool)] else result
		if #pool > 1 and index > 1 and pick == sequence[index - 1] then
			pick = pool[(table.find(pool, pick) :: number) % #pool + 1]
		end
		sequence[index] = pick
	end
	sequence[REEL_STEPS] = result
	if #pool > 1 and sequence[REEL_STEPS + 1] == result then
		sequence[REEL_STEPS + 1] = pool[(table.find(pool, result) or 0) % #pool + 1]
	end

	local popInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for step = 1, REEL_STEPS do
		local entry = sequence[step]
		local previous = sequence[step - 1] or sequence[REEL_STEPS + 1]
		local nextEntry = sequence[step + 1]
		above.Text, above.TextColor3 = previous.name, previous.color
		below.Text, below.TextColor3 = nextEntry.name, nextEntry.color
		current.Text, current.TextColor3 = entry.name, entry.color
		frameStroke.Color = entry.color
		currentScale.Scale = 1.15
		tweenService:Create(currentScale, popInfo, { Scale = 1 }):Play()

		local progress = step / REEL_STEPS
		playSound(TICK_SOUND_ID, 0.9 + progress * 0.4)
		task.wait(REEL_FIRST_INTERVAL + REEL_SLOWDOWN * progress ^ 3)
	end

	above.Visible = false
	below.Visible = false
	tweenService:Create(currentScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.35,
	}):Play()
	task.wait(REEL_LAND_SECONDS)
	anchor:Destroy()
end

-- The won ability's spinning hologram on the podium with a burst that grows with its rarity.
function AbilityShackVFX.reveal(top: Vector3, entry: Entry, subtitle: string?)
	local tier = TIERS[entry.rarity] or TIERS.Common
	local folder = getFolder()
	local base = CFrame.new(top)
	local effects: { Instance } = {}

	local display = makePart(HOLOGRAM_SIZE, base)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Face = face
		surface.LightInfluence = 0
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		makeLabel(surface, entry.name, entry.color, UDim2.fromScale(1, 0.6), UDim2.fromScale(0.5, 0.32))
		makeLabel(surface, subtitle or entry.rarity, Color3.new(1, 1, 1), UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0.82))
		surface.Parent = display
	end
	local light = Instance.new("PointLight")
	light.Color = entry.color
	light.Brightness = tier.light
	light.Range = 8 + tier.ring
	light.Parent = display
	display.Parent = folder
	table.insert(effects, display)

	local ring = makeCylinder(0.15, 2, base, entry.color, 0.2)
	ring.Parent = folder
	table.insert(effects, ring)
	tweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, tier.ring, tier.ring),
		Transparency = 1,
	}):Play()

	if tier.column then
		local column = makeCylinder(COLUMN_HEIGHT, 2.4, base * CFrame.new(0, COLUMN_HEIGHT / 2, 0), entry.color, 0.4)
		column.Parent = folder
		table.insert(effects, column)
		tweenService:Create(column, TweenInfo.new(tier.seconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = Vector3.new(COLUMN_HEIGHT, 0.2, 0.2),
			Transparency = 1,
		}):Play()
	end

	local emitterPart = burst(base, entry.color, tier.particles, folder)
	if emitterPart then
		table.insert(effects, emitterPart)
	end

	flash(entry.color, tier.flash)
	playSound(WIN_SOUND_IDS[entry.rarity])

	local start = os.clock()
	local connection = runService.RenderStepped:Connect(function()
		local elapsed = os.clock() - start
		local rise = math.min(elapsed / HOLOGRAM_RISE_SECONDS, 1)
		local eased = 1 - (1 - rise) ^ 3
		local height = 0.5 + (HOLOGRAM_HEIGHT - 0.5) * eased + math.sin(elapsed * 2.5) * HOLOGRAM_BOB * rise
		display.CFrame = base * CFrame.new(0, height, 0) * CFrame.Angles(0, elapsed * HOLOGRAM_SPIN, 0)
	end)

	task.delay(tier.seconds, function()
		fadeLabels(display)
		tweenService:Create(light, TweenInfo.new(FADE_SECONDS), { Brightness = 0 }):Play()
		task.wait(FADE_SECONDS)
		connection:Disconnect()
		for _, effect in effects do
			effect:Destroy()
		end
	end)
end

-- What other players near the podium see: a short "<name> rolled <ability>!" once the roller's reel would have landed.
function AbilityShackVFX.playSpectator(top: Vector3, rollerName: string, entry: Entry)
	task.delay(AbilityShackVFX.REEL_SECONDS, function()
		if spectatorAnchor then
			spectatorAnchor:Destroy()
		end

		local folder = getFolder()
		local start = CFrame.new(top + Vector3.new(0, HOLOGRAM_HEIGHT, 0))
		local anchor = makePart(Vector3.one * 0.2, start)
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(10, 1.6)
		billboard.LightInfluence = 0
		billboard.MaxDistance = 120
		billboard.Adornee = anchor
		billboard.Parent = anchor
		makeLabel(billboard, `{rollerName} rolled {entry.name}!`, entry.color, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))
		anchor.Parent = folder
		spectatorAnchor = anchor

		local tier = TIERS[entry.rarity] or TIERS.Common
		if tier.column then
			burst(CFrame.new(top), entry.color, math.floor(tier.particles / 4), anchor)
		end

		tweenService:Create(anchor, TweenInfo.new(SPECTATOR_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = start + Vector3.new(0, 2, 0),
		}):Play()
		task.wait(SPECTATOR_SECONDS - FADE_SECONDS)
		fadeLabels(billboard)
		task.wait(FADE_SECONDS)
		anchor:Destroy()
		if spectatorAnchor == anchor then
			spectatorAnchor = nil
		end
	end)
end

return AbilityShackVFX
