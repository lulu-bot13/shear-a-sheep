--!strict

--[[
	Hitbox shearing: every swing of the held shear takes its damage (with the Shear Damage upgrade) off each of the player's sheep within its range.
	Each hit pays out its share of the sheep's wool (with the Prestige and More Wool multipliers) and Luck; a sheep shorn bare leaves the farm.

	Location: ServerScriptService.Modules.Controllers.ShearHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PrestigeData = require(script.Parent.Parent.Constants.PrestigeData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local GemHandler = require(script.Parent.GemHandler)
local IndexHandler = require(script.Parent.IndexHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)
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

-- What the client is told about the wool and Luck one hit knocked off, for the drops on the ground.
type Drop = {
	position: Vector3,
	wool: number,
	luck: number,
	fraction: number, -- of the sheep's full health this hit took off
	luckDrops: boolean, -- show only Luck on the ground
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

-- Wool for shearing this sheep bare: its own wool times the Prestige, More Wool and podium multipliers.
local function getWoolReward(player: Player, sheep: Model): number
	local baseWool = sheep:GetAttribute("WoolAmount")
	local multiplier = PrestigeData.getWoolMultiplier(getNumber(player, "Prestiges"))
		* UpgradeData.getMoreWoolMultiplier(getNumber(player, "MoreWoolLevel"))
		* PodiumBonusHandler.getWoolMultiplier(player)
	return math.floor((if type(baseWool) == "number" then baseWool else 0) * multiplier)
end

-- Wool one swing of the equipped shear takes off, with the Shear Damage upgrade.
local function getShearDamage(player: Player): number
	local shear = ShearShopHandler.getShear(player)
	return UpgradeData.getShearDamage(shear.damage, getNumber(player, "DamageLevel"))
end
ShearHandler.getShearDamage = getShearDamage

-- Mirrored for the client, so the tutorial can count the swings a sheep needs.
local function updateDamageAttribute(player: Player)
	player:SetAttribute("ShearDamage", getShearDamage(player))
end

-- How much of `total` has been earned once the sheep is down to `health`; each hit pays the difference, so the hits add up to `total`.
local function getEarnedShare(total: number, maxHealth: number, health: number): number
	return math.floor(total * (maxHealth - health) / maxHealth)
end

-- The player's sheep whose root is inside the hitbox circle around `center`.
function ShearHandler.getSheepInRange(player: Player, center: Vector3, range: number): { Model }
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
		AnnouncementHandler.bestFind(player, sheepType)
	end
end

--// Shearing ----------------------------------------------------------------------

-- Pays out the wool and Luck a hit taking the sheep from `health` to `newHealth` knocked off; nil when it was nothing.
local function payHit(player: Player, sheep: Model, health: number, newHealth: number, position: Vector3): Drop?
	local maxAttribute = sheep:GetAttribute("MaxShearHealth")
	local luckAttribute = sheep:GetAttribute("LuckAmount")
	local maxHealth: number = if type(maxAttribute) == "number" and maxAttribute > 0 then maxAttribute else health
	local totalLuck: number = if type(luckAttribute) == "number" then luckAttribute else 0
	local totalWool = getWoolReward(player, sheep)

	local wool = getEarnedShare(totalWool, maxHealth, newHealth) - getEarnedShare(totalWool, maxHealth, health)
	local luck = getEarnedShare(totalLuck, maxHealth, newHealth) - getEarnedShare(totalLuck, maxHealth, health)
	if wool > 0 then
		PlayerDataHandler.increment(player, "Wool", wool)
	end
	if luck > 0 then
		PlayerDataHandler.increment(player, "Luck", luck)
	end
	if wool <= 0 and luck <= 0 then
		return nil
	end

	local sheepType = sheep:GetAttribute("SheepType")
	local info = if type(sheepType) == "string" then SheepData.Sheep[sheepType] else nil
	return {
		position = position,
		wool = wool,
		luck = luck,
		fraction = (health - newHealth) / maxHealth,
		luckDrops = info ~= nil and info.luckDrops == true,
	}
end

-- The sheep is bare: count it, add it to the Index, roll its Gem drop and have it vanish a second later.
local function finishSheep(player: Player, sheep: Model, sheepId: number)
	local sheepType = sheep:GetAttribute("SheepType")

	SheepHandler.vanishSheep(sheepId)
	updateBestFind(player, sheepType)
	IndexHandler.discover(player, sheepType, sheep)
	PlayerDataHandler.increment(player, "SheepShearedCount", 1)
	GemHandler.rollSheepDrop(player)
end

--[[
	Hits each of these sheep once for `getDamage(sheep, maxHealth)` wool (or a flat number), paying out and finishing
	bare sheep like a swing does. `holdSheep = false` skips stopping them from wandering (the caller is moving them).
]]
function ShearHandler.shearSheep(
	player: Player,
	targets: { Model },
	getDamage: number | (sheep: Model, maxHealth: number) -> number,
	holdSheep: boolean?
)
	local hits: { Hit } = {}
	local drops: { Drop } = {}

	for _, sheep in targets do
		local sheepId = sheep:GetAttribute("id")
		local health = sheep:GetAttribute("ShearHealth")
		local maxHealth = sheep:GetAttribute("MaxShearHealth")
		local root = getRootPart(sheep)
		if type(sheepId) ~= "number" or type(health) ~= "number" or health <= 0 or not root or not SheepHandler.getSheep(sheepId)
			or sheep:GetAttribute("Rising")
		then
			continue
		end

		local rawDamage = if type(getDamage) == "number"
			then getDamage
			else getDamage(sheep, if type(maxHealth) == "number" then maxHealth else health)
		local damage = math.min(math.max(math.floor(rawDamage), 1), health)
		local newHealth = health - damage
		local position = root.Position
		table.insert(hits, {
			sheep = if newHealth > 0 then sheep else nil, -- a bare sheep is pooled away before the client could flash it
			position = position,
			damage = damage,
			color = SheepHandler.getWoolColor(sheep),
		})

		local drop = payHit(player, sheep, health, newHealth, position)
		if drop then
			table.insert(drops, drop)
		end

		sheep:SetAttribute("ShearHealth", newHealth)
		if newHealth <= 0 then
			finishSheep(player, sheep, sheepId)
		elseif holdSheep ~= false then
			SheepWanderHandler.holdSheep(sheep)
		end
	end

	if #hits > 0 then
		ShearShopHandler.registerSnip(player)
		network.fireClient(network.RemoteEvents.ShearHit, player, hits)
	end
	if #drops > 0 then
		network.fireClient(network.RemoteEvents.SheepSheared, player, drops)
	end
end

-- Shears every one of the player's sheep within the equipped shear's range (times `rangeMultiplier`) once.
function ShearHandler.shearAround(player: Player, rangeMultiplier: number?, damageMultiplier: number?)
	local playerRoot = getRootPart(player.Character)
	if not playerRoot then
		return
	end

	local shear = ShearShopHandler.getShear(player)
	local range = shear.range * (rangeMultiplier or 1) + ShearData.RangeTolerance
	local targets = ShearHandler.getSheepInRange(player, playerRoot.Position, range)
	ShearHandler.shearSheep(player, targets, getShearDamage(player) * (damageMultiplier or 1))
end

local function onShearSwing(player: Player)
	local now = os.clock()
	if now - (lastSwing[player] or 0) < ShearData.SwingCooldown * COOLDOWN_LENIENCY then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not ShearShopHandler.getHeldTool(player) then
		return
	end
	lastSwing[player] = now

	ShearHandler.shearAround(player)
end

--// Lifecycle ---------------------------------------------------------------------

function ShearHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.ShearSwing, onShearSwing)

	PlayerDataHandler.Loaded:Connect(updateDamageAttribute)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "ShearId" or key == "DamageLevel" then
			updateDamageAttribute(player)
		end
	end)
	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) then
			updateDamageAttribute(player)
		end
	end

	players.PlayerRemoving:Connect(function(player: Player)
		lastSwing[player] = nil
	end)
end

return ShearHandler
