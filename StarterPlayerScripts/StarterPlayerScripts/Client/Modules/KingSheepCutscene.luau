--!strict

--[[
	King Sheep cutscenes: the arrival fly-in and the defeat shot, with letterbox bars, a title card and a skip button.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.KingSheepCutscene
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

--// Modules
local windowsManager = require(script.Parent.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local DISPLAY_ORDER = 250 -- over the King Sheep banner (150) and owner banners (200); the reward popup (300) sits on top
local RENDER_NAME = "KingSheepCutscene"
local SHAKE_RENDER_NAME = "KingSheepShake"
local HUD_GUI_NAME = "Main" -- hidden while a cutscene plays
local TUTORIAL_GUI_NAME = "Tutorial"
local TUTORIAL_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local BAR_HEIGHT = 0.11 -- of the screen, each letterbox bar
local BAR_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local BAR_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local FADE_SECONDS = 0.3 -- each way, for a cut through black
local FAR_DISTANCE = 260 -- studs: further than this from the arena the camera cuts there instead of flying
local RETURN_SECONDS = 0.75
local SKIP_RETURN_SECONDS = 0.35
local SKIP_GRACE = 0.35 -- seconds before skipping works, so a click already in flight doesn't skip it
local SAFETY_SECONDS = 3 -- on top of a cutscene's length, after which it ends no matter what
local SKIP_KEYS = {
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.ButtonA] = true,
	[Enum.KeyCode.ButtonB] = true,
}
local GOLD = Color3.fromRGB(255, 211, 77)
local GOLD_DARK = Color3.fromRGB(196, 122, 18)
local TEXT_FONT = Enum.Font.FredokaOne
local TITLE_IN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TITLE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

export type Kind = "Intro" | "Outro"

-- What WorldBossClient passes in: where the boss stands and how big it is.
export type Target = {
	pivot: CFrame,
	center: Vector3,
	height: number,
	seconds: number, -- the server's intro / defeat sequence length
	explodeAt: number?, -- seconds into the outro the boss bursts
}

type Shot = {
	cframe: CFrame,
	fov: number,
	seconds: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	cut: boolean?, -- jump there behind a fade to black instead of flying
}

type Segment = {
	startsAt: number,
	endsAt: number,
	from: CFrame,
	to: CFrame,
	fromFov: number,
	toFov: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	cutAt: number?, -- a cut holds `from` until this time, then jumps to `to`
}

type Running = {
	token: number,
	kind: Kind,
	camera: Camera,
	savedType: Enum.CameraType,
	savedSubject: Instance?,
	savedFov: number,
	savedCFrame: CFrame,
	far: boolean,
	startedAt: number,
	segments: { Segment },
	endsAt: number,
	skipped: boolean,
	connections: { RBXScriptConnection },
	hud: ScreenGui?,
	controls: any,
}

--// State
local running: Running? = nil
local token = 0
local shakeEndsAt = 0
local shakeStrength = 0
local shakeSeconds = 1
local shakeBound = false
local random = Random.new()

local endedEvent = Instance.new("BindableEvent")

local KingSheepCutscene = {}
KingSheepCutscene.ended = endedEvent.Event -- (kind) once a cutscene has handed the camera back

--// Gui ------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KingSheepCutscene"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

local function newFrame(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.Parent = parent
	return frame
end

local function newLabel(name: string, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = TEXT_FONT
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Parent = parent
	return label
end

local function addStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

local fade = newFrame("Fade", screenGui)
fade.Size = UDim2.fromScale(1, 1)
fade.BackgroundTransparency = 1
fade.ZIndex = 1

local flash = newFrame("Flash", screenGui)
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(255, 244, 214)
flash.BackgroundTransparency = 1
flash.ZIndex = 2

local topBar = newFrame("TopBar", screenGui)
topBar.Size = UDim2.fromScale(1, 0)
topBar.ZIndex = 3

local bottomBar = newFrame("BottomBar", screenGui)
bottomBar.AnchorPoint = Vector2.new(0, 1)
bottomBar.Position = UDim2.fromScale(0, 1)
bottomBar.Size = UDim2.fromScale(1, 0)
bottomBar.ClipsDescendants = true
bottomBar.ZIndex = 3

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(1, 0.5)
skipButton.Position = UDim2.new(1, -24, 0.5, 0)
skipButton.Size = UDim2.fromScale(0.13, 0.5)
skipButton.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
skipButton.BackgroundTransparency = 0.2
skipButton.AutoButtonColor = true
skipButton.Font = TEXT_FONT
skipButton.Text = "SKIP  >>"
skipButton.TextScaled = true
skipButton.TextColor3 = Color3.new(1, 1, 1)
skipButton.ZIndex = 4
skipButton.Parent = bottomBar
do
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = skipButton
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.18, 0)
	padding.PaddingBottom = UDim.new(0.18, 0)
	padding.Parent = skipButton
	local stroke = addStroke(skipButton, GOLD, 2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(96, 30)
	sizeConstraint.MaxSize = Vector2.new(190, 54)
	sizeConstraint.Parent = skipButton
end

local skipHint = newLabel("SkipHint", bottomBar)
skipHint.AnchorPoint = Vector2.new(1, 0.5)
skipHint.Position = UDim2.new(0.86, -36, 0.5, 0)
skipHint.Size = UDim2.fromScale(0.16, 0.3)
skipHint.TextXAlignment = Enum.TextXAlignment.Right
skipHint.TextColor3 = Color3.fromRGB(190, 190, 190)
skipHint.Text = "press SPACE"
skipHint.ZIndex = 4

-- The title card: a gold rule either side of a big name, a small line above and below.
local card = Instance.new("Frame")
card.Name = "TitleCard"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.7)
card.Size = UDim2.fromScale(0.7, 0.22)
card.BackgroundTransparency = 1
card.ZIndex = 5
card.Visible = false
card.Parent = screenGui
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local kicker = newLabel("Kicker", card)
kicker.Position = UDim2.fromScale(0.5, 0.1)
kicker.Size = UDim2.fromScale(0.5, 0.2)
kicker.TextColor3 = GOLD
kicker.ZIndex = 6
local kickerStroke = addStroke(kicker, Color3.fromRGB(40, 20, 0), 2)

local title = newLabel("Title", card)
title.Position = UDim2.fromScale(0.5, 0.5)
title.Size = UDim2.fromScale(1, 0.56)
title.ZIndex = 6
local titleStroke = addStroke(title, Color3.fromRGB(46, 22, 0), 4)
local titleGradient = Instance.new("UIGradient")
titleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD_DARK),
	ColorSequenceKeypoint.new(0.42, GOLD),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 252, 230)),
	ColorSequenceKeypoint.new(0.58, GOLD),
	ColorSequenceKeypoint.new(1, GOLD_DARK),
})
titleGradient.Parent = title

