--[[
	Uses the player's ability on E, then plays its animation and spins the character while AbilityHandler keeps it active.
	Counts the ability's cooldown down on the Main gui's Ability.Cooldown label.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AbilityClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilityAnimations = replicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("Abilities")

--// Configs
local ABILITY_KEY = Enum.KeyCode.E
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs
local READY_AT_ATTRIBUTE = "AbilityReadyAt" -- server time the ability can be used again
local SPIN_SPEED = math.rad(900) -- radians per second the character turns while spinning
local READY_TEXT = "[E] Ability"

--// State
local abilityTrack: AnimationTrack? = nil
local spinConnection: RBXScriptConnection? = nil
local spinningHumanoid: Humanoid? = nil
local cooldownConnection: RBXScriptConnection? = nil

--// Cooldown label --------------------------------------------------------------

-- Looked up each time: the Main gui may be rebuilt on respawn.
local function getCooldownLabel(): TextLabel?
	local main = playerGui:FindFirstChild("Main")
	local ability = main and main:FindFirstChild("Ability")
	local label = ability and ability:FindFirstChild("Cooldown")
	return if label and label:IsA("TextLabel") then label else nil
end

local function getSecondsLeft(): number
	local readyAt = player:GetAttribute(READY_AT_ATTRIBUTE)
	return if type(readyAt) == "number" then math.max(readyAt - workspace:GetServerTimeNow(), 0) else 0
end

local function updateCooldownLabel()
	local secondsLeft = getSecondsLeft()
	local label = getCooldownLabel()
	if label then
		if player:GetAttribute(ACTIVE_ATTRIBUTE) then
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
player.CharacterAdded:Connect(stopAbility)
onActiveAbilityChanged()
onReadyAtChanged()

network.waitUntilReadyAsync()

userInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if not gameProcessed and input.KeyCode == ABILITY_KEY then
		network.fireServer(network.RemoteEvents.UseAbility)
	end
end)
