--[[
	Uses the player's ability (aimed at the mouse, or straight ahead on touch) on E, the Ability ui or the touch button by the jump button, and plays its animation and Modules.Abilities effect.
	Shows the cooldown on Main.Ability and routes AbilityEffect broadcasts to each ability's module so everyone sees the VFX.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AbilityClient
]]--

--// Services
local contextActionService = game:GetService("ContextActionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local userInputService = game:GetService("UserInputService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityAnimations = replicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Abilities")
local abilityModules = script.Parent.Parent.Modules.Abilities

--// Sounds
local abilityStartSound = soundService:WaitForChild("UISounds"):FindFirstChild("ShearAbilityStart")

--// Configs
local ABILITY_KEY = Enum.KeyCode.E
local ABILITY_ACTION = "UseAbility"
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs
local READY_AT_ATTRIBUTE = "AbilityReadyAt" -- server time the ability can be used again
local EQUIPPED_ATTRIBUTE = "AbilityEquipped" -- mirrored from PlayerDataHandler
local SHEAR_RANGE_ATTRIBUTE = "ShearRange" -- set on every shear Tool by ShearShopHandler
local CARRY_ATTRIBUTE = "CarryingSheep" -- set by SheepCarryHandler while a sheep is carried
local CROOK_NAME = "ShepherdsCrook"
local USED_COLOR = Color3.fromRGB(120, 120, 120) -- while active and cooling down
local READY_TEXT = "[E] Ability"
local TOUCH_AIM_DISTANCE = 40 -- studs ahead of the character an ability is aimed without a mouse
local AIM_RAY_LENGTH = 500

--// Mobile ability button
local ABILITY_BUTTON_IMAGE = "" -- the mobile button's icon (rbxassetid://...); blank until one is made
local MOBILE_BUTTON_NAME = "MobileAbility" -- a Studio-made Main.MobileAbility is used instead of the built one
local MOBILE_BUTTON_SCALE = 0.9 -- of the jump button's size
local MOBILE_BUTTON_GAP = 12 -- pixels between it and the jump button
local MOBILE_BUTTON_COLOR = Color3.fromRGB(255, 190, 60)
local MOBILE_OVERLAY_TRANSPARENCY = 0.4

type AbilityModule = {
	loopAnimation: boolean?,
	start: ((character: Model, humanoid: Humanoid) -> () -> ())?,
	onEffect: ((caster: Player, ...any) -> ())?,
}

--// State
local abilityTrack: AnimationTrack? = nil
local stopEffect: (() -> ())? = nil
local cooldownConnection: RBXScriptConnection? = nil
local loadedModules: { [string]: AbilityModule | false } = {}
local normalColors: { [GuiObject]: Color3 } = setmetatable({}, { __mode = "k" }) :: any -- each Ability ui's Studio color
local usingTouch = userInputService.TouchEnabled
	and (not userInputService.KeyboardEnabled or userInputService:GetLastInputType() == Enum.UserInputType.Touch)

--// Cooldown label --------------------------------------------------------------

-- Looked up each time: the Main gui may be rebuilt on respawn.
local function getAbilityUi(): GuiObject?
	local main = playerGui:FindFirstChild("Main")
	local ability = main and main:FindFirstChild("Ability")
	return if ability and ability:IsA("GuiObject") then ability else nil
end

local function getAbilityLabel(name: string): TextLabel?
	local ability = getAbilityUi()
	local label = ability and ability:FindFirstChild(name)
	return if label and label:IsA("TextLabel") then label else nil
end

local function updateAbilityName()
	local label = getAbilityLabel("AbilityName")
	local abilityId = player:GetAttribute(EQUIPPED_ATTRIBUTE)
	if label and type(abilityId) == "string" then
		label.Text = `[{abilityId}]`
	end
end

local function isHoldingShear(): boolean
	local character = player.Character
	if not character then
		return false
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute(SHEAR_RANGE_ATTRIBUTE) ~= nil then
			return true
		end
	end
	return false
end

-- The crook is out or a sheep is being carried: no abilities until it's placed or let go.
local function isUsingCrook(): boolean
	local character = player.Character
	return player:GetAttribute(CARRY_ATTRIBUTE) ~= nil or (character ~= nil and character:FindFirstChild(CROOK_NAME) ~= nil)
end

local function canShowAbility(): boolean
	return isHoldingShear() and not isUsingCrook() and not windowsManager.anyOpen()
end

-- Shown only while a shear is held, and hidden while any window is open so it doesn't sit on top of the menus.
-- Touch players get the mobile button instead.
local function updateAbilityVisibility()
	local abilityUi = getAbilityUi()
	if abilityUi then
		abilityUi.Visible = not usingTouch and canShowAbility()
	end
end

local function getSecondsLeft(): number
	local readyAt = player:GetAttribute(READY_AT_ATTRIBUTE)
	return if type(readyAt) == "number" then math.max(readyAt - workspace:GetServerTimeNow(), 0) else 0
end

local function updateCooldownLabel()
	local secondsLeft = getSecondsLeft()
	local isActive = player:GetAttribute(ACTIVE_ATTRIBUTE) ~= nil
	local abilityUi = getAbilityUi()
	if abilityUi then
		local normalColor = normalColors[abilityUi] or abilityUi.BackgroundColor3
		normalColors[abilityUi] = normalColor
		abilityUi.BackgroundColor3 = if isActive or secondsLeft > 0 then USED_COLOR else normalColor
	end

	local label = getAbilityLabel("Cooldown")
	if label then
		if isActive then
			label.Text = `{READY_TEXT} active`
		elseif secondsLeft > 0 then
			label.Text = `{READY_TEXT} {string.format("%.1f", secondsLeft)}s`
		else
			label.Text = READY_TEXT
		end
	end

	if secondsLeft <= 0 and cooldownConnection then
		cooldownConnection:Disconnect()
		cooldownConnection = nil
	end
end

local function onReadyAtChanged()
	updateCooldownLabel()
	if getSecondsLeft() > 0 and not cooldownConnection then
		cooldownConnection = runService.Heartbeat:Connect(updateCooldownLabel)
	end
end

--// Ability ------------------------------------------------------------------------

-- The Animation for this ability: either the child itself or the first Animation inside it.
local function getAnimation(abilityId: string): Animation?
	local asset = abilityAnimations:FindFirstChild(abilityId)
	if asset and asset:IsA("Animation") then
		return asset
	end
	return asset and asset:FindFirstChildWhichIsA("Animation", true)
end

local function getModule(abilityId: string): AbilityModule?
	local cached = loadedModules[abilityId]
	if cached ~= nil then
		return cached or nil
	end

	local moduleScript = abilityModules:FindFirstChild(abilityId)
	local loaded = moduleScript and moduleScript:IsA("ModuleScript") and require(moduleScript) :: any
	loadedModules[abilityId] = loaded or false
	return loaded or nil
end

local function stopAbility()
	if stopEffect then
		local stop = stopEffect
		stopEffect = nil
		stop()
	end
	if abilityTrack then
		abilityTrack:Stop()
		abilityTrack:Destroy()
		abilityTrack = nil
	end
end

local function startAbility(abilityId: string)
	stopAbility()

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end

	if abilityStartSound and abilityStartSound:IsA("Sound") then
		abilityStartSound:Play()
	end

	local abilityModule = getModule(abilityId)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animation = getAnimation(abilityId)
	if animator and animation then
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = abilityModule ~= nil and abilityModule.loopAnimation == true
		track:Play()
		abilityTrack = track
	else
		warn(`AbilityClient: no Animation for ability "{abilityId}" in {abilityAnimations:GetFullName()}.`)
	end

	if abilityModule and abilityModule.start then
		stopEffect = abilityModule.start(character, humanoid)
	end
end

-- Where the ability is aimed: the world point under the mouse, or straight ahead of the character on touch and gamepad.
local function getAimPoint(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local lastInput = userInputService:GetLastInputType()
	local usingMouse = lastInput == Enum.UserInputType.MouseButton1
		or lastInput == Enum.UserInputType.MouseMovement
		or lastInput == Enum.UserInputType.Keyboard
	local camera = workspace.CurrentCamera
	if not usingMouse or not camera then
		return root.Position + root.CFrame.LookVector * TOUCH_AIM_DISTANCE
	end

	local mouse = userInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * AIM_RAY_LENGTH, params)
	return if result then result.Position else ray.Origin + ray.Direction * AIM_RAY_LENGTH
end

local function onActiveAbilityChanged()
	local abilityId = player:GetAttribute(ACTIVE_ATTRIBUTE)
	if type(abilityId) == "string" then
		startAbility(abilityId)
	else
		stopAbility()
	end
	updateCooldownLabel()
end

player:GetAttributeChangedSignal(ACTIVE_ATTRIBUTE):Connect(onActiveAbilityChanged)
player:GetAttributeChangedSignal(READY_AT_ATTRIBUTE):Connect(onReadyAtChanged)
player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(updateAbilityName)
player:GetAttributeChangedSignal(CARRY_ATTRIBUTE):Connect(updateAbilityVisibility)
local function onCharacterAdded(character: Model)
	stopAbility()
	character.ChildAdded:Connect(updateAbilityVisibility)
	character.ChildRemoved:Connect(updateAbilityVisibility)
	updateAbilityVisibility()
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end
windowsManager.openChanged:Connect(updateAbilityVisibility)
onActiveAbilityChanged()
onReadyAtChanged()
updateAbilityName()
updateAbilityVisibility()

network.waitUntilReadyAsync()

local function useAbility()
	if not isUsingCrook() then
		network.fireServer(network.RemoteEvents.UseAbility, getAimPoint())
	end
end

network.connectEvent(network.RemoteEvents.AbilityEffect, function(caster: Player, abilityId: string, ...: any)
	local abilityModule = type(abilityId) == "string" and getModule(abilityId)
	if abilityModule and abilityModule.onEffect then
		abilityModule.onEffect(caster, ...)
	end
end)

-- Tapping or clicking the Ability ui uses it too, so touch players aren't stuck without an E key.
local boundAbilityUi: GuiObject? = nil

local function bindAbilityUi(main: Instance)
	local ability = main:WaitForChild("Ability", 10)
	if not ability or ability == boundAbilityUi then
		return
	end

	updateAbilityName()
	updateCooldownLabel()
	updateAbilityVisibility()

	if ability:IsA("GuiButton") then
		boundAbilityUi = ability
		ability.Activated:Connect(useAbility)
	elseif ability:IsA("GuiObject") then
		boundAbilityUi = ability
		ability.Active = true
		ability.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				useAbility()
			end
		end)
	end
