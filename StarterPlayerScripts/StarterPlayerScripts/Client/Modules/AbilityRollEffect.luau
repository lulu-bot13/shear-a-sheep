--!strict

--[[
	The Ability Shack roll carousel: on a darkened screen, name cards scroll downward past an arrow, land on the rarest result with rays and a glow, and 5X rolls pop in the other four cards.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.AbilityRollEffect
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Configs
local FONT_FAMILY = "rbxasset://fonts/families/SourceSansPro.json"
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local POINTER_IMAGE = "rbxassetid://133131800619707"

local GUI_NAME = "AbilityRollEffect"
local STAGE_W, STAGE_H = 12, 14 -- studs on a spectator's billboard; the aspect ratio on the roller's screen
local STAGE_SCREEN_HEIGHT = 0.85 -- of the screen
local DISPLAY_ORDER = 20
local DIM_TRANSPARENCY = 0.35
local DIM_SECONDS = 0.25
local SPECTATOR_OFFSET = Vector3.new(0, 7, 0)
local SPECTATOR_MAX_DISTANCE = 150

-- Layout, as fractions of the stage
local REEL_X, REEL_Y = 0.5, 0.42 -- the centre slot
local CARD_W, CARD_H = 0.44, 0.16
local NAME_POS, NAME_SIZE = UDim2.fromScale(0.5, 0.38), UDim2.fromScale(0.9, 0.5)
local RARITY_POS, RARITY_SIZE = UDim2.fromScale(0.5, 0.76), UDim2.fromScale(0.8, 0.3)
local POINTER_POS, POINTER_SIZE, POINTER_ROTATION = UDim2.fromScale(0.83, REEL_Y), 0.09, 180
local POINTER_NUDGE = 0.03 -- how far the arrow jabs toward the card on landing
local TAG_POS, TAG_SIZE = UDim2.fromScale(0.5, 0.83), UDim2.fromScale(0.8, 0.05)
local SMALL_Y, SMALL_SCALE, SMALL_X = 0.94, 0.45, { -0.33, -0.11, 0.11, 0.33 }

-- Slot 0 is the card leaving at the bottom and slot 6 the one waiting at the top; 1 to 5 are on screen.
type Slot = { y: number, scale: number, alpha: number }
local SLOTS: { [number]: Slot } = {
	[0] = { y = REEL_Y + 0.42, scale = 0.3, alpha = 1 },
	[1] = { y = REEL_Y + 0.31, scale = 0.4, alpha = 0.95 },
	[2] = { y = REEL_Y + 0.17, scale = 0.6, alpha = 0.45 },
	[3] = { y = REEL_Y, scale = 1, alpha = 0 },
	[4] = { y = REEL_Y - 0.17, scale = 0.6, alpha = 0.45 },
	[5] = { y = REEL_Y - 0.31, scale = 0.4, alpha = 0.95 },
	[6] = { y = REEL_Y - 0.42, scale = 0.3, alpha = 1 },
}
local CENTER_SLOT = 3

-- Spin timing
local ROLL_TICKS = 26
local SPECTATOR_TICKS = 10
local TICK_FIRST = 0.05
local TICK_LAST = 0.45
local TICK_EASE_POWER = 3
local INTRO_SECONDS = 0.25
local SPIN_PITCH_START, SPIN_PITCH_END = 0.9, 1.3
local POP_POOL_SIZE = 4

-- Landing
local LAND_POP_SCALE, LAND_POP_SECONDS = 1.35, 0.15
local LAND_SETTLE_SCALE, LAND_SETTLE_SECONDS = 1.15, 0.35
local LAND_FADE_SECONDS = 0.25
local BURST_TRANSPARENCY = 0.1
local RAY_COUNT, RAY_SPIN_DEGREES, RAY_RADIUS = 12, 40, 0.3 -- radius as a fraction of the stage height
local GLOW_RADIUS = 0.2
local SHAKE_SECONDS, SHAKE_MAGNITUDE = 0.6, 0.6
local SMALL_START_DELAY, SMALL_STAGGER, SMALL_POP_SECONDS = 0.5, 0.18, 0.35
local HOLD_SECONDS, SPECTATOR_HOLD_SECONDS = 2, 1.2
local FADE_SECONDS = 0.4
local HARD_TIMEOUT = 25

-- Speed streaks
local STREAK_X = { 0.2, 0.5, 0.8 }
local STREAK_SPEEDS = { 1.4, 2, 1.1 }
local STREAK_SIZE = UDim2.fromScale(0.012, 0.3)
local STREAK_FADE_INTERVAL = 0.25 -- tick length at which the streaks have fully vanished
local STREAK_MAX_OPACITY = 0.8

local LEGENDARY_RARITIES: { [string]: boolean } = { Legendary = true, Mythic = true }
local CANCELLED = "AbilityRollEffect cancelled"

--// Types
export type Entry = { id: string, name: string, rarity: string, color: Color3, chance: number, icon: string? }
export type Item = { entry: Entry, isNew: boolean, refund: number }

type Card = {
	holder: Frame,
	scale: UIScale,
	alpha: NumberValue,
	frame: Frame,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	strokes: { UIStroke },
}

type Streak = { frame: Frame, y: number, speed: number }

type Effect = {
	gui: LayerCollector,
	stage: Frame,
	dim: Frame?,
	character: Model?,
	humanoid: Humanoid?,
	owner: Player?,
	isLocal: boolean,
	alive: boolean,
	startedAt: number,
	interval: number,
	spinning: boolean,
	landed: boolean,
	baseCameraOffset: Vector3,
	shakeUntil: number,
	shaking: boolean,
	rayContainer: Frame?,
	streaks: { Streak },
	connections: { RBXScriptConnection },
	tweens: { Tween },
}

--// State
local random = Random.new()
local effects: { [Effect]: boolean } = {}
local spectators: { [Model]: Effect } = {}
local localEffect: Effect? = nil
local popPool: { Sound } = {}
local popIndex = 0

local AbilityRollEffect = {}

--// Sounds ----------------------------------------------------------------------

local function findUISound(name: string): Sound?
	local folder = soundService:FindFirstChild("UISounds")
	local sound = folder and folder:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

-- Pop is cloned a few times so quick ticks can overlap.
local function playTick(speed: number)
	local first = popPool[1]
	if not first or not first.Parent then
		for _, old in popPool do
			old:Destroy()
		end
		table.clear(popPool)
		local template = findUISound("Pop")
		if not template then
			return
		end
		for _ = 1, POP_POOL_SIZE do
			local clone = template:Clone()
			clone.Parent = soundService
			table.insert(popPool, clone)
		end
	end

	popIndex = popIndex % #popPool + 1
	local sound = popPool[popIndex]
	sound.PlaybackSpeed = speed
	sound:Play()
end

local function playUISound(name: string)
	local sound = findUISound(name)
	if sound then
		sound:Play()
	end
end

--// Building blocks -------------------------------------------------------------

local function makeStroke(parent: Instance, thickness: number, contextual: boolean): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = STROKE_COLOR
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function makeLabel(parent: Instance, weight: Enum.FontWeight, size: UDim2, position: UDim2): (TextLabel, UIStroke)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new(FONT_FAMILY, weight)
	label.TextColor3 = TEXT_COLOR
	label.TextScaled = true
	label.Text = ""
	label.Size = size
	label.Position = position
	local stroke = makeStroke(label, 2, true)
	label.Parent = parent
	return label, stroke
end

local function squareSize(heightFraction: number): UDim2
	return UDim2.fromScale(heightFraction * STAGE_H / STAGE_W, heightFraction)
end

local function applyAlpha(card: Card, alpha: number)
	card.frame.BackgroundTransparency = alpha
	card.nameLabel.TextTransparency = alpha
	card.rarityLabel.TextTransparency = alpha
	for _, stroke in card.strokes do
		stroke.Transparency = alpha
	end
end

local function createCard(parent: Instance): Card
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(CARD_W, CARD_H)

	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.14, 0)
	corner.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(125, 125, 125))
	gradient.Parent = frame
	local frameStroke = makeStroke(frame, 3, false)

	local nameLabel, nameStroke = makeLabel(frame, Enum.FontWeight.ExtraBold, NAME_SIZE, NAME_POS)
	local rarityLabel, rarityStroke = makeLabel(frame, Enum.FontWeight.Bold, RARITY_SIZE, RARITY_POS)

	local alpha = Instance.new("NumberValue")
	alpha.Parent = holder
	holder.Parent = parent

	local card: Card = {
		holder = holder,
		scale = scale,
		alpha = alpha,
		frame = frame,
		nameLabel = nameLabel,
		rarityLabel = rarityLabel,
		strokes = { frameStroke, nameStroke, rarityStroke },
	}
	alpha.Changed:Connect(function(value: number)
		applyAlpha(card, value)
	end)
	return card