local subtitle = newLabel("Subtitle", card)
subtitle.Position = UDim2.fromScale(0.5, 0.9)
subtitle.Size = UDim2.fromScale(0.62, 0.2)
subtitle.ZIndex = 6
local subtitleStroke = addStroke(subtitle, Color3.new(0, 0, 0), 2)

local function newRule(name: string, anchorX: number, positionX: number): Frame
	local rule = newFrame(name, card)
	rule.AnchorPoint = Vector2.new(anchorX, 0.5)
	rule.Position = UDim2.fromScale(positionX, 0.1)
	rule.Size = UDim2.fromScale(0, 0.025)
	rule.BackgroundColor3 = GOLD
	rule.ZIndex = 6
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new(if anchorX == 1 then 1 else 0, if anchorX == 1 then 0 else 1)
	gradient.Parent = rule
	return rule
end
local leftRule = newRule("LeftRule", 1, 0.24)
local rightRule = newRule("RightRule", 0, 0.76)

--// Sound ----------------------------------------------------------------------------

-- A copy of a SoundService sound in its own group (so the sound settings still mute it), cleaned up once it's done.
function KingSheepCutscene.playSound(groupName: string, soundName: string, speed: number?, volume: number?)
	local group = soundService:FindFirstChild(groupName)
	local template = group and group:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		return
	end
	local sound = template:Clone()
	sound.PlaybackSpeed = speed or 1
	sound.Volume = template.Volume * (volume or 1)
	sound.Parent = group
	sound:Play()
	local length = if sound.TimeLength > 0 then sound.TimeLength / sound.PlaybackSpeed else 6
	task.delay(length + 0.5, function()
		sound:Destroy()
	end)
end

--// Shake -----------------------------------------------------------------------------