end

playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "Main" then
		bindAbilityUi(child)
	end
end)
local main = playerGui:FindFirstChild("Main")
if main then
	task.spawn(bindAbilityUi, main)
end

-- No CAS touch button: the Main gui's Ability ui and the mobile button below cover touch.
contextActionService:BindAction(ABILITY_ACTION, function(_, inputState: Enum.UserInputState)
	-- Passed on with the crook out, so E still reaches the podium prompts.
	if inputState ~= Enum.UserInputState.Begin or isUsingCrook() then
		return Enum.ContextActionResult.Pass
	end
	useAbility()
	return Enum.ContextActionResult.Sink
end, false, ABILITY_KEY)

--// Mobile ability button ------------------------------------------------------------

-- A thumb-sized button by the jump button on touch screens; a Studio-made Main.MobileAbility replaces the built one.
local builtMobileButton: ImageButton? = nil
local boundMobileButtons: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local mobileCooldownConnection: RBXScriptConnection? = nil
local cooldownTotal = 0 -- length of the current cooldown, for the overlay's fill

-- Size, left edge and top edge (offsets from the bottom-right corner) of the PlayerModule's touch jump button.
local function getJumpLayout(): (number, number, number)
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.zero
	if math.min(viewport.X, viewport.Y) <= 500 then
		return 70, 95, 90
	end
	return 120, 170, 210
