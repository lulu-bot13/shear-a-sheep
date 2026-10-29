--!strict

--[[
	Smash: plants the player, then slams the ground, shearing every one of their sheep in a wide circle for shear damage plus a share of each sheep's wool.
	Location: ServerScriptService.Modules.Abilities.Smash
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local AbilityUtil = require(script.Parent.AbilityUtil)
local ShearHandler = require(script.Parent.Parent.Controllers.ShearHandler)
local UpgradeHandler = require(script.Parent.Parent.Controllers.UpgradeHandler)

--// Configs
local SPEED_ATTRIBUTE = "AbilitySpeedMultiplier" -- read by UpgradeHandler.applyWalkSpeed
local GROUND_RAY_LENGTH = 12 -- studs below the root the ground is searched for

local Smash = {}

-- The ground under the player, so the clients burst the right spot even mid-jump.
local function getGroundPoint(character: Model, root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = {}
	for _, other in players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	table.insert(ignore, character)
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(root.Position, Vector3.new(0, -GROUND_RAY_LENGTH, 0), params)
	return if result then result.Position else root.Position - Vector3.new(0, 3, 0)
end

function Smash.run(player: Player, ability: AbilityData.AbilityInfo)
	local stats = ability.stats
	local character = player.Character
	local startedAt = os.clock()
	player:SetAttribute(SPEED_ATTRIBUTE, stats.walkSpeedMultiplier)
	UpgradeHandler.applyWalkSpeed(player)

	task.wait(stats.impactDelay)
	local root = AbilityUtil.getRoot(player)
	if character and root and AbilityUtil.isStillActive(player, character) then
		local shearDamage = ShearHandler.getShearDamage(player) * stats.damageMultiplier
		local targets = ShearHandler.getSheepInRange(player, root.Position, stats.radius)
		ShearHandler.shearSheep(player, targets, function(_, maxHealth: number): number
			return shearDamage + maxHealth * stats.woolPercent
		end)
		network.fireAllClients(network.RemoteEvents.AbilityEffect, player, ability.id, getGroundPoint(character, root), stats.radius)
	end

	task.wait(math.max(ability.duration - (os.clock() - startedAt), 0))
	player:SetAttribute(SPEED_ATTRIBUTE, nil)
	if player.Parent then
		UpgradeHandler.applyWalkSpeed(player)
	end
end

return Smash