local function getShakeOffset(): CFrame
	local left = shakeEndsAt - os.clock()
	if left <= 0 then
		return CFrame.identity
	end
	local amount = shakeStrength * left / shakeSeconds
	return CFrame.new(random:NextUnitVector() * amount) * CFrame.Angles(0, 0, random:NextNumber(-1, 1) * amount * 0.02)
end

-- Outside a cutscene the shake is added after the camera scripts, so it never builds up frame to frame.
local function updateShake()
	local camera = workspace.CurrentCamera
	if running or not camera or os.clock() >= shakeEndsAt then
		runService:UnbindFromRenderStep(SHAKE_RENDER_NAME)
		shakeBound = false
		return
	end
	camera.CFrame *= getShakeOffset()
end

-- Shakes the camera, fading out over `seconds`; a stronger shake takes over a weaker one.
function KingSheepCutscene.shake(strength: number, seconds: number)
	local now = os.clock()
	local current = if now < shakeEndsAt then shakeStrength * (shakeEndsAt - now) / shakeSeconds else 0
	if strength < current then
		return
	end
	shakeStrength, shakeSeconds, shakeEndsAt = strength, seconds, now + seconds
	if not running and not shakeBound then
		shakeBound = true
		runService:BindToRenderStep(SHAKE_RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, updateShake)
	end
end

--// Overlay -----------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = tweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function showBars()
	screenGui.Enabled = true
	skipButton.Visible = true
	skipHint.Visible = userInputService.KeyboardEnabled
	tween(topBar, BAR_IN, { Size = UDim2.fromScale(1, BAR_HEIGHT) })
	tween(bottomBar, BAR_IN, { Size = UDim2.fromScale(1, BAR_HEIGHT) })
end

local function hideOverlay(currentToken: number)
	skipButton.Visible = false
	tween(fade, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 })
	tween(topBar, BAR_OUT, { Size = UDim2.fromScale(1, 0) })
	tween(bottomBar, BAR_OUT, { Size = UDim2.fromScale(1, 0) }).Completed:Once(function()
		if token == currentToken and not running then
			screenGui.Enabled = false
		end
	end)
end

local function setCardTransparency(transparency: number, info: TweenInfo?)
	local goals: { [Instance]: { [string]: any } } = {
		[kicker] = { TextTransparency = transparency },
		[kickerStroke] = { Transparency = transparency },
		[title] = { TextTransparency = transparency },
		[titleStroke] = { Transparency = transparency },
		[subtitle] = { TextTransparency = transparency },
		[subtitleStroke] = { Transparency = transparency },
		[leftRule] = { BackgroundTransparency = transparency },
		[rightRule] = { BackgroundTransparency = transparency },
	}
	for instance, goal in goals do
		if info then
			tween(instance, info, goal)
		else
			for property, value in goal do
				(instance :: any)[property] = value
			end
		end
	end
end

local function hideCard()
	if not card.Visible then
		return
	end
	setCardTransparency(1, TITLE_OUT)
	tween(cardScale, TITLE_OUT, { Scale = 0.9 })
end

-- Slams the title in, draws the rules out from it and sweeps a shine across the name.
local function showCard(kickerText: string, titleText: string, subtitleText: string)
	kicker.Text = kickerText
	title.Text = titleText
	subtitle.Text = subtitleText
	setCardTransparency(1)
	cardScale.Scale = 1.5
	leftRule.Size = UDim2.fromScale(0, 0.025)
	rightRule.Size = UDim2.fromScale(0, 0.025)
	titleGradient.Offset = Vector2.new(-1, 0)
	card.Visible = true

	setCardTransparency(0, TITLE_IN)
	tween(cardScale, TITLE_IN, { Scale = 1 })
	local ruleIn = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.15)
	tween(leftRule, ruleIn, { Size = UDim2.fromScale(0.2, 0.025) })
	tween(rightRule, ruleIn, { Size = UDim2.fromScale(0.2, 0.025) })
	tween(titleGradient, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, false, 0.25), { Offset = Vector2.new(1, 0) })
end

-- A cut through black: fades in, the camera jumps at the darkest point, then it fades back out.
local function fadeThrough()
	tween(fade, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 })
	tween(fade, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, FADE_SECONDS + 0.05), {
		BackgroundTransparency = 1,
	})
end

