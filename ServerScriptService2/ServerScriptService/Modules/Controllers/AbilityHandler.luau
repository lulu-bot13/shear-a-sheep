--!strict

--[[
	Runs abilities: on UseAbility it boosts the player's speed, puts a copy of their shears in the other hand and shears every sheep around them until it ends.
	Clients see the player's "ActiveAbility" attribute to play the animation and spin. Spare offhand shears wait in ReplicatedStorage.Assets.ShearsPool.
	Location: ServerScriptService.Modules.Controllers.AbilityHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local ShearHandler = require(script.Parent.ShearHandler)
local ShearShopHandler = require(script.Parent.ShearShopHandler)
local UpgradeHandler = require(script.Parent.UpgradeHandler)

--// Instances
local assets = replicatedStorage:WaitForChild("Assets")

--// Configs
local REQUEST_COOLDOWN = 0.25
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- the running ability's id, nil when none
local SPEED_ATTRIBUTE = "AbilitySpeedMultiplier" -- read by UpgradeHandler.applyWalkSpeed
local READY_AT_ATTRIBUTE = "AbilityReadyAt" -- server time the ability can be used again
local SHEARS_POOL_NAME = "ShearsPool"
local OFFHAND_GRIP_NAME = "OffhandGrip"

--// State
local readyAt: { [Player]: number } = {}
local offhandShears: { [Player]: Tool } = {}

local AbilityHandler = {}

local function isAlive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

--// Offhand shears -----------------------------------------------------------------

local function getShearsPool(): Folder
	local existing = assets:FindFirstChild(SHEARS_POOL_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = SHEARS_POOL_NAME
	folder.Parent = assets
	return folder
end

-- The left hand (R15) or arm (R6), and where on it a held tool's grip sits.
local function getOffhand(character: Model): (BasePart?, CFrame)
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not hand or not hand:IsA("BasePart") then
		return nil, CFrame.identity
	end

	local attachment = hand:FindFirstChild("LeftGripAttachment")
	if attachment and attachment:IsA("Attachment") then
		return hand, attachment.CFrame
	end
	return hand, CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
end

-- A pooled copy of the equipped shear, else a fresh clone of it with its scripts stripped so it is only for show.
local function takeShears(player: Player): Tool?
	local tool = ShearShopHandler.getTool(player)
	if not tool then
		return nil
	end

	local pooled = getShearsPool():FindFirstChild(tool.Name)
	if pooled and pooled:IsA("Tool") then
		return pooled
	end

	local copy = tool:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	return copy
end

-- Parented under the hand rather than the character, so the Humanoid never equips it as a second tool.
local function equipOffhandShears(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local hand, grip = getOffhand(character)
	local shears = takeShears(player)
	if not hand or not shears then
		return
	end

	local handle = shears:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		shears:Destroy()
		return
	end

	local weld = Instance.new("Weld")
	weld.Name = OFFHAND_GRIP_NAME
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = grip
	weld.C1 = shears.Grip
	weld.Parent = handle
	shears.Parent = hand
	offhandShears[player] = shears
end

local function storeOffhandShears(player: Player)
	local shears = offhandShears[player]
	offhandShears[player] = nil
	if not shears or not shears.Parent then
		return -- destroyed along with the character
	end

	local weld = shears:FindFirstChild(OFFHAND_GRIP_NAME, true)
	if weld then
		weld:Destroy()
	end
	shears.Parent = getShearsPool()
end

--// Ability ------------------------------------------------------------------------

-- The cooldown starts once the ability is over.
local function endAbility(player: Player, ability: AbilityData.AbilityInfo)
	readyAt[player] = os.clock() + ability.cooldown
	player:SetAttribute(READY_AT_ATTRIBUTE, workspace:GetServerTimeNow() + ability.cooldown)
	player:SetAttribute(ACTIVE_ATTRIBUTE, nil)
	player:SetAttribute(SPEED_ATTRIBUTE, nil)
	UpgradeHandler.applyWalkSpeed(player)
end

local function runAbility(player: Player, ability: AbilityData.AbilityInfo)
	local character = player.Character
	player:SetAttribute(ACTIVE_ATTRIBUTE, ability.id)
	player:SetAttribute(SPEED_ATTRIBUTE, ability.speedMultiplier)
	UpgradeHandler.applyWalkSpeed(player)
	equipOffhandShears(player)

	local endsAt = os.clock() + ability.duration
	while os.clock() < endsAt and player.Parent and player.Character == character and isAlive(player) do
		ShearHandler.shearAround(player, ability.rangeMultiplier, ability.damageMultiplier)
		task.wait(ability.hitInterval)
	end

	storeOffhandShears(player)
	if player.Parent then
		endAbility(player, ability)
	end
end

local function onUseAbility(player: Player)
	local now = os.clock()
	if now < (readyAt[player] or 0) or player:GetAttribute(ACTIVE_ATTRIBUTE) or not isAlive(player) then
		return
	end

	local ability = AbilityData.get(AbilityData.DefaultAbilityId)
	if not ability then
		return
	end

	task.spawn(runAbility, player, ability)
end

function AbilityHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.UseAbility, onUseAbility, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})

	players.PlayerAdded:Connect(function()
		getShearsPool()
	end)
	if #players:GetPlayers() > 0 then
		getShearsPool()
	end

	players.PlayerRemoving:Connect(function(player: Player)
		readyAt[player] = nil
	end)
end

return AbilityHandler
