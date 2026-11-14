--!strict

--[[
	When the sheep this player's next rebirth needs lands in their pen, the camera flies to it, outlines it and shows a title card.
	Fired by SheepSpawnHandler (RebirthSheepSpawned). Location: StarterPlayerScripts.Client.Controllers.RebirthSheepClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local contextActionService = game:GetService("ContextActionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local vfxFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX")
local uiSounds = soundService:WaitForChild("UISounds")

--// Configs
local SHEEP_TAG = "Sheep"
local PLAYING_ATTRIBUTE = "RebirthSheepCutscenePlaying" -- set locally on the player while the camera is taken (TutorialClient waits for it)
local PEN_CUTSCENE_ATTRIBUTE = "PenCutscenePlaying" -- PenUnlockClient's; this one waits for it to finish
local REBIRTH_SHEEP_ATTRIBUTE = "RebirthSheepId" -- set by RebirthHandler: the adult type the next rebirth needs
local HUD_GUI_NAME = "Main"
local RENDER_NAME = "RebirthSheepCutscene"
local SKIP_ACTION = "SkipRebirthSheepCutscene"
local DISPLAY_ORDER = 240 -- over the HUD and tutorial (90), under the King Sheep cutscene (250)
local FIND_SHEEP_SECONDS = 3 -- how long to wait for the sheep's model to stream in
local WAIT_FOR_CAMERA_SECONDS = 10 -- another cutscene may still own the camera; after this the reveal is dropped
local REPEAT_COOLDOWN = 60 -- seconds before another of the same sheep can play it again

-- Timeline, in seconds from the start of the cutscene.
local FLY_IN_SECONDS = 1
local REVEAL_AT = 0.9 -- outline, poof and sound
local CARD_AT = 1.1
local END_AT = 4.8
local RETURN_SECONDS = 0.8
local SKIP_GRACE = 0.4
local SAFETY_SECONDS = 4

local SHOT_DISTANCE = 2.6 -- of the sheep's widest side, the camera's distance back from it
local SHOT_HEIGHT = 0.45 -- of that distance, the camera's height above the sheep
local MIN_DISTANCE, MAX_DISTANCE = 9, 30 -- studs
local LOOK_LIFT = 0.25 -- of the sheep's height, how far above its root the camera looks
local ORBIT_DEGREES = 30 -- how far the camera circles the sheep while it plays
local FOLLOW_SPEED = 6 -- how quickly the shot catches up with the sheep wandering
local BAR_HEIGHT = 0.11 -- of the screen, each letterbox bar
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)
local FALLBACK_COLOR = Color3.fromRGB(255, 211, 77)

--// State
local token = 0
local playing = false
local lastPlayedAt: { [string]: number } = {}
local skipRequested: (() -> ())? = nil

--// Gui ------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RebirthSheepCutscene"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.Enabled = false
screenGui:SetAttribute("EffectLayer", true) -- TutorialClient leaves it on
screenGui.Parent = playerGui

local function newBar(name: string, anchorY: number): Frame
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.AnchorPoint = Vector2.new(0, anchorY)
	bar.Position = UDim2.fromScale(0, anchorY)
	bar.Size = UDim2.fromScale(1, 0)
	bar.BackgroundColor3 = Color3.new(0, 0, 0)
	bar.BorderSizePixel = 0
	bar.Parent = screenGui
	return bar
end

local topBar = newBar("TopBar", 0)
local bottomBar = newBar("BottomBar", 1)

local function newLabel(name: string, text: string, positionY: number, height: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, positionY)
	label.Size = UDim2.fromScale(0.8, height)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Transparency = 1
	stroke.Parent = label
	return label
end

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.25)
card.Size = UDim2.fromScale(0.7, 0.24)
card.BackgroundTransparency = 1
card.Parent = screenGui
local cardScale = Instance.new("UIScale")
cardScale.Parent = card
local kicker = newLabel("Kicker", "REBIRTH SHEEP APPEARED!", 0.14, 0.26, Color3.new(1, 1, 1))
kicker.Parent = card
local title = newLabel("Title", "", 0.55, 0.5, FALLBACK_COLOR)
title.Parent = card
local subtitle = newLabel("Subtitle", "Shear it to unlock your next Rebirth!", 0.9, 0.2, Color3.new(1, 1, 1))
subtitle.Parent = card
local cardLabels = { kicker, title, subtitle }