function KingSheepCutscene.flash(strength: number?)
	flash.BackgroundTransparency = 1 - (strength or 0.75)
	tween(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
end

--// Camera ---------------------------------------------------------------------------------

local function getHumanoid(): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function getControls(): any
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule or not playerModule:IsA("ModuleScript") then
		return nil
	end
	local success, controls = pcall(function()
		return (require(playerModule) :: any):GetControls()
	end)
	return if success then controls else nil
end

-- Lays the shots end to end from the camera's own view, each starting where the last one left off.
local function buildSegments(from: CFrame, fromFov: number, shots: { Shot }): ({ Segment }, number)
	local segments: { Segment } = {}
	local time = 0
	for _, shot in shots do
		table.insert(segments, {
			startsAt = time,
			endsAt = time + shot.seconds,
			from = from,
			to = shot.cframe,
			fromFov = fromFov,
			toFov = shot.fov,
			style = shot.style,
			direction = shot.direction,
			cutAt = if shot.cut then time + FADE_SECONDS else nil,
		})
		time += shot.seconds
		from, fromFov = shot.cframe, shot.fov
	end
	return segments, time
end

local function sample(current: Running, elapsed: number): (CFrame, number)
	for _, segment in current.segments do
		if elapsed < segment.endsAt then
			if segment.cutAt then
				if elapsed < segment.cutAt then
					return segment.from, segment.fromFov
				end
				local alpha = (elapsed - segment.cutAt) / math.max(segment.endsAt - segment.cutAt, 0.01)
				-- After a cut the shot settles in from slightly further back.
				local settle = tweenService:GetValue(math.clamp(alpha, 0, 1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				return segment.to * CFrame.new(0, 0, (1 - settle) * 4), segment.toFov
			end
			local alpha = (elapsed - segment.startsAt) / math.max(segment.endsAt - segment.startsAt, 0.01)
			local eased = tweenService:GetValue(math.clamp(alpha, 0, 1), segment.style, segment.direction)
			return segment.from:Lerp(segment.to, eased), segment.fromFov + (segment.toFov - segment.fromFov) * eased
		end
	end
	local last = current.segments[#current.segments]
	return last.to, last.toFov
end

local function finish()
	local current = running
	if not current then
		return
	end
	running = nil
	runService:UnbindFromRenderStep(RENDER_NAME)
	for _, connection in current.connections do
		connection:Disconnect()
	end

	local camera = current.camera
	if camera.Parent then
		camera.CameraType = current.savedType
		local subject = current.savedSubject
		camera.CameraSubject = if subject and subject:IsDescendantOf(workspace) then subject else getHumanoid()
		camera.FieldOfView = current.savedFov
	end
	local hud = current.hud
	if hud and hud.Parent and not hud.Enabled then
		hud.Enabled = true
	end
	if current.controls then
		pcall(function()
			current.controls:Enable()
		end)
	end

	hideCard()
	hideOverlay(current.token)
	if os.clock() < shakeEndsAt then
		KingSheepCutscene.shake(shakeStrength * (shakeEndsAt - os.clock()) / shakeSeconds, shakeEndsAt - os.clock())
	end
	endedEvent:Fire(current.kind)
end

-- Takes the camera back to where the player left it, from wherever the cutscene is now.
local function returnHome(current: Running, seconds: number)
	local elapsed = os.clock() - current.startedAt
	local from, fromFov = sample(current, elapsed)
	local cut = current.far
	if cut then
		fadeThrough()
	end
	current.segments = {
		{
			startsAt = elapsed,
			endsAt = elapsed + (if cut then FADE_SECONDS * 2 else seconds),
			from = from,
			to = current.savedCFrame,
			fromFov = fromFov,
			toFov = current.savedFov,
			style = Enum.EasingStyle.Quad,
			direction = Enum.EasingDirection.InOut,
			cutAt = if cut then elapsed + FADE_SECONDS else nil,
		},
	}
	current.endsAt = current.segments[1].endsAt
end

function KingSheepCutscene.skip()
	local current = running
	if not current or current.skipped or os.clock() - current.startedAt < SKIP_GRACE then
		return
	end
	current.skipped = true
	skipButton.Visible = false
	hideCard()
	returnHome(current, SKIP_RETURN_SECONDS)
end

local function render()
	local current = running
	if not current then
		runService:UnbindFromRenderStep(RENDER_NAME)
		return
	end
	local elapsed = os.clock() - current.startedAt
	if elapsed >= current.endsAt then
		finish()
		return
	end
	local cframe, fov = sample(current, elapsed)
	current.camera.CFrame = cframe * getShakeOffset()
	current.camera.FieldOfView = fov
end

-- Whether a cutscene can take the camera now: the default camera, a living character and the tutorial done.
local function canPlay(camera: Camera): boolean
	if camera.CameraType ~= Enum.CameraType.Custom or not getHumanoid() then
		return false
	end
	local tutorial = playerGui:FindFirstChild(TUTORIAL_GUI_NAME)
	return not tutorial or tutorial:GetAttribute(TUTORIAL_DONE_ATTRIBUTE) == true
end

type Cue = { at: number, run: () -> () }

--[[
	Takes the camera through `shots` and back, running each cue at its time unless the cutscene was skipped or ended.
	Returns false when it can't play right now (another camera mode, dead, or in the tutorial).
]]
local function play(kind: Kind, target: Target, makeShots: (savedCFrame: CFrame, savedFov: number, far: boolean) -> { Shot }, cues: { Cue }): boolean
	if running then
		finish()
	end
	local camera = workspace.CurrentCamera
	if not camera or not canPlay(camera) then
		return false
	end

	token += 1
	local currentToken = token
	local savedCFrame, savedFov = camera.CFrame, camera.FieldOfView
	local far = (savedCFrame.Position - target.center).Magnitude > FAR_DISTANCE
	local shots = makeShots(savedCFrame, savedFov, far)
	table.insert(shots, {
		cframe = savedCFrame,
		fov = savedFov,
		seconds = if far then FADE_SECONDS * 2 else RETURN_SECONDS,
		style = Enum.EasingStyle.Quad,
		direction = Enum.EasingDirection.InOut,
		cut = far,
	})
	local segments, length = buildSegments(savedCFrame, savedFov, shots)

	local current: Running = {
		token = currentToken,
		kind = kind,
		camera = camera,
		savedType = camera.CameraType,
		savedSubject = camera.CameraSubject,
		savedFov = savedFov,
		savedCFrame = savedCFrame,
		far = far,
		startedAt = os.clock(),
		segments = segments,
		endsAt = length,
		skipped = false,
		connections = {},
		hud = nil,
		controls = getControls(),
	}
	running = current

	windowsManager.closeAll()
	local hud = playerGui:FindFirstChild(HUD_GUI_NAME)
	if hud and hud:IsA("ScreenGui") and hud.Enabled then
		hud.Enabled = false
		current.hud = hud
		-- Something else turning the HUD back on owns it from then on.
		table.insert(current.connections, hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			if hud.Enabled then
				current.hud = nil
			end
		end))
	end
	if current.controls then
		pcall(function()
			current.controls:Disable()
		end)
	end

	camera.CameraType = Enum.CameraType.Scriptable
	runService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, render)
	showBars()
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, target.center, 2)
	end)

	-- Fades for cuts, then the scene's own cues; none of them run once it's been skipped or replaced.
	for _, segment in segments do
		if segment.cutAt then
			task.delay(segment.startsAt, function()
				if running == current and not current.skipped then
					fadeThrough()
				end
			end)
		end
	end
	for _, cue in cues do
		task.delay(cue.at, function()
			if running == current and not current.skipped then
				cue.run()
			end
		end)
	end

	-- Never leaves the player stuck: a respawn, death, camera swap or someone else taking the camera ends it at once.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	table.insert(current.connections, player.CharacterAdded:Connect(finish))
	if humanoid then
		table.insert(current.connections, humanoid.Died:Connect(finish))
	end
	table.insert(current.connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(finish))
	table.insert(current.connections, camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			finish()
		end
	end))
	task.delay(length + SAFETY_SECONDS, function()
		if running == current then
			finish()
		end
	end)
	return true
