--!strict

--[[
	Special sheep shower themed 3D pieces over the screen in a ViewportFrame (Cotton Candy wool, gold coins, gems, clovers...): a sprinkle per hit, a shower when sheared bare.
	Some pieces fly at the camera and land "on the glass", then slide down and fade. Every piece is pooled; nothing renders while none are falling.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.SheepScreenEffects
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local settings = require(script.Parent.Settings)

--// Configs
local DISPLAY_ORDER = 3 -- over the HUD and world, under the damage numbers, windows and popups
local EFFECT_LAYER_ATTRIBUTE = "EffectLayer" -- TutorialClient leaves guis with this on
local SETTING_ID = "SheepScreenEffects"
local FOV = 70
local MAX_PIECES = 70 -- falling at once; a shower past this is cut short
local HIT_COOLDOWN = 0.22 -- seconds between per-hit sprinkles
local GRAVITY = 16 -- studs/s² pulling pieces down the screen
local MIN_DEPTH, MAX_DEPTH = 7, 13 -- studs in front of the camera pieces start at
local GLASS_DEPTH = 4.5 -- how close a piece that "lands on the screen" gets (closer covers too much of the view)
local GLASS_SCALE = 0.7 -- pieces that land on the glass are made this much smaller, since they end up so close
local GLASS_SLIDE_SPEED = 0.55 -- studs/s it slides down the glass
local GLASS_HOLD = 0.9 -- seconds it sits on the glass before fading
local FADE_SECONDS = 0.45
local PARK = CFrame.new(0, 0, 500) -- behind the camera, where idle pieces wait
local FLASH_IN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FLASH_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FLASH_TRANSPARENCY = 0.78

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Effect = {
	kinds: { string }, -- piece shapes, picked at random per piece (see BUILDERS)
	colors: { Color3 }, -- the palette the colourable parts take
	count: number, -- pieces in the shower when it's sheared bare
	hitCount: number, -- pieces per hit while it's being sheared
	stick: number, -- chance (0-1) a piece lands on the screen instead of falling past
	spin: number?, -- times the normal spin speed
	size: NumberRange?, -- model scale range
	flash: Color3?, -- a quick screen tint on the shower
}

-- Adult sheep type key -> its effect. Plain sheep (Basic, Grey, Brown, Black) have none, so the special ones stand out.
local EFFECTS: { [string]: Effect } = {
	CottonCandy = {
		kinds = { "puff" },
		colors = { rgb(255, 168, 214), rgb(166, 214, 255), rgb(222, 182, 255), rgb(255, 206, 236) },
		count = 30, hitCount = 3, stick = 0.6, spin = 0.5, size = NumberRange.new(0.9, 1.5), flash = rgb(255, 170, 215),
	},
	Fluffy = {
		kinds = { "puff" },
		colors = { rgb(255, 255, 255), rgb(250, 244, 230), rgb(240, 240, 248) },
		count = 18, hitCount = 2, stick = 0.5, spin = 0.5, size = NumberRange.new(0.9, 1.4),
	},
	Spotted = {
		kinds = { "puff" },
		colors = { rgb(255, 255, 255), rgb(30, 30, 34), rgb(245, 245, 245) },
		count = 22, hitCount = 2, stick = 0.5, spin = 0.5, flash = rgb(255, 255, 255),
	},
	Mustache = {
		kinds = { "mustache" },
		colors = { rgb(35, 25, 20), rgb(80, 50, 30), rgb(20, 20, 20) },
		count = 14, hitCount = 1, stick = 0.55, spin = 0.8,
	},
	Golden = {
		kinds = { "coin" },
		colors = { rgb(255, 205, 60), rgb(255, 222, 110), rgb(240, 180, 40) },
		count = 26, hitCount = 2, stick = 0.3, spin = 1.6, flash = rgb(255, 210, 80),
	},
	Emerald = {
		kinds = { "gem" },
		colors = { rgb(40, 210, 110), rgb(90, 240, 150), rgb(20, 160, 90) },
		count = 22, hitCount = 2, stick = 0.35, spin = 1.2, flash = rgb(60, 230, 130),
	},
	Ruby = {
		kinds = { "gem" },
		colors = { rgb(235, 40, 70), rgb(255, 90, 110), rgb(180, 20, 50) },
		count = 24, hitCount = 2, stick = 0.35, spin = 1.2, flash = rgb(240, 50, 80),
	},
	Diamond = {
		kinds = { "gem", "star" },
		colors = { rgb(150, 235, 255), rgb(220, 250, 255), rgb(100, 200, 255) },
		count = 30, hitCount = 2, stick = 0.4, spin = 1.4, flash = rgb(170, 240, 255),
	},
	Obsidian = {
		kinds = { "shard" },
		colors = { rgb(40, 20, 60), rgb(90, 40, 140), rgb(20, 15, 30) },
		count = 26, hitCount = 2, stick = 0.35, spin = 1.3, flash = rgb(120, 60, 200),
	},
	Lucky = {
		kinds = { "clover" },
		colors = { rgb(60, 200, 80), rgb(100, 230, 110), rgb(40, 160, 60) },
		count = 22, hitCount = 2, stick = 0.5, spin = 0.8, flash = rgb(90, 230, 110),
	},
	Ice = {
		kinds = { "flake", "gem" },
		colors = { rgb(200, 240, 255), rgb(150, 215, 255), rgb(255, 255, 255) },
		count = 26, hitCount = 2, stick = 0.55, spin = 0.7, flash = rgb(170, 230, 255),
	},
	Stone = {
		kinds = { "rock" },
		colors = { rgb(130, 130, 135), rgb(100, 100, 108), rgb(160, 155, 150) },
		count = 18, hitCount = 2, stick = 0.25, spin = 1,
	},
	Cactus = {
		kinds = { "cactus" },
		colors = { rgb(70, 170, 70), rgb(50, 140, 60), rgb(100, 190, 80) },
		count = 16, hitCount = 1, stick = 0.4, spin = 0.8,
	},
	Square = {
		kinds = { "cube" },
		colors = { rgb(255, 90, 90), rgb(255, 200, 60), rgb(90, 200, 255), rgb(140, 230, 110), rgb(200, 120, 255) },
		count = 24, hitCount = 2, stick = 0.4, spin = 1.1,
	},
	Rainbow = {
		kinds = { "puff", "star" },
		colors = { rgb(255, 80, 80), rgb(255, 160, 50), rgb(255, 230, 70), rgb(90, 220, 100), rgb(80, 170, 255), rgb(170, 100, 255) },
		count = 34, hitCount = 3, stick = 0.5, spin = 0.9, flash = rgb(255, 255, 255),
	},
	Ninja = {
		kinds = { "shuriken" },
		colors = { rgb(70, 70, 80), rgb(120, 120, 130), rgb(40, 40, 48) },
		count = 18, hitCount = 2, stick = 0.45, spin = 3,
	},
	Princess = {
		kinds = { "heart", "star" },
		colors = { rgb(255, 120, 190), rgb(255, 170, 215), rgb(255, 215, 90) },
		count = 28, hitCount = 2, stick = 0.5, spin = 0.8, flash = rgb(255, 150, 210),
	},
	Robot = {
		kinds = { "gear", "cube" },
		colors = { rgb(160, 170, 180), rgb(110, 120, 130), rgb(90, 200, 255) },
		count = 22, hitCount = 2, stick = 0.35, spin = 1.4, flash = rgb(90, 200, 255),
	},
	Wizard = {
		kinds = { "star" },
		colors = { rgb(150, 90, 255), rgb(90, 140, 255), rgb(255, 220, 90) },
		count = 28, hitCount = 2, stick = 0.4, spin = 1.2, flash = rgb(140, 90, 255),
	},
	Alien = {
		kinds = { "ufo" },
		colors = { rgb(110, 255, 120), rgb(70, 220, 90), rgb(160, 255, 170) },
		count = 16, hitCount = 1, stick = 0.35, spin = 0.9, flash = rgb(100, 255, 120),
	},
	Pumpkin = {
		kinds = { "pumpkin" },
		colors = { rgb(255, 140, 30), rgb(240, 120, 20), rgb(255, 165, 60) },
		count = 18, hitCount = 1, stick = 0.45, spin = 0.8, flash = rgb(255, 140, 40),
	},
	Mummy = {
		kinds = { "strip" },
		colors = { rgb(235, 225, 200), rgb(215, 205, 180), rgb(245, 240, 225) },
		count = 20, hitCount = 2, stick = 0.55, spin = 0.9,
	},
	Vampire = {
		kinds = { "drop" },
		colors = { rgb(150, 0, 20), rgb(200, 20, 40), rgb(110, 0, 15) },
		count = 22, hitCount = 2, stick = 0.65, spin = 0.4, flash = rgb(160, 0, 30),
	},
}

--// Piece builders ---------------------------------------------------------------------
-- Each builds a model around the origin and returns it, its parts (for fading) and the parts that take the palette colour.

type Built = { model: Model, parts: { BasePart }, colored: { BasePart } }

local function newPart(shape: Enum.PartType, size: Vector3, cframe: CFrame, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local FACE = CFrame.Angles(0, math.rad(90), 0) -- turns a cylinder's round face towards the camera
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder on end

local function assemble(colored: { BasePart }, fixed: { BasePart }?): Built
	local model = Instance.new("Model")
	local parts: { BasePart } = {}
	for _, part in colored do
		part.Parent = model
		table.insert(parts, part)
	end
	for _, part in fixed or {} do
		part.Parent = model
		table.insert(parts, part)
	end
	model.WorldPivot = CFrame.identity
	return { model = model, parts = parts, colored = colored }
end

local BUILDERS: { [string]: () -> Built } = {
	puff = function()
		return assemble({
			newPart(Enum.PartType.Ball, Vector3.one * 1, CFrame.identity),
			newPart(Enum.PartType.Ball, Vector3.one * 0.72, CFrame.new(0.45, -0.12, 0.1)),
			newPart(Enum.PartType.Ball, Vector3.one * 0.68, CFrame.new(-0.42, -0.08, -0.05)),
			newPart(Enum.PartType.Ball, Vector3.one * 0.6, CFrame.new(0.05, 0.35, 0.15)),
		})
	end,
	coin = function()
		return assemble({ newPart(Enum.PartType.Cylinder, Vector3.new(0.16, 1.1, 1.1), FACE, Enum.Material.Metal) })
	end,
	gem = function()
		return assemble({ newPart(Enum.PartType.Block, Vector3.one * 0.75, CFrame.Angles(math.rad(45), 0, math.rad(45)), Enum.Material.Glass) })
	end,
	shard = function()
		local wedge = Instance.new("WedgePart")
		wedge.Size = Vector3.new(0.25, 1.3, 0.6)
		wedge.Material = Enum.Material.Glass
		wedge.Anchored, wedge.CanCollide, wedge.CanQuery, wedge.CanTouch, wedge.CastShadow = true, false, false, false, false
		return assemble({ wedge })
	end,
	clover = function()
		local leaves = {}
		for _, offset in { Vector2.new(0.27, 0.27), Vector2.new(-0.27, 0.27), Vector2.new(0.27, -0.27), Vector2.new(-0.27, -0.27) } do
			table.insert(leaves, newPart(Enum.PartType.Cylinder, Vector3.new(0.1, 0.6, 0.6), CFrame.new(offset.X, offset.Y, 0) * FACE))
		end
		local stem = newPart(Enum.PartType.Block, Vector3.new(0.09, 0.55, 0.09), CFrame.new(0.12, -0.6, 0) * CFrame.Angles(0, 0, math.rad(-20)))
		stem.Color = rgb(40, 120, 45)
		return assemble(leaves, { stem })
	end,
	pumpkin = function()
		local stem = newPart(Enum.PartType.Cylinder, Vector3.new(0.35, 0.16, 0.16), CFrame.new(0, 0.6, 0) * UPRIGHT)
		stem.Color = rgb(60, 120, 40)
		return assemble({ newPart(Enum.PartType.Ball, Vector3.one * 1.1, CFrame.identity) }, { stem })
	end,
	flake = function()
		local arms = {}
		for index = 0, 2 do
			table.insert(arms, newPart(Enum.PartType.Block, Vector3.new(1.2, 0.11, 0.08), CFrame.Angles(0, 0, math.rad(60 * index)), Enum.Material.Neon))
		end
		return assemble(arms)
	end,
	strip = function()
		return assemble({ newPart(Enum.PartType.Block, Vector3.new(1.5, 0.32, 0.05), CFrame.identity, Enum.Material.Fabric) })
	end,
	drop = function()
		return assemble({
			newPart(Enum.PartType.Ball, Vector3.one * 0.6, CFrame.identity),
			newPart(Enum.PartType.Block, Vector3.one * 0.38, CFrame.new(0, 0.22, 0) * CFrame.Angles(0, 0, math.rad(45))),
		})
	end,
	rock = function()
		return assemble({ newPart(Enum.PartType.Block, Vector3.new(0.9, 0.7, 0.8), CFrame.Angles(0.3, 0.6, 0.2), Enum.Material.Slate) })
	end,
	mustache = function()
		return assemble({
			newPart(Enum.PartType.Block, Vector3.new(0.7, 0.22, 0.15), CFrame.new(0.3, 0, 0) * CFrame.Angles(0, 0, math.rad(18))),
			newPart(Enum.PartType.Block, Vector3.new(0.7, 0.22, 0.15), CFrame.new(-0.3, 0, 0) * CFrame.Angles(0, 0, math.rad(-18))),
			newPart(Enum.PartType.Ball, Vector3.one * 0.26, CFrame.new(0.66, 0.14, 0)),
			newPart(Enum.PartType.Ball, Vector3.one * 0.26, CFrame.new(-0.66, 0.14, 0)),
		})
	end,
	cactus = function()
		return assemble({
			newPart(Enum.PartType.Cylinder, Vector3.new(1.1, 0.4, 0.4), UPRIGHT),
			newPart(Enum.PartType.Cylinder, Vector3.new(0.4, 0.22, 0.22), CFrame.new(0.32, 0.12, 0) * UPRIGHT),
			newPart(Enum.PartType.Cylinder, Vector3.new(0.35, 0.22, 0.22), CFrame.new(-0.32, -0.05, 0) * UPRIGHT),
		})
	end,
	cube = function()
		return assemble({ newPart(Enum.PartType.Block, Vector3.one * 0.75, CFrame.identity) })
	end,
	shuriken = function()
		return assemble({
			newPart(Enum.PartType.Block, Vector3.new(1.2, 0.24, 0.05), CFrame.Angles(0, 0, math.rad(45)), Enum.Material.Metal),
			newPart(Enum.PartType.Block, Vector3.new(1.2, 0.24, 0.05), CFrame.Angles(0, 0, math.rad(-45)), Enum.Material.Metal),
		})
	end,
	heart = function()
		local side = 0.62
		local edge = side / (2 * math.sqrt(2))
		return assemble({
			newPart(Enum.PartType.Block, Vector3.new(side, side, 0.2), CFrame.Angles(0, 0, math.rad(45))),
			newPart(Enum.PartType.Ball, Vector3.one * side, CFrame.new(-edge, edge, 0)),
			newPart(Enum.PartType.Ball, Vector3.one * side, CFrame.new(edge, edge, 0)),
		})
	end,
	star = function()
		return assemble({
			newPart(Enum.PartType.Block, Vector3.new(0.7, 0.7, 0.14), CFrame.identity, Enum.Material.Neon),
			newPart(Enum.PartType.Block, Vector3.new(0.7, 0.7, 0.14), CFrame.Angles(0, 0, math.rad(45)), Enum.Material.Neon),
		})
	end,
	gear = function()
		local parts = { newPart(Enum.PartType.Cylinder, Vector3.new(0.2, 0.9, 0.9), FACE, Enum.Material.Metal) }
		for index = 0, 5 do
			local angle = math.rad(60 * index)
			table.insert(parts, newPart(Enum.PartType.Block, Vector3.new(0.24, 0.24, 0.18),
				CFrame.new(math.cos(angle) * 0.5, math.sin(angle) * 0.5, 0) * CFrame.Angles(0, 0, angle), Enum.Material.Metal))
		end
		return assemble(parts)
	end,
	ufo = function()
		local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.22, 1.3, 1.3), UPRIGHT, Enum.Material.Metal)
		disc.Color = rgb(170, 175, 185)
		return assemble({ newPart(Enum.PartType.Ball, Vector3.one * 0.6, CFrame.new(0, 0.18, 0), Enum.Material.Glass) }, { disc })
	end,
}

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "SheepScreenEffects"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = DISPLAY_ORDER
gui:SetAttribute(EFFECT_LAYER_ATTRIBUTE, true)
gui.Parent = playerGui

local flashFrame = Instance.new("Frame")
flashFrame.Name = "Flash"
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BorderSizePixel = 0
flashFrame.BackgroundTransparency = 1
flashFrame.Active = false
flashFrame.Parent = gui

local viewport = Instance.new("ViewportFrame")
viewport.Name = "Pieces"
viewport.Size = UDim2.fromScale(1, 1)
viewport.BackgroundTransparency = 1
viewport.Ambient = rgb(190, 190, 200)
viewport.LightColor = rgb(255, 255, 255)
viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
viewport.Visible = false
viewport.ZIndex = 2
viewport.Parent = gui

local camera = Instance.new("Camera")
camera.FieldOfView = FOV
camera.CFrame = CFrame.identity -- looking down -Z, so a piece's world position is its camera-space position
camera.Parent = viewport
viewport.CurrentCamera = camera

--// State
type Piece = {
	kind: string,
	built: Built,
	active: boolean,
	position: Vector3,
	velocity: Vector3,
	rotation: CFrame,
	spinAxis: Vector3,
	spinSpeed: number,
	sticks: boolean,
	startAt: number, -- waits parked until then, so a shower comes in over a moment rather than all at once
	stuckAt: number?, -- when it landed on the glass
	fadeAt: number?,
}

local idle: { [string]: { Piece } } = {}
local active: { Piece } = {}
local renderConnection: RBXScriptConnection? = nil
local lastHitAt = 0
local flashTween: Tween? = nil
local random = Random.new()

local SheepScreenEffects = {}

--// Pieces ------------------------------------------------------------------------------

local function acquire(kind: string): Piece?
	local list = idle[kind]
	local piece = list and table.remove(list)
	if piece then
		return piece
	end
	local builder = BUILDERS[kind]
	if not builder then
		return nil
	end
	local built = builder()
	built.model:PivotTo(PARK)
	built.model.Parent = viewport
	return {
		kind = kind,
		built = built,
		active = false,
		position = Vector3.zero,
		velocity = Vector3.zero,
		rotation = CFrame.identity,
		spinAxis = Vector3.yAxis,
		spinSpeed = 0,
		sticks = false,
		startAt = 0,
		stuckAt = nil,
		fadeAt = nil,
	}
end

local function release(piece: Piece)
	piece.active = false
	piece.built.model:PivotTo(PARK)
	local list = idle[piece.kind]
	if not list then
		list = {}
		idle[piece.kind] = list
	end
	table.insert(list, piece)
end

local function setTransparency(piece: Piece, transparency: number)
	for _, part in piece.built.parts do
		part.Transparency = transparency
	end
end

-- Half the visible width and height `depth` studs in front of the camera.
local function getHalfExtents(depth: number): (number, number)
	local size = viewport.AbsoluteSize
	local halfHeight = depth * math.tan(math.rad(FOV / 2))
	local aspect = if size.Y > 0 then size.X / size.Y else 16 / 9
	return halfHeight * aspect, halfHeight
end

local function spawnPiece(effect: Effect, now: number, delay: number)
	if #active >= MAX_PIECES then
		return
	end
	local kind = effect.kinds[random:NextInteger(1, #effect.kinds)]
	local piece = acquire(kind)
	if not piece then
		return
	end

	local color = effect.colors[random:NextInteger(1, #effect.colors)]
	for _, part in piece.built.colored do
		part.Color = color
	end
	setTransparency(piece, 0)

	piece.sticks = random:NextNumber() < effect.stick
	local sizeRange = effect.size or NumberRange.new(0.8, 1.25)
	local scale = random:NextNumber(sizeRange.Min, sizeRange.Max) * (if piece.sticks then GLASS_SCALE else 1)
	if math.abs(piece.built.model:GetScale() - scale) > 0.01 then
		piece.built.model:ScaleTo(scale)
	end

	local depth = random:NextNumber(MIN_DEPTH, MAX_DEPTH)
	local halfWidth, halfHeight = getHalfExtents(depth)
	if piece.sticks then
		-- Flies in from the distance straight at a spot on the glass, starting a little above where it lands on screen.
		local glassWidth, glassHeight = getHalfExtents(GLASS_DEPTH)
		local target = Vector3.new(random:NextNumber(-0.85, 0.85) * glassWidth, random:NextNumber(-0.5, 0.85) * glassHeight, -GLASS_DEPTH)
		local far = depth / GLASS_DEPTH
		local start = Vector3.new(target.X * far, target.Y * far + random:NextNumber(1.5, 3), -depth)
		piece.position = start
		piece.velocity = (target - start) / random:NextNumber(0.45, 0.75)
	else
		piece.position = Vector3.new(random:NextNumber(-halfWidth, halfWidth) * 0.95, halfHeight + 1.2, -depth)
		piece.velocity = Vector3.new(random:NextNumber(-1.5, 1.5), -random:NextNumber(2, 5), 0)
	end
	piece.startAt = now + delay
	piece.rotation = CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), random:NextNumber(0, 6.28))
	piece.spinAxis = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)).Unit
	piece.spinSpeed = random:NextNumber(1.5, 4) * (effect.spin or 1)
	piece.stuckAt = nil
	piece.fadeAt = nil
	piece.active = true
	table.insert(active, piece)
end

local function step(deltaTime: number)
	local now = os.clock()
	local dt = math.min(deltaTime, 1 / 20)

	for index = #active, 1, -1 do
		local piece = active[index]
		local remove = false

		if now < piece.startAt then
			continue
		elseif piece.stuckAt then
			-- On the glass: slides slowly down, then fades.
			piece.position += Vector3.new(0, -GLASS_SLIDE_SPEED * dt, 0)
			if not piece.fadeAt and now - piece.stuckAt >= GLASS_HOLD then
				piece.fadeAt = now
			end
		else
			if not piece.sticks then
				piece.velocity += Vector3.new(0, -GRAVITY * dt, 0)
			end
			piece.position += piece.velocity * dt
			piece.rotation = piece.rotation * CFrame.fromAxisAngle(piece.spinAxis, piece.spinSpeed * dt)
			if piece.sticks and -piece.position.Z <= GLASS_DEPTH then
				piece.position = Vector3.new(piece.position.X, piece.position.Y, -GLASS_DEPTH)
				piece.stuckAt = now
			end
			local _, halfHeight = getHalfExtents(-piece.position.Z)
			if piece.position.Y < -halfHeight - 2 then
				remove = true
			end
		end

		if piece.fadeAt then
			local fade = (now - piece.fadeAt) / FADE_SECONDS
			if fade >= 1 then
				remove = true
			else
				setTransparency(piece, fade)
			end
		end

		if remove then
			active[index] = active[#active]
			active[#active] = nil
			release(piece)
		else
			piece.built.model:PivotTo(CFrame.new(piece.position) * piece.rotation)
		end
	end

	if #active == 0 and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
		viewport.Visible = false
	end
end

local function start(effect: Effect, count: number, spread: number)
	local now = os.clock()
	for index = 1, count do
		spawnPiece(effect, now, spread * (index - 1) / math.max(count, 1))
	end
	if #active > 0 and not renderConnection then
		viewport.Visible = true
		renderConnection = runService.RenderStepped:Connect(step)
	end
end

local function flash(color: Color3)
	if flashTween then
		flashTween:Cancel()
	end
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1
	local fadeIn = tweenService:Create(flashFrame, FLASH_IN, { BackgroundTransparency = FLASH_TRANSPARENCY })
	fadeIn.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			local fadeOut = tweenService:Create(flashFrame, FLASH_OUT, { BackgroundTransparency = 1 })
			flashTween = fadeOut
			fadeOut:Play()
		end
	end)
	flashTween = fadeIn
	fadeIn:Play()
end

--// Public API --------------------------------------------------------------------------

function SheepScreenEffects.has(sheepType: string?): boolean
	return sheepType ~= nil and EFFECTS[sheepType] ~= nil
end

-- A few pieces for one hit on a special sheep (at most one sprinkle every HIT_COOLDOWN).
function SheepScreenEffects.playHit(sheepType: string?)
	local effect = if sheepType then EFFECTS[sheepType] else nil
	local now = os.clock()
	if not effect or not settings.get(SETTING_ID) or now - lastHitAt < HIT_COOLDOWN then
		return
	end
	lastHitAt = now
	start(effect, settings.effectCount(effect.hitCount), 0.1)
end

-- The full shower (and screen tint) for shearing a special sheep bare; `multiplier` grows it (rare finds, mutations).
function SheepScreenEffects.playFinish(sheepType: string?, multiplier: number?)
	local effect = if sheepType then EFFECTS[sheepType] else nil
	if not effect or not settings.get(SETTING_ID) then
		return
	end
	start(effect, settings.effectCount(math.floor(effect.count * (multiplier or 1) + 0.5)), 0.7)
	if effect.flash then
		flash(effect.flash)
	end
end

-- Builds a few of each piece now, so the first shower doesn't hitch.
task.defer(function()
	for kind in BUILDERS do
		for _ = 1, 2 do
			local piece = acquire(kind)
			if piece then
				release(piece)
			end
		end
		task.wait()
	end
end)

return SheepScreenEffects