local skipButton = Instance.new("TextButton")
skipButton.Name = "Skip"
skipButton.AnchorPoint = Vector2.new(1, 0.5)
skipButton.Position = UDim2.fromScale(0.97, 1 - BAR_HEIGHT / 2)
skipButton.Size = UDim2.fromScale(0.12, BAR_HEIGHT * 0.5)
skipButton.BackgroundTransparency = 1
skipButton.Font = Enum.Font.FredokaOne
skipButton.Text = "SKIP >>"
skipButton.TextColor3 = Color3.new(1, 1, 1)
skipButton.TextScaled = true
skipButton.Visible = false
skipButton.Parent = screenGui
local skipRatio = Instance.new("UIAspectRatioConstraint")
skipRatio.AspectRatio = 3.2
skipRatio.Parent = skipButton

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = tweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function setCardTransparency(transparency: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, label in cardLabels do
		tween(label, info, { TextTransparency = transparency })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			tween(stroke, info, { Transparency = transparency })
		end
	end
end

local function showCard(name: string, color: Color3)
	title.Text = name
	title.TextColor3 = color
	cardScale.Scale = 1.5
	setCardTransparency(0, 0.35)
	tween(cardScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

local function hideCard()
	setCardTransparency(1, 0.3)
end

local function showBars()
	screenGui.Enabled = true
	skipButton.Visible = true
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	tween(topBar, info, { Size = UDim2.fromScale(1, BAR_HEIGHT) })
	tween(bottomBar, info, { Size = UDim2.fromScale(1, BAR_HEIGHT) })
end

local function hideBars(currentToken: number)
	skipButton.Visible = false
	hideCard()
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	tween(topBar, info, { Size = UDim2.fromScale(1, 0) })
	tween(bottomBar, info, { Size = UDim2.fromScale(1, 0) }).Completed:Once(function()
		if token == currentToken then
			screenGui.Enabled = false
		end
	end)
end

--// Effects ---------------------------------------------------------------------------

local function playSound(name: string)
	local sound = uiSounds:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

local function poof(position: Vector3)
	local template = vfxFolder:FindFirstChild("PoofAttachment")
	if not template or not template:IsA("Attachment") then
		return
	end
	local attachment = template:Clone()
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local longest = 0
	for _, emitter in attachment:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			local count = emitter:GetAttribute("EmitCount")
			emitter:Emit(if type(count) == "number" then count else 10)
			longest = math.max(longest, emitter.Lifetime.Max)
		end
	end
	debris:AddItem(attachment, longest + 0.1)
end

-- An outline in the sheep's rarity colour that flashes in, then settles; removed when the cutscene ends.
local function addOutline(sheep: Model, color: Color3): Highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "RebirthSheepOutline"
	highlight.Adornee = sheep
	highlight.FillColor = color
	highlight.OutlineColor = OUTLINE_COLOR
	highlight.FillTransparency = 0
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace
	tween(highlight, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 0.6 })
	return highlight
end

--// Camera ----------------------------------------------------------------------------

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

local function ease(alpha: number): number
	return tweenService:GetValue(math.clamp(alpha, 0, 1), Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

local function canTakeCamera(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and camera.CameraType == Enum.CameraType.Custom and getHumanoid() ~= nil
		and not player:GetAttribute(PEN_CUTSCENE_ATTRIBUTE)
end

local function getRoot(sheep: Model): BasePart?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The player's sheep with this id once it has streamed in, or nil after FIND_SHEEP_SECONDS.
local function findSheep(sheepId: number): Model?
	local giveUpAt = os.clock() + FIND_SHEEP_SECONDS
	repeat
		for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
			if sheep:IsA("Model") and sheep:GetAttribute("id") == sheepId and sheep:GetAttribute("OwnerId") == player.UserId
				and getRoot(sheep)
			then
				return sheep
			end
		end
		task.wait(0.1)
	until os.clock() > giveUpAt
	return nil
end

-- Flies the camera to the sheep, follows it with a slow orbit, then flies back. The sheep may be nil (it never streamed in): the shot holds on `fallback`.
local function playCamera(sheep: Model?, fallback: Vector3, name: string, color: Color3)
	local camera = workspace.CurrentCamera :: Camera
	token += 1
	local currentToken = token
	local savedCFrame, savedType, savedSubject = camera.CFrame, camera.CameraType, camera.CameraSubject
	local startedAt = os.clock()
	local returnFrom: CFrame? = nil
	local returnAt = END_AT
	local connections: { RBXScriptConnection } = {}
	local controls = getControls()
	local hud = playerGui:FindFirstChild(HUD_GUI_NAME)
	local hiddenHud = if hud and hud:IsA("ScreenGui") and hud.Enabled then hud else nil
	local outline: Highlight? = nil

	-- Shot size from the sheep's bounding box, so a Giant gets a wider shot than a Baby.
	local width, height = 4, 4
	if sheep then
		local _, size = sheep:GetBoundingBox()
		width, height = math.max(size.X, size.Z), size.Y
	end
	local distance = math.clamp(width * SHOT_DISTANCE, MIN_DISTANCE, MAX_DISTANCE)
	local lift = Vector3.new(0, height * LOOK_LIFT, 0)

	-- The orbit starts on the side the camera already looks from, so the fly-in is short.
	local function getTarget(): Vector3
		local root = sheep and sheep.Parent and getRoot(sheep)
		return (if root then root.Position else fallback) + lift
	end
	local target = getTarget()
	local fromFlat = Vector3.new(savedCFrame.Position.X - target.X, 0, savedCFrame.Position.Z - target.Z)
	local startAngle = if fromFlat.Magnitude > 1e-3 then math.atan2(fromFlat.Z, fromFlat.X) else 0

	local function orbitAt(elapsed: number): CFrame
		local angle = startAngle + math.rad(ORBIT_DEGREES) * math.clamp(elapsed / END_AT, 0, 1)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance + Vector3.new(0, distance * SHOT_HEIGHT, 0)
		return CFrame.lookAt(target + offset, target)
	end

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		playing = false
		runService:UnbindFromRenderStep(RENDER_NAME)
		contextActionService:UnbindAction(SKIP_ACTION)
		for _, connection in connections do
			connection:Disconnect()
		end
		skipRequested = nil
		if outline then
			outline:Destroy()
		end
		if camera.Parent then
			camera.CameraType = savedType
			camera.CameraSubject = if savedSubject and savedSubject:IsDescendantOf(workspace) then savedSubject else getHumanoid()
		end
		if hiddenHud and hiddenHud.Parent then
			hiddenHud.Enabled = true
		end
		if controls then
			pcall(function()
				controls:Enable()
			end)
		end
		hideBars(currentToken)
		player:SetAttribute(PLAYING_ATTRIBUTE, nil)
	end

	local function skip()
		if returnFrom or os.clock() - startedAt < SKIP_GRACE then
			return
		end
		returnFrom = camera.CFrame
		returnAt = os.clock() - startedAt
		skipButton.Visible = false
		hideCard()
	end
	skipRequested = skip

	local function render(deltaTime: number)
		local elapsed = os.clock() - startedAt
		target = target:Lerp(getTarget(), math.min(deltaTime * FOLLOW_SPEED, 1))
		local cframe: CFrame
		if elapsed < returnAt then
			local orbit = orbitAt(elapsed)
			cframe = if elapsed < FLY_IN_SECONDS then savedCFrame:Lerp(orbit, ease(elapsed / FLY_IN_SECONDS)) else orbit
		else
			local alpha = (elapsed - returnAt) / RETURN_SECONDS
			cframe = (returnFrom or orbitAt(END_AT)):Lerp(savedCFrame, ease(alpha))
			if alpha >= 1 then
				camera.CFrame = savedCFrame
				finish()
				return
			end
		end
		camera.CFrame = cframe
	end

	playing = true
	player:SetAttribute(PLAYING_ATTRIBUTE, true)
	windowsManager.closeAll()
	if hiddenHud then
		hiddenHud.Enabled = false
	end
	if controls then
		pcall(function()
			controls:Disable()
		end)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	runService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, render)
	contextActionService:BindActionAtPriority(SKIP_ACTION, function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			skip()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.ButtonB)
	showBars()

	task.delay(REVEAL_AT, function()
		if finished or returnFrom then
			return
		end
		if sheep and sheep.Parent then
			outline = addOutline(sheep, color)
		end
		poof(getTarget())
		playSound("UnlockedSheep")
	end)
	task.delay(CARD_AT, function()
		if not finished and not returnFrom then
			showCard(name, color)
		end
	end)

	-- Never leaves the player stuck: a respawn, death or someone else taking the camera ends it at once.
	local humanoid = getHumanoid()
	table.insert(connections, player.CharacterAdded:Connect(finish))
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(finish))
	end
	table.insert(connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(finish))
	table.insert(connections, camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			finish()
		end
	end))
	task.delay(END_AT + RETURN_SECONDS + SAFETY_SECONDS, finish)