end

--// Public API ------------------------------------------------------------------

function KingSheepCutscene.isPlaying(): boolean
	return running ~= nil
end

function KingSheepCutscene.getKind(): Kind?
	return if running then running.kind else nil
end

-- Ends the cutscene straight away (only one of this kind, when given).
function KingSheepCutscene.stop(kind: Kind?)
	if running and (kind == nil or running.kind == kind) then
		finish()
	end
end

-- Yields until no cutscene is playing, or `maxSeconds` have passed.
function KingSheepCutscene.waitUntilDone(maxSeconds: number)
	local giveUpAt = os.clock() + maxSeconds
	while running and os.clock() < giveUpAt do
		task.wait(0.1)
	end
end

local function flat(vector: Vector3): Vector3
	local flattened = Vector3.new(vector.X, 0, vector.Z)
	return if flattened.Magnitude > 0.01 then flattened.Unit else Vector3.zAxis
end

-- The arrival: a wide shot of the arena, a slow push in to a low hero angle on the King, then back to the player.
function KingSheepCutscene.playIntro(target: Target): boolean
	local height = math.max(target.height, 4)
	local look = flat(target.pivot.LookVector)
	local side = look:Cross(Vector3.yAxis)
	local center = target.center
	local focus = center + Vector3.new(0, height * 0.1, 0)
	local face = center + look * height * 0.35 + Vector3.new(0, height * 0.28, 0)

	local wide = CFrame.lookAt(focus + look * height * 3.1 + side * height * 1.7 + Vector3.new(0, height * 1.5, 0), focus)
	local hero = CFrame.lookAt(center + look * height * 1.35 + side * height * 0.4 - Vector3.new(0, height * 0.18, 0), face)
	local drift = CFrame.lookAt(center + look * height * 1.25 + side * height * 0.28 - Vector3.new(0, height * 0.2, 0), face)
	local length = math.max(target.seconds, 3)

	return play("Intro", target, function(_savedCFrame: CFrame, savedFov: number, far: boolean): { Shot }
		return {
			{ cframe = wide, fov = math.min(savedFov, 62), seconds = 1.15, style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.InOut, cut = far },
			{ cframe = hero, fov = 50, seconds = length - 2.4, style = Enum.EasingStyle.Sine, direction = Enum.EasingDirection.InOut },
			{ cframe = drift, fov = 48, seconds = 0.5, style = Enum.EasingStyle.Linear, direction = Enum.EasingDirection.InOut },
		}
	end, {
		{ at = 1.3, run = function()
			showCard("W O R L D   B O S S", "THE KING SHEEP", "has arrived at the plaza!")
		end },
		{ at = 1.6, run = function()
			KingSheepCutscene.shake(0.7, 0.6)
		end },
		{ at = length - 0.5, run = hideCard },
	})
