--!strict

--[[
	Spin: equips the shears, boosts speed, holds a spare shear in the other hand and shears everything around the player.
	Location: ServerScriptService.Modules.Abilities.Spin
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local AbilityUtil = require(script.Parent.AbilityUtil)
local ShearHandler = require(script.Parent.Parent.Controllers.ShearHandler)
local ShearShopHandler = require(script.Parent.Parent.Controllers.ShearShopHandler)
local UpgradeHandler = require(script.Parent.Parent.Controllers.UpgradeHandler)

--// Instances
local assets = replicatedStorage:WaitForChild("Assets")

--// Configs
local SPEED_ATTRIBUTE = "AbilitySpeedMultiplier" -- read by UpgradeHandler.applyWalkSpeed
local SHEARS_POOL_NAME = "ShearsPool" -- spare offhand shears wait in ReplicatedStorage.Assets
local OFFHAND_GRIP_NAME = "OffhandGrip"

local Spin = {}

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
local function equipOffhandShears(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local hand, grip = getOffhand(character)
	local shears = takeShears(player)
	if not hand or not shears then
		return nil
	end

	local handle = shears:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		shears:Destroy()
		return nil
	end

	local weld = Instance.new("Weld")
	weld.Name = OFFHAND_GRIP_NAME
	weld.Part0 = hand
	weld.Part1 = handle
	weld.C0 = grip
	weld.C1 = shears.Grip
	weld.Parent = handle
	shears.Parent = hand
	return shears
end

local function storeOffhandShears(shears: Tool?)
	if not shears or not shears.Parent then
		return -- destroyed along with the character
	end

	local weld = shears:FindFirstChild(OFFHAND_GRIP_NAME, true)
	if weld then
		weld:Destroy()
	end
	shears.Parent = getShearsPool()
end

function Spin.run(player: Player, ability: AbilityData.AbilityInfo)
	local stats = ability.stats
	local character = player.Character
	player:SetAttribute(SPEED_ATTRIBUTE, stats.speedMultiplier)
	UpgradeHandler.applyWalkSpeed(player)
	AbilityUtil.equipMainShears(player)
	local offhand = equipOffhandShears(player)

	local endsAt = os.clock() + ability.duration
	while os.clock() < endsAt and AbilityUtil.isStillActive(player, character) do
		ShearHandler.shearAround(player, stats.rangeMultiplier, stats.damageMultiplier)
		task.wait(stats.hitInterval)
	end

	storeOffhandShears(offhand)
	player:SetAttribute(SPEED_ATTRIBUTE, nil)
	if player.Parent then
		UpgradeHandler.applyWalkSpeed(player)
	end
end

return Spin