end

skipButton.Activated:Connect(function()
	if skipRequested then
		skipRequested()
	end
end)

--// Reveal ----------------------------------------------------------------------------

local function onRebirthSheepSpawned(sheepId: any, position: any)
	local adultType = player:GetAttribute(REBIRTH_SHEEP_ATTRIBUTE)
	if type(sheepId) ~= "number" or typeof(position) ~= "Vector3" or type(adultType) ~= "string" or adultType == "" then
		return
	end
	if playing or os.clock() - (lastPlayedAt[adultType] or -math.huge) < REPEAT_COOLDOWN then
		return
	end
	lastPlayedAt[adultType] = os.clock()

	local sheep = findSheep(sheepId)
	local giveUpAt = os.clock() + WAIT_FOR_CAMERA_SECONDS
	while not canTakeCamera() do
		if os.clock() > giveUpAt or playing then
			return
		end
		task.wait(0.2)
	end
	if sheep and not sheep.Parent then
		return -- sheared or gone while waiting
	end

	local name = if sheep then sheep:GetAttribute("SheepName") else nil
	local color = if sheep then sheep:GetAttribute("RarityColor") else nil
	playCamera(sheep, position, if type(name) == "string" then name else "Rebirth Sheep",
		if typeof(color) == "Color3" then color else FALLBACK_COLOR)
end

network.waitUntilReadyAsync()
network.connectEvent(network.RemoteEvents.RebirthSheepSpawned, onRebirthSheepSpawned)