end

local function addCorner(guiObject: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = guiObject
end

local function addLabel(name: string, parent: GuiObject): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ""
	label.ZIndex = 3
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
	return label
end

local function buildMobileButton(): ImageButton
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileAbility"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local button = Instance.new("ImageButton")
	button.Name = MOBILE_BUTTON_NAME
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Image = ABILITY_BUTTON_IMAGE
	button.ScaleType = Enum.ScaleType.Fit
	button.BackgroundColor3 = MOBILE_BUTTON_COLOR
	button.BackgroundTransparency = 0.15
	button.Visible = false
	button.Parent = gui
	addCorner(button)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 3
	stroke.Parent = button

	-- Darkens the top share of the button still cooling down; the gradient keeps it inside the round corners.
	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = MOBILE_OVERLAY_TRANSPARENCY
	overlay.Visible = false
	overlay.ZIndex = 2
	overlay.Parent = button
	addCorner(overlay)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = overlay

	local cooldownLabel = addLabel("Cooldown", button)
	cooldownLabel.Position = UDim2.fromScale(0.5, 0.5)
	cooldownLabel.Size = UDim2.fromScale(0.7, 0.4)

	local nameLabel = addLabel("AbilityName", button)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 1, 2)
	nameLabel.Size = UDim2.fromScale(1.4, 0.28)

	return button
end

