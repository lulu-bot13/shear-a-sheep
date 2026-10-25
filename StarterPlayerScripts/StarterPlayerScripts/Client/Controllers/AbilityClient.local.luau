--[[
	Uses the player's ability on E or by tapping the Ability ui, then plays its animation and spins the character while AbilityHandler keeps it active.
	Counts the ability's cooldown down on the Main gui's Ability.Cooldown label, greys the button out until it's ready and shows AbilityEquipped on Ability.AbilityName.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AbilityClient
]]--

--// Services
local contextActionService = game:GetService("ContextActionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityAnimations = replicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Abilities")

--// Sounds
local abilityStartSound = soundService:WaitForChild("UISounds"):FindFirstChild("ShearAbilityStart")

--// Configs
local ABILITY_KEY = Enum.KeyCode.E
local ABILITY_ACTION = "UseAbility"
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs
local READY_AT_ATTRIBUTE = "AbilityReadyAt" -- server time the ability can be used again
local EQUIPPED_ATTRIBUTE = "AbilityEquipped" -- mirrored from PlayerDataHandler
local USED_COLOR = Color3.fromRGB(120, 120, 120) -- while active and cooling down
local SPIN_SPEED = math.rad(900) -- radians per second the character turns while spinning
local READY_TEXT = "[E] Ability"

--// State
local abilityTrack: AnimationTrack? = nil
local spinConnection: RBXScriptConnection? = nil
local spinningHumanoid: Humanoid? = nil
local cooldownConnection: RBXScriptConnection? = nil
local normalColors: { [GuiObject]: Color3 } = setmetatable({}, { __mode = "k" }) :: any -- each Ability ui's Studio color

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

-- Hidden while any window is open so it doesn't sit on top of the menus.
local function updateAbilityVisibility()
	local abilityUi = getAbilityUi()
	if abilityUi then
		abilityUi.Visible = not windowsManager.anyOpen()
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

local function stopAbility()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
	if spinningHumanoid then
		spinningHumanoid.AutoRotate = true
		spinningHumanoid = nil
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
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	if abilityStartSound and abilityStartSound:IsA("Sound") then
		abilityStartSound:Play()
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animation = getAnimation(abilityId)
	if animator and animation then
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play()
		abilityTrack = track
	else
		warn(`AbilityClient: no Animation for ability "{abilityId}" in {abilityAnimations:GetFullName()}.`)
	end

	-- AutoRotate off so the humanoid stops turning the character to face its walk direction.
	humanoid.AutoRotate = false
	spinningHumanoid = humanoid
	spinConnection = runService.RenderStepped:Connect(function(deltaTime: number)
		if not root.Parent then
			stopAbility()
			return
		end
		root.CFrame *= CFrame.Angles(0, SPIN_SPEED * deltaTime, 0)
	end)
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
player.CharacterAdded:Connect(stopAbility)
windowsManager.openChanged:Connect(updateAbilityVisibility)
onActiveAbilityChanged()
onReadyAtChanged()
updateAbilityName()
updateAbilityVisibility()

network.waitUntilReadyAsync()

local function useAbility()
	network.fireServer(network.RemoteEvents.UseAbility)
end

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

-- No CAS touch button: the Main gui's Ability ui already covers touch.
contextActionService:BindAction(ABILITY_ACTION, function(_, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	useAbility()
	return Enum.ContextActionResult.Sink
end, false, ABILITY_KEY)