end

local function setCard(card: Card, entry: Entry)
	card.frame.BackgroundColor3 = entry.color
	card.nameLabel.Text = entry.name
	card.rarityLabel.Text = entry.rarity
end

local function snapCard(card: Card, slotIndex: number)
	local slot = SLOTS[slotIndex]
	card.holder.Position = UDim2.fromScale(REEL_X, slot.y)
	card.holder.ZIndex = 5 - math.abs(slotIndex - CENTER_SLOT)
	card.scale.Scale = slot.scale
	card.alpha.Value = slot.alpha
end

--// Effect lifecycle ------------------------------------------------------------

local function track(effect: Effect, instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = tweenService:Create(instance, info, goals)
	table.insert(effect.tweens, tween)
	tween:Play()
	return tween
end

local function pruneTweens(effect: Effect)
	local kept: { Tween } = {}
	for _, tween in effect.tweens do
		if tween.PlaybackState == Enum.PlaybackState.Playing or tween.PlaybackState == Enum.PlaybackState.Begin then
			table.insert(kept, tween)
		end
	end
	effect.tweens = kept
end

local function cleanup(effect: Effect)
	if not effect.alive then
		return
	end
	effect.alive = false
	effects[effect] = nil
	if localEffect == effect then
		localEffect = nil
	end
	local character = effect.character
	if character and spectators[character] == effect then
		spectators[character] = nil
	end

	for _, connection in effect.connections do
		connection:Disconnect()
	end
	table.clear(effect.connections)
	for _, tween in effect.tweens do
		tween:Cancel()
	end
	table.clear(effect.tweens)

	local humanoid = effect.humanoid
	if effect.shaking and humanoid and humanoid.Parent then
		humanoid.CameraOffset = effect.baseCameraOffset
	end
	effect.gui:Destroy()
end

-- Every yield in the animation goes through here, so a cleanup or the timeout always unwinds it.
local function waitEffect(effect: Effect, seconds: number)
	local finish = os.clock() + seconds
	repeat
		task.wait(math.clamp(finish - os.clock(), 0, 0.25))
		if not effect.alive or os.clock() - effect.startedAt > HARD_TIMEOUT then
			error(CANCELLED)
		end
	until os.clock() >= finish
end

local function onHeartbeat(effect: Effect, dt: number)
	local visibility = 0
	if effect.spinning then
		visibility = math.clamp((STREAK_FADE_INTERVAL - effect.interval) / (STREAK_FADE_INTERVAL - TICK_FIRST), 0, 1)
	end
	for _, streak in effect.streaks do
		streak.y += dt * streak.speed * (0.25 + visibility)
		if streak.y > 1.3 then
			streak.y = -0.3
		end
		streak.frame.Position = UDim2.fromScale(streak.frame.Position.X.Scale, streak.y)
		streak.frame.BackgroundTransparency = 1 - visibility * STREAK_MAX_OPACITY
	end

	local rays = effect.rayContainer
	if rays and effect.landed then
		rays.Rotation = (rays.Rotation + dt * RAY_SPIN_DEGREES) % 360
	end

	local humanoid = effect.humanoid
	if humanoid then
		local remaining = effect.shakeUntil - os.clock()
		if remaining > 0 then
			effect.shaking = true
			local strength = SHAKE_MAGNITUDE * remaining / SHAKE_SECONDS
			humanoid.CameraOffset = effect.baseCameraOffset
				+ Vector3.new((random:NextNumber() - 0.5) * 2, (random:NextNumber() - 0.5) * 2, 0) * strength
		elseif effect.shaking then
			effect.shaking = false
			humanoid.CameraOffset = effect.baseCameraOffset
		end
	end
end

-- The roller's carousel fills their screen over a dark overlay; a spectator's floats above the roller.
local function createGui(isLocal: boolean, root: BasePart?): (LayerCollector, Frame, Frame?)
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1

	if isLocal then
		local screen = Instance.new("ScreenGui")
		screen.Name = GUI_NAME
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = DISPLAY_ORDER
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.Active = true
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 1
		dim.BorderSizePixel = 0
		dim.Size = UDim2.fromScale(1, 1)
		dim.Parent = screen

		stage.AnchorPoint = Vector2.new(0.5, 0.5)
		stage.Position = UDim2.fromScale(0.5, 0.5)
		stage.Size = UDim2.fromScale(1, STAGE_SCREEN_HEIGHT)
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = STAGE_W / STAGE_H
		aspect.DominantAxis = Enum.DominantAxis.Height
		aspect.Parent = stage
		stage.Parent = screen
		return screen, stage, dim
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = GUI_NAME
	billboard.Adornee = root
	billboard.Size = UDim2.fromScale(STAGE_W, STAGE_H)
	billboard.StudsOffset = SPECTATOR_OFFSET
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.ClipsDescendants = false
	billboard.MaxDistance = SPECTATOR_MAX_DISTANCE
	billboard.Active = false
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	stage.Size = UDim2.fromScale(1, 1)
	stage.Parent = billboard
	return billboard, stage, nil
end

local function createEffect(character: Model?, root: BasePart?, isLocal: boolean): Effect
	local gui, stage, dim = createGui(isLocal, root)
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local effect: Effect = {
		gui = gui,
		stage = stage,
		dim = dim,
		character = character,
		humanoid = humanoid,
		owner = if character then players:GetPlayerFromCharacter(character) else players.LocalPlayer,
		isLocal = isLocal,
		alive = true,
		startedAt = os.clock(),
		interval = TICK_FIRST,
		spinning = true,
		landed = false,
		baseCameraOffset = if humanoid then humanoid.CameraOffset else Vector3.zero,
		shakeUntil = 0,
		shaking = false,
		rayContainer = nil,
		streaks = {},
		connections = {},
		tweens = {},
	}

	local function kill()
		cleanup(effect)
	end
	if character then
		table.insert(effect.connections, character.AncestryChanged:Connect(function()
			if not character:IsDescendantOf(workspace) then
				kill()
			end
		end))
	end
	table.insert(effect.connections, gui.Destroying:Connect(kill))
	if humanoid then
		table.insert(effect.connections, humanoid.Died:Connect(kill))
	end
	table.insert(effect.connections, runService.Heartbeat:Connect(function(dt: number)
		onHeartbeat(effect, dt)
	end))

	effects[effect] = true
	if isLocal then
		localEffect = effect
		gui.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
	else
		spectators[character :: Model] = effect
		gui.Parent = root
	end
	return effect
end

--// Animation -------------------------------------------------------------------

-- Weighted-random rollable entries; index `ticks + 4` is the landed one, which is what the centre shows after the last tick.
local function buildStrip(pool: { Entry }, landed: Entry, ticks: number): { Entry }
	local rollable: { Entry } = {}
	local total = 0
	for _, entry in pool do
		if entry.chance > 0 then
			table.insert(rollable, entry)
			total += entry.chance
		end
	end
	if #rollable == 0 then
		rollable[1] = landed
		total = 1
	end

	local function pick(avoidA: Entry?, avoidB: Entry?): Entry
		local function ok(entry: Entry): boolean
			return not (avoidA and avoidA.id == entry.id) and not (avoidB and avoidB.id == entry.id)
		end
		for _ = 1, 8 do
			local roll = random:NextNumber() * total
			for _, entry in rollable do
				roll -= entry.chance
				if roll <= 0 then
					if ok(entry) then
						return entry
					end
					break
				end
			end
		end
		for _, entry in rollable do
			if ok(entry) then
				return entry
			end
		end
		return rollable[1]
	end

	local landedIndex = ticks + 4
	local strip: { Entry } = {}
	for index = 1, ticks + 7 do
		if index == landedIndex then
			strip[index] = landed
		else
			local nextToLanded = index == landedIndex - 1 or index == landedIndex + 1
			strip[index] = pick(strip[index - 1], if nextToLanded then landed else nil)
		end
	end
	return strip
end

local function animate(effect: Effect, pool: { Entry }, items: { Item })
	local isLocal = effect.isLocal

	local landedItem = items[1]
	for index = 2, #items do
		if items[index].entry.chance < landedItem.entry.chance then
			landedItem = items[index]
		end
	end
	local landed = landedItem.entry
	local ticks = if isLocal then ROLL_TICKS else SPECTATOR_TICKS
	local strip = buildStrip(pool, landed, ticks)

	--// Stage layers
	local stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromScale(1, 1)
	local introScale = Instance.new("UIScale")
	introScale.Scale = 0
	introScale.Parent = stage
	stage.Parent = effect.stage

	local backdrop = Instance.new("Frame")
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 1
	backdrop.Parent = stage

	for index, x in STREAK_X do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = Color3.new(1, 1, 1)
		frame.BackgroundTransparency = 1
		frame.Size = STREAK_SIZE
		local y = random:NextNumber() * 1.6 - 0.3
		frame.Position = UDim2.fromScale(x, y)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = frame
		frame.Parent = backdrop
		table.insert(effect.streaks, { frame = frame, y = y, speed = STREAK_SPEEDS[index] })
	end

	-- Glow and spinning rays behind the landed card, hidden until the landing.
	local burst = Instance.new("CanvasGroup")
	burst.BackgroundTransparency = 1
	burst.Size = UDim2.fromScale(1, 1)
	burst.GroupTransparency = 1
	burst.ZIndex = 2
	burst.Parent = backdrop

	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.BorderSizePixel = 0
	glow.Position = UDim2.fromScale(REEL_X, REEL_Y)
	glow.Size = squareSize(GLOW_RADIUS * 2)
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow
	local glowGradient = Instance.new("UIGradient")
	glowGradient.Rotation = 90
	glowGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.85),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	glowGradient.Parent = glow
	glow.Parent = burst

	local rayContainer = Instance.new("Frame")
	rayContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	rayContainer.BackgroundTransparency = 1
	rayContainer.Position = UDim2.fromScale(REEL_X, REEL_Y)
	rayContainer.Size = squareSize(RAY_RADIUS * 2)
	rayContainer.Parent = burst
	effect.rayContainer = rayContainer
	local rays: { Frame } = {}
	for index = 1, RAY_COUNT do
		local spoke = Instance.new("Frame")
		spoke.AnchorPoint = Vector2.new(0.5, 0.5)
		spoke.BackgroundTransparency = 1
		spoke.Position = UDim2.fromScale(0.5, 0.5)
		spoke.Size = UDim2.fromScale(1, 1)
		spoke.Rotation = (index - 1) * 360 / RAY_COUNT
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.BorderSizePixel = 0
		ray.Position = UDim2.fromScale(0.5, 0.2)
		ray.Size = UDim2.fromScale(0.035, 0.4)
		local rayGradient = Instance.new("UIGradient")
		rayGradient.Rotation = 90
		rayGradient.Transparency = NumberSequence.new(1, 0.1)
		rayGradient.Parent = ray
		ray.Parent = spoke
		spoke.Parent = rayContainer
		table.insert(rays, ray)
	end

	--// Cards
	local order: { Card } = {}
	for slotIndex = 0, 6 do
		local card = createCard(stage)
		setCard(card, strip[slotIndex + 1])
		snapCard(card, slotIndex)
		table.insert(order, card)
	end

	local smalls: { Card } = {}
	if #items > 1 then
		local slot = 1
		for _, item in items do
			if item ~= landedItem then
				local small = createCard(stage)
				setCard(small, item.entry)
				small.holder.Position = UDim2.fromScale(0.5 + SMALL_X[slot], SMALL_Y)
				small.holder.ZIndex = 5
				small.scale.Scale = 0
				small.alpha.Value = 0
				table.insert(smalls, small)
				slot += 1
			end
		end
	end

	--// Overlay: arrow and tag sit above the cards
	local overlay = Instance.new("CanvasGroup")
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 10
	overlay.Parent = stage

	local pointer = Instance.new("ImageLabel")
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.BackgroundTransparency = 1
	pointer.Image = POINTER_IMAGE
	pointer.Rotation = POINTER_ROTATION
	pointer.Position = POINTER_POS
	pointer.Size = squareSize(POINTER_SIZE)
	pointer.Parent = overlay
	local pointerScale = Instance.new("UIScale")
	pointerScale.Parent = pointer

	local tagGroup = Instance.new("CanvasGroup")
	tagGroup.BackgroundTransparency = 1
	tagGroup.AnchorPoint = Vector2.new(0.5, 0.5)
	tagGroup.Position = TAG_POS
	tagGroup.Size = TAG_SIZE
	tagGroup.GroupTransparency = 1
	tagGroup.Parent = overlay
	local tagLabel = makeLabel(tagGroup, Enum.FontWeight.ExtraBold, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5))

	--// Intro
	local dim = effect.dim
	if dim then
		track(effect, dim, TweenInfo.new(DIM_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = DIM_TRANSPARENCY,
		})
	end
	track(effect, introScale, TweenInfo.new(INTRO_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

	--// Spin: every tick, each card drops one slot and the one leaving the bottom waits at the top
	for tick = 1, ticks do
		local progress = tick / ticks
		local interval = TICK_FIRST + (TICK_LAST - TICK_FIRST) * progress ^ TICK_EASE_POWER
		effect.interval = interval
		pruneTweens(effect)

		local recycled = table.remove(order, 1) :: Card
		setCard(recycled, strip[tick + 7])
		table.insert(order, recycled)
		snapCard(recycled, 6)

		local info = TweenInfo.new(interval, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for index, card in order do
			if card ~= recycled then
				local slotIndex = index - 1
				local slot = SLOTS[slotIndex]
				card.holder.ZIndex = 5 - math.abs(slotIndex - CENTER_SLOT)
				track(effect, card.holder, info, { Position = UDim2.fromScale(REEL_X, slot.y) })
				track(effect, card.scale, info, { Scale = slot.scale })
				track(effect, card.alpha, info, { Value = slot.alpha })
			end
		end

		if isLocal then
			playTick(SPIN_PITCH_START + (SPIN_PITCH_END - SPIN_PITCH_START) * progress)
		end
		waitEffect(effect, interval)
	end

	--// Landing
	effect.spinning = false
	effect.landed = true
	local center = order[CENTER_SLOT + 1]
	local color = landed.color

	track(effect, center.scale, TweenInfo.new(LAND_POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = LAND_POP_SCALE })
		.Completed:Once(function()
			if effect.alive then
				track(effect, center.scale, TweenInfo.new(LAND_SETTLE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = LAND_SETTLE_SCALE,
				})
			end
		end)

	local fadeInfo = TweenInfo.new(LAND_FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, card in order do
		if card ~= center then
			track(effect, card.alpha, fadeInfo, { Value = 1 })
		end
	end

	glow.BackgroundColor3 = color
	for _, ray in rays do
		ray.BackgroundColor3 = color
	end
	track(effect, burst, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = BURST_TRANSPARENCY })

	-- The arrow jabs toward the landed card and springs back.
	pointerScale.Scale = 1.4
	track(effect, pointerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	pointer.Position = POINTER_POS - UDim2.fromScale(POINTER_NUDGE, 0)
	track(effect, pointer, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = POINTER_POS })

	if isLocal then
		tagLabel.Text = if landedItem.isNew then "NEW!" else `DUPLICATE  +{landedItem.refund} Wool`
		track(effect, tagGroup, fadeInfo, { GroupTransparency = 0 })
		playUISound(if LEGENDARY_RARITIES[landed.rarity] then "UnlockedSheep" else "LuckClaimed")
		if landed.rarity == "Mythic" then
			effect.shakeUntil = os.clock() + SHAKE_SECONDS
		end
	end

	--// 5X: the other four pop in under the reel
	local hold = if isLocal then HOLD_SECONDS else SPECTATOR_HOLD_SECONDS
	if #smalls > 0 then
		waitEffect(effect, SMALL_START_DELAY)
		local popInfo = TweenInfo.new(SMALL_POP_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for _, small in smalls do
			track(effect, small.scale, popInfo, { Scale = SMALL_SCALE })
			waitEffect(effect, SMALL_STAGGER)
		end
	end
	waitEffect(effect, hold)

	--// Fade out, then the whole screen is removed by cleanup
	local outInfo = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, card in order do
		track(effect, card.alpha, outInfo, { Value = 1 })
	end
	for _, small in smalls do
		track(effect, small.alpha, outInfo, { Value = 1 })
	end
	track(effect, burst, outInfo, { GroupTransparency = 1 })
	track(effect, overlay, outInfo, { GroupTransparency = 1 })
	if dim then
		track(effect, dim, outInfo, { BackgroundTransparency = 1 })
	end
	waitEffect(effect, FADE_SECONDS + 0.05)
end

local function run(character: Model?, pool: { Entry }, items: { Item }, isLocal: boolean)
	if #items == 0 then
		return
	end
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local liveCharacter = if character and character:IsDescendantOf(workspace) then character else nil
	-- A spectator's carousel hangs off the roller, so it needs them; the roller's own plays on screen regardless.
	if not isLocal and (not liveCharacter or not root or not root:IsA("BasePart")) then
		return
	end

	local previous = if isLocal then localEffect elseif character then spectators[character] else nil
	if previous then
		cleanup(previous)
	end

	local rootPart = if root and root:IsA("BasePart") then root else nil
	local effect = createEffect(liveCharacter, rootPart, isLocal)
	local ok, err = pcall(animate, effect, pool, items)
	cleanup(effect)
	if not ok and not string.find(tostring(err), CANCELLED, 1, true) then
		warn(`[AbilityRollEffect] {err}`)
	end
end

--// Public API ------------------------------------------------------------------

-- Yields until the whole effect (spin, hold, fade) is done or was cancelled.
function AbilityRollEffect.play(character: Model?, pool: { Entry }, items: { Item })
	run(character, pool, items, true)
end

-- A short, silent version of someone else's roll above their character. Does not yield.
function AbilityRollEffect.playSpectator(character: Model, pool: { Entry }, entry: Entry)
	local items: { Item } = { { entry = entry, isNew = false, refund = 0 } }
	task.spawn(run, character, pool, items, false)
end

function AbilityRollEffect.cancelAll()
	for effect in effects do
		cleanup(effect)
	end
end

function AbilityRollEffect.isPlaying(): boolean
	return localEffect ~= nil
end

players.PlayerRemoving:Connect(function(player: Player)
	for effect in effects do
		if effect.owner == player then
			cleanup(effect)
		end
	end
end)

return AbilityRollEffect