local function layoutBuiltButton(button: ImageButton)
	local jumpSize, jumpLeft, jumpTop = getJumpLayout()
	local size = math.floor(jumpSize * MOBILE_BUTTON_SCALE)
	button.Size = UDim2.fromOffset(size, size)
	button.Position = UDim2.new(1, -(jumpLeft + MOBILE_BUTTON_GAP), 1, -jumpTop)
end

-- Main.MobileAbility when Studio has one, else the built button (made on first need, touch devices only).
local function getMobileButton(): GuiButton?
	local mainGui = playerGui:FindFirstChild("Main")
	local studioButton = mainGui and mainGui:FindFirstChild(MOBILE_BUTTON_NAME)
	local button: GuiButton? = nil
	if studioButton and studioButton:IsA("GuiButton") then
		button = studioButton
		if builtMobileButton then
			builtMobileButton.Visible = false
		end
	elseif userInputService.TouchEnabled then
		if not builtMobileButton then
			builtMobileButton = buildMobileButton()
		end
		button = builtMobileButton
	end

	if button and not boundMobileButtons[button] then
		boundMobileButtons[button] = true
		button.Activated:Connect(useAbility)
	end
	return button
end

local function updateMobileCooldown()
	local secondsLeft = getSecondsLeft()
	if secondsLeft <= 0 and mobileCooldownConnection then
		mobileCooldownConnection:Disconnect()
		mobileCooldownConnection = nil
	end

	local button = getMobileButton()
	if not button then
		return
	end

	local isActive = player:GetAttribute(ACTIVE_ATTRIBUTE) ~= nil
	local overlay = button:FindFirstChild("CooldownOverlay")
	if overlay and overlay:IsA("GuiObject") then
		overlay.Visible = isActive or secondsLeft > 0
		local gradient = overlay:FindFirstChildOfClass("UIGradient")
		if gradient and overlay.Visible then
			local share = if isActive or cooldownTotal <= 0 then 1 else secondsLeft / cooldownTotal
			local edge = math.clamp(share, 0.002, 0.998)
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(edge, 0),
				NumberSequenceKeypoint.new(edge + 0.001, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end

	local label = button:FindFirstChild("Cooldown")
	if label and label:IsA("TextLabel") then
		label.Text = if isActive then "Active" elseif secondsLeft > 0 then string.format("%.1f", secondsLeft) else ""
	end
end

local function onMobileReadyAtChanged()
	cooldownTotal = getSecondsLeft()
	updateMobileCooldown()
	if cooldownTotal > 0 and not mobileCooldownConnection then
		mobileCooldownConnection = runService.Heartbeat:Connect(updateMobileCooldown)
	end
end

-- Shown to touch players holding a shear while no window is open, like Main.Ability.
local function updateMobileButton()
	local button = getMobileButton()
	if not button then
		return
	end

	if button == builtMobileButton then
		layoutBuiltButton(button :: ImageButton)
	end
	button.Visible = usingTouch and canShowAbility()

	local nameLabel = button:FindFirstChild("AbilityName")
	if nameLabel and nameLabel:IsA("TextLabel") then
		local abilityId = player:GetAttribute(EQUIPPED_ATTRIBUTE)
		nameLabel.Text = if type(abilityId) == "string" then abilityId else "Ability"
	end
	updateMobileCooldown()
end

local function onMobileCharacterAdded(character: Model)
	character.ChildAdded:Connect(updateMobileButton)
	character.ChildRemoved:Connect(updateMobileButton)
	updateMobileButton()
end

if userInputService.TouchEnabled then
	userInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local wasTouch = usingTouch
		if inputType == Enum.UserInputType.Touch then
			usingTouch = true
		elseif inputType == Enum.UserInputType.Keyboard
			or string.find(inputType.Name, "Mouse", 1, true)
			or string.find(inputType.Name, "Gamepad", 1, true)
		then
			usingTouch = false
		end
		if usingTouch ~= wasTouch then
			updateAbilityVisibility()
			updateMobileButton()
		end
	end)
end

player:GetAttributeChangedSignal(ACTIVE_ATTRIBUTE):Connect(updateMobileCooldown)
player:GetAttributeChangedSignal(READY_AT_ATTRIBUTE):Connect(onMobileReadyAtChanged)
player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(updateMobileButton)
player:GetAttributeChangedSignal(CARRY_ATTRIBUTE):Connect(updateMobileButton)
windowsManager.openChanged:Connect(updateMobileButton)
playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "Main" then
		updateMobileButton()
	end
end)
player.CharacterAdded:Connect(onMobileCharacterAdded)
if player.Character then
	onMobileCharacterAdded(player.Character)
end
onMobileReadyAtChanged()
