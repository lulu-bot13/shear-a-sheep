--!strict

--[[
	Hitbox shearing: every swing of the held shear takes its damage (with the Shear Damage upgrade) off each of the player's sheep within its range.
	A sheep shorn bare pays out wool (with the rebirth and More Wool multipliers) and Luck, then leaves the farm.

	Location: ServerScriptService.Modules.Controllers.ShearHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local IndexHandler = require(script.Parent.IndexHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local ShearShopHandler = require(script.Parent.ShearShopHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// Configs
local COOLDOWN_LENIENCY = 0.8 -- swings may arrive this fraction of the cooldown apart (network jitter bunches them up)

-- What the client is told about each sheep a swing hit.
type Hit = {
	sheep: Model?,
	position: Vector3,
	damage: number,
	color: Color3,
}

--// State
local lastSwing: { [Player]: number } = {}

local ShearHandler = {}

--// Helpers -------------------------------------------------------------------

local function getRootPart(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

-- Wool for shearing this sheep bare: its own wool times the rebirth and More Wool multipliers.
local function getWoolReward(player: Player, sheep: Model): number
	local baseWool = sheep:GetAttribute("WoolAmount")
	local multiplier = RebirthData.getMultiplier(getNumber(player, "Rebirths"))
		* UpgradeData.getMoreWoolMultiplier(getNumber(player, "MoreWoolLevel"))
	return math.floor((if type(baseWool) == "number" then baseWool else 0) * multiplier)
end

-- The player's sheep whose root is inside the hitbox circle around `center`.
local function getSheepInRange(player: Player, center: Vector3, range: number): { Model }
	local found: { Model } = {}
	for _, sheep in SheepHandler.getAllSheep() do
		if SheepHandler.getOwnerId(sheep) ~= player.UserId then
			continue
		end

		local root = getRootPart(sheep)
		if not root then
			continue
		end

		local offset = root.Position - center
		if math.abs(offset.Y) <= ShearData.MaxHeightDifference and Vector3.new(offset.X, 0, offset.Z).Magnitude <= range then
			table.insert(found, sheep)
		end
	end
	return found
end

-- Saves this sheep type as the player's best find when it is rarer (lower base spawn weight) than their current one.
local function updateBestFind(player: Player, sheepType: any)
	local info = if type(sheepType) == "string" then SheepData.Sheep[sheepType] else nil
	if not info then
		return
	end

	local current = PlayerDataHandler.get(player, "BestFind")
	local currentInfo = if type(current) == "string" then SheepData.Sheep[current] else nil
	if not currentInfo or info.chance < currentInfo.chance then
		PlayerDataHandler.set(player, "BestFind", sheepType)
	end
end

--// Shearing ----------------------------------------------------------------------

-- The sheep is bare: pay out wool and Luck, remove it and tell the client where the wool flies from.
local function finishSheep(player: Player, sheep: Model, sheepId: number, origin: Vector3)
	local wool = getWoolReward(player, sheep)
	local luck = sheep:GetAttribute("LuckAmount")
	local sheepType = sheep:GetAttribute("SheepType")
	local color = SheepHandler.getWoolColor(sheep)

	SheepHandler.removeSheep(sheepId)
	updateBestFind(player, sheepType)
	IndexHandler.discover(player, sheepType)
	PlayerDataHandler.increment(player, "Wool", wool)
	PlayerDataHandler.increment(player, "SheepShearedCount", 1)
	if type(luck) == "number" and luck > 0 then
		PlayerDataHandler.increment(player, "Luck", luck)
	end

	network.fireClient(network.RemoteEvents.SheepSheared, player, origin, wool, color)
end

local function onShearSwing(player: Player)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < ShearData.SwingCooldown * COOLDOWN_LENIENCY then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local playerRoot = getRootPart(character)
	if not humanoid or humanoid.Health <= 0 or not playerRoot or not ShearShopHandler.getHeldTool(player) then
		return
	end
	lastSwing[player] = now

	local shear = ShearShopHandler.getShear(player)
	local shearDamage = UpgradeData.getShearDamage(shear.damage, getNumber(player, "DamageLevel"))
	local hits: { Hit } = {}

	for _, sheep in getSheepInRange(player, playerRoot.Position, shear.range + ShearData.RangeTolerance) do
		local sheepId = sheep:GetAttribute("id")
		local health = sheep:GetAttribute("ShearHealth")
		local root = getRootPart(sheep)
		if type(sheepId) ~= "number" or type(health) ~= "number" or health <= 0 or not root then
			continue
		end

		local damage = math.min(shearDamage, health)
		local newHealth = health - damage
		local position = root.Position
		table.insert(hits, {
			sheep = if newHealth > 0 then sheep else nil, -- a bare sheep is pooled away before the client could flash it
			position = position,
			damage = damage,
			color = SheepHandler.getWoolColor(sheep),
		})

		sheep:SetAttribute("ShearHealth", newHealth)
		if newHealth <= 0 then
			finishSheep(player, sheep, sheepId, position)
		else
			SheepWanderHandler.holdSheep(sheep)
		end
	end

	if #hits > 0 then
		ShearShopHandler.registerSnip(player)
		network.fireClient(network.RemoteEvents.ShearHit, player, hits)
	end
end

--// Lifecycle ---------------------------------------------------------------------

function ShearHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.ShearSwing, onShearSwing)

	players.PlayerRemoving:Connect(function(player: Player)
		lastSwing[player] = nil
	end)
end

return ShearHandler
