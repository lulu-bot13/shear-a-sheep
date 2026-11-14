--!strict

--[[
	When this player's pen moves up a tier, the camera flies over it: the old fence sinks away, the new one pops up around the pen, then a title card.
	The server has already swapped the fence; this plays a local copy of the old one going away. Location: StarterPlayerScripts.Client.Controllers.PenUnlockClient
]]--

--// Services
local contextActionService = game:GetService("ContextActionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
local vfxFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX")
local uiSounds = soundService:WaitForChild("UISounds")

--// Configs
local FENCE_NAME = "PlotFence1" -- PenStyleData.FenceName
local AREA_NAME = "SheepArea"
local OWNER_ATTRIBUTE = "Owner" -- set on the plot by PlotHandler
local TIER_ATTRIBUTE = "PenTier" -- set on the plot by PlotLayoutHandler
local NAME_ATTRIBUTE = "PenName"
local PLAYING_ATTRIBUTE = "PenCutscenePlaying" -- set locally on the player while the camera is taken (TutorialClient waits for it)
local HUD_GUI_NAME = "Main"
local RENDER_NAME = "PenUnlockCutscene"
local SKIP_ACTION = "SkipPenCutscene"
local DISPLAY_ORDER = 240 -- over the HUD and tutorial (90), under the King Sheep cutscene (250)
local SETTLE_SECONDS = 3 -- tier changes this soon after the plot is found are the join's own swap, not an unlock
local START_DELAY = 1.6 -- lets the rebirth burst play before the camera leaves

-- Timeline, in seconds from the start of the cutscene.
local FLY_IN_SECONDS = 1.1
local REMOVE_AT = 1.1 -- the old fence sinks away around the pen, one side to the other
local REMOVE_SPREAD = 1
local REMOVE_SECONDS = 0.45
local BUILD_AT = 2.4 -- then the new one pops up in the same order
local BUILD_SPREAD = 1.6
local BUILD_SECONDS = 0.55
local CARD_AT = 3.9
local END_AT = 6.8
local RETURN_SECONDS = 0.8
local SKIP_GRACE = 0.4 -- seconds before skipping works, so a click already in flight doesn't skip it
local SAFETY_SECONDS = 4 -- on top of the whole length, after which it ends no matter what

local SINK_DEPTH = 7 -- studs pieces sink and rise through
local SHOT_DISTANCE = 0.95 -- of the pen's widest side, the camera's distance back from its centre
local SHOT_HEIGHT = 0.8 -- of that side, the camera's height above it
local ORBIT_DEGREES = 40 -- how far the camera circles the pen while it plays
local POOF_COUNT = 8 -- puffs spread around the old fence as it goes
local POP_SOUNDS = 10 -- pops spread over the build, each a little higher
local BAR_HEIGHT = 0.11 -- of the screen, each letterbox bar
local GOLD = Color3.fromRGB(255, 211, 77)

type Look = { cframe: CFrame, transparency: number }

--// State
local ownPlot: Instance? = nil
local knownTier: number? = nil
local settledAt = math.huge
local cachedFence: Model? = nil -- an unparented copy of the fence as it is now, to play going away on the next unlock
local token = 0
local plotConnections: { RBXScriptConnection } = {}
local skipRequested: (() -> ())? = nil

--// Gui ------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PenUnlockCutscene"
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
local kicker = newLabel("Kicker", "NEW PEN UNLOCKED!", 0.14, 0.26, Color3.new(1, 1, 1))
kicker.Parent = card
local title = newLabel("Title", "", 0.55, 0.5, GOLD)
title.Parent = card
local subtitle = newLabel("Subtitle", "Rebirth more for an even fancier pen", 0.9, 0.2, Color3.new(1, 1, 1))
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

local function showCard(penName: string)
	title.Text = penName
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

local function playPop(speed: number)
	local template = uiSounds:FindFirstChild("Pop")
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		sound.PlaybackSpeed = speed
		sound.Parent = uiSounds
		sound:Play()
		debris:AddItem(sound, 3)
	end
end

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

--// Fence swap ------------------------------------------------------------------------

-- The pen's centre and its widest side, or nil without a SheepArea.
local function getAreaBox(plot: Instance): (Vector3?, number)
	local area = plot:FindFirstChild(AREA_NAME)
	if area and area:IsA("BasePart") then
		return area.Position, math.max(area.Size.X, area.Size.Z)
	end
	return nil, 0
end

-- 0..1 around the pen, starting from `startAngle` (radians), so pieces go and come in a sweep.
local function getSweep(position: Vector3, center: Vector3, startAngle: number): number
	local angle = math.atan2(position.Z - center.Z, position.X - center.X) - startAngle
	return (angle % (2 * math.pi)) / (2 * math.pi)
end

local function getFence(plot: Instance): Model?
	local fence = plot:FindFirstChild(FENCE_NAME)
	return if fence and fence:IsA("Model") then fence else nil
end

local function cacheFence(plot: Instance)
	local fence = getFence(plot)
	if cachedFence then
		cachedFence:Destroy()
	end
	cachedFence = if fence then fence:Clone() else nil
end

type Swap = {
	finish: () -> (), -- snaps everything to the end state at once
}

--[[
	Plays the old fence copy sinking away and the new fence rising, both in a sweep around the pen from `startAngle`.
	The timeline starts `startDelay` seconds from now; until then the old fence stands and the new one is hidden.
	The new fence's real look is put back exactly when it's done or finished early.
]]
local function playSwap(oldFence: Model?, newFence: Model, center: Vector3, startAngle: number, startDelay: number): Swap
	local removeAt, buildAt = startDelay + REMOVE_AT, startDelay + BUILD_AT
	local tweens: { Tween } = {}
	local looks: { [BasePart]: Look } = {}
	local decals: { [Decal | Texture]: number } = {}
	local lights: { [Light]: boolean } = {}
	local done = false

	local function hide(object: Instance)
		if object:IsA("BasePart") and not looks[object] then
			looks[object] = { cframe = object.CFrame, transparency = object.Transparency }
			object.Transparency = 1
			object.CFrame = object.CFrame - Vector3.new(0, SINK_DEPTH, 0)
		elseif (object:IsA("Decal") or object:IsA("Texture")) and not decals[object] then
			decals[object] = object.Transparency
			object.Transparency = 1
		elseif object:IsA("Light") and lights[object] == nil then
			lights[object] = object.Enabled
			object.Enabled = false
		end
	end

	for _, descendant in newFence:GetDescendants() do
		hide(descendant)
	end
	-- Parts still streaming in join the build hidden.
	local addedConnection = newFence.DescendantAdded:Connect(hide)

	if oldFence then
		oldFence.Parent = workspace
		for _, part in oldFence:GetDescendants() do
			if part:IsA("BasePart") then
				local delay = removeAt + getSweep(part.Position, center, startAngle) * REMOVE_SPREAD
				local info = TweenInfo.new(REMOVE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay)
				table.insert(tweens, tween(part, info, { CFrame = part.CFrame - Vector3.new(0, SINK_DEPTH, 0), Transparency = 1 }))
			elseif part:IsA("Light") then
				task.delay(removeAt, function()
					part.Enabled = false
				end)
			end
		end
	end

	for part, look in looks do
		local delay = buildAt + getSweep(look.cframe.Position, center, startAngle) * BUILD_SPREAD
		local info = TweenInfo.new(BUILD_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		table.insert(tweens, tween(part, info, { CFrame = look.cframe, Transparency = look.transparency }))
	end
	for decal, transparency in decals do
		local info = TweenInfo.new(BUILD_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, buildAt + BUILD_SPREAD / 2)
		table.insert(tweens, tween(decal, info, { Transparency = transparency }))
	end

	local function finish()
		if done then
			return
		end
		done = true
		addedConnection:Disconnect()
		for _, created in tweens do
			created:Cancel()
		end
		for part, look in looks do
			if part.Parent then
				part.CFrame = look.cframe
				part.Transparency = look.transparency
			end
		end
		for decal, transparency in decals do
			decal.Transparency = transparency
		end
		for light, enabled in lights do
			light.Enabled = enabled
		end
		if oldFence then
			oldFence:Destroy()
		end
	end

	-- Puffs as the old fence goes, pops as the new one comes, lights once it's up.
	local poofParts: { BasePart } = {}
	if oldFence then
		for _, part in oldFence:GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(poofParts, part)
			end
		end
	end
	for index = 1, math.min(POOF_COUNT, #poofParts) do
		local part = poofParts[math.floor((index - 0.5) * #poofParts / POOF_COUNT) + 1]
		local position = part.Position
		task.delay(removeAt + getSweep(position, center, startAngle) * REMOVE_SPREAD, function()
			if not done then
				poof(position)
			end
		end)
	end
	for index = 1, POP_SOUNDS do
		task.delay(buildAt + (index - 1) / POP_SOUNDS * BUILD_SPREAD, function()
			if not done then
				playPop(0.9 + index * 0.06)
			end
		end)
	end
	task.delay(buildAt + BUILD_SPREAD + BUILD_SECONDS, function()
		if not done then
			for light, enabled in lights do
				light.Enabled = enabled
			end
			playSound("UnlockedSheep")
		end
	end)
	task.delay(buildAt + BUILD_SPREAD + BUILD_SECONDS + 0.2, finish)

	return { finish = finish }
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

-- Flies the camera over the pen and back while `swap` plays; returns false if the camera can't be taken right now.
local function playCamera(center: Vector3, size: number, startAngle: number, penName: string, swap: Swap): boolean
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom or not getHumanoid() then
		return false
	end

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

	local function orbitAt(elapsed: number): CFrame
		local angle = startAngle + math.rad(ORBIT_DEGREES) * math.clamp(elapsed / END_AT, 0, 1)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * size * SHOT_DISTANCE + Vector3.new(0, size * SHOT_HEIGHT, 0)
		return CFrame.lookAt(center + offset, center)
	end

	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		runService:UnbindFromRenderStep(RENDER_NAME)
		contextActionService:UnbindAction(SKIP_ACTION)
		for _, connection in connections do
			connection:Disconnect()
		end
		skipRequested = nil
		swap.finish()
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
		local elapsed = os.clock() - startedAt
		returnFrom = camera.CFrame
		returnAt = elapsed
		skipButton.Visible = false
		hideCard()
		swap.finish()
	end
	skipRequested = skip

	local function render()
		local elapsed = os.clock() - startedAt
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
	task.spawn(function()
		pcall(player.RequestStreamAroundAsync, player, center, 2)
	end)

	task.delay(CARD_AT, function()
		if not finished and not returnFrom then
			showCard(penName)
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
	return true
end

skipButton.Activated:Connect(function()
	if skipRequested then
		skipRequested()
	end
end)

--// Unlocks ---------------------------------------------------------------------------

local function onTierChanged(plot: Instance)
	local tier = plot:GetAttribute(TIER_ATTRIBUTE)
	if type(tier) ~= "number" then
		return
	end
	local previous = knownTier
	knownTier = tier
	if not previous or tier <= previous or os.clock() < settledAt then
		cacheFence(plot)
		return
	end

	local oldFence = cachedFence
	cachedFence = nil
	local newFence = getFence(plot)
	local center, size = getAreaBox(plot)
	if not newFence or not center then
		if oldFence then
			oldFence:Destroy()
		end
		cacheFence(plot)
		return
	end

	-- The old fence stays up (and the new one hidden) through the rebirth burst, then the swap plays.
	-- The sweep and the camera both start on the side the player is looking from.
	local camera = workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else center + Vector3.new(0, 0, size)
	local startAngle = math.atan2(from.Z - center.Z, from.X - center.X)
	local penName = plot:GetAttribute(NAME_ATTRIBUTE)
	local swap = playSwap(oldFence, newFence, center, startAngle, START_DELAY)
	task.delay(START_DELAY, function()
		playCamera(center, size, startAngle, if type(penName) == "string" then penName else "New Pen", swap)
	end)
	task.delay(START_DELAY + BUILD_AT + BUILD_SPREAD + BUILD_SECONDS + 0.5, function()
		if ownPlot == plot then
			cacheFence(plot)
		end
	end)
end

local function setOwnPlot(plot: Instance?)
	if plot == ownPlot then
		return
	end
	for _, connection in plotConnections do
		connection:Disconnect()
	end
	table.clear(plotConnections)
	ownPlot = plot
	knownTier = nil
	if cachedFence then
		cachedFence:Destroy()
		cachedFence = nil
	end
	if not plot then
		return
	end

	settledAt = os.clock() + SETTLE_SECONDS
	table.insert(plotConnections, plot:GetAttributeChangedSignal(TIER_ATTRIBUTE):Connect(function()
		onTierChanged(plot)
	end))
	-- First look once the join's own swap is done and the fence has streamed in, so the copy is complete.
	task.delay(SETTLE_SECONDS, function()
		if ownPlot == plot then
			onTierChanged(plot)
		end
	end)
end

local function findOwnPlot()
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute(OWNER_ATTRIBUTE) == player.UserId then
			setOwnPlot(plot)
			return
		end
	end
	setOwnPlot(nil)
end

for _, plot in plotsFolder:GetChildren() do
	plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(findOwnPlot)
end
plotsFolder.ChildAdded:Connect(function(plot: Instance)
	plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(findOwnPlot)
	findOwnPlot()
end)
findOwnPlot()