end

-- The defeat: a slow orbit while the King charges up, a kick back when it bursts, then back to the player.
function KingSheepCutscene.playOutro(target: Target): boolean
	local height = math.max(target.height, 4)
	local look = flat(target.pivot.LookVector)
	local center = target.center
	local focus = center + Vector3.new(0, height * 0.05, 0)
	local explodeAt = target.explodeAt or math.max(target.seconds - 0.6, 0.8)

	local function around(degrees: number, distance: number, rise: number): CFrame
		local direction = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(look)
		return CFrame.lookAt(center + direction * height * distance + Vector3.new(0, height * rise, 0), focus)
	end

	return play("Outro", target, function(_savedCFrame: CFrame, savedFov: number, far: boolean): { Shot }
		return {
			{ cframe = around(40, 1.9, 0.55), fov = math.min(savedFov, 60), seconds = 0.8, style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.Out, cut = far },
			{ cframe = around(-20, 1.6, 0.4), fov = 54, seconds = math.max(explodeAt - 0.8, 0.4), style = Enum.EasingStyle.Sine, direction = Enum.EasingDirection.InOut },
			{ cframe = around(-35, 2.7, 0.95), fov = 64, seconds = 0.7, style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out },
			{ cframe = around(-42, 2.85, 1.05), fov = 64, seconds = 0.9, style = Enum.EasingStyle.Linear, direction = Enum.EasingDirection.InOut },
		}
	end, {
		{ at = explodeAt, run = function()
			KingSheepCutscene.flash(0.8)
			KingSheepCutscene.shake(1.6, 0.8)
		end },
	})
end

--// Setup -------------------------------------------------------------------------------

skipButton.Activated:Connect(KingSheepCutscene.skip)
userInputService.InputBegan:Connect(function(input: InputObject)
	if running and SKIP_KEYS[input.KeyCode] then
		KingSheepCutscene.skip()
	end
end)

return KingSheepCutscene
