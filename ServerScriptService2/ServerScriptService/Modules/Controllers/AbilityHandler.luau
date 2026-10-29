--!strict

--[[
	Runs the player's AbilityEquipped ability on UseAbility through its module in Modules.Abilities, then starts its cooldown.
	Clients see the "ActiveAbility" attribute to play its effects; the optional aim point is passed to the module.
	Location: ServerScriptService.Modules.Controllers.AbilityHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local AbilityUtil = require(script.Parent.Parent.Abilities.AbilityUtil)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local UpgradeHandler = require(script.Parent.UpgradeHandler)

--// Instances
local abilityModules = script.Parent.Parent.Abilities

--// Configs
local REQUEST_COOLDOWN = 0.25
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- the running ability's id, nil when none
local READY_AT_ATTRIBUTE = "AbilityReadyAt" -- server time the ability can be used again
local SPEED_ATTRIBUTE = "AbilitySpeedMultiplier" -- read by UpgradeHandler.applyWalkSpeed

type AbilityModule = {
	run: (player: Player, ability: AbilityData.AbilityInfo, aim: Vector3?) -> boolean?, -- false = nothing happened, skip the cooldown
}

--// State
local readyAt: { [Player]: number } = {}
local modules: { [string]: AbilityModule } = {}

local AbilityHandler = {}

local function getModule(id: string): AbilityModule?
	if modules[id] then
		return modules[id]
	end

	local moduleScript = abilityModules:FindFirstChild(id)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(`AbilityHandler: no module for ability "{id}" in Modules.Abilities.`)
		return nil
	end
	modules[id] = require(moduleScript) :: any
	return modules[id]
end

-- The cooldown starts once the ability is over.
local function endAbility(player: Player, ability: AbilityData.AbilityInfo, startCooldown: boolean)
	if startCooldown then
		readyAt[player] = os.clock() + ability.cooldown
		player:SetAttribute(READY_AT_ATTRIBUTE, workspace:GetServerTimeNow() + ability.cooldown)
	end
	player:SetAttribute(ACTIVE_ATTRIBUTE, nil)
end

local function runAbility(player: Player, ability: AbilityData.AbilityInfo, abilityModule: AbilityModule, aim: Vector3?)
	player:SetAttribute(ACTIVE_ATTRIBUTE, ability.id)
	local success, result = pcall(abilityModule.run, player, ability, aim)
	if not success then
		warn(`AbilityHandler: {ability.id} failed for {player.Name}: {result}`)
	end
	if player.Parent then
		-- A module that errored may have left the player boosted or frozen.
		if player:GetAttribute(SPEED_ATTRIBUTE) ~= nil then
			player:SetAttribute(SPEED_ATTRIBUTE, nil)
			UpgradeHandler.applyWalkSpeed(player)
		end
		endAbility(player, ability, not success or result ~= false)
	end
end

local function onUseAbility(player: Player, aim: any)
	local now = os.clock()
	if now < (readyAt[player] or 0) or player:GetAttribute(ACTIVE_ATTRIBUTE) or not AbilityUtil.isAlive(player) then
		return
	end

	local ability = AbilityData.get(PlayerDataHandler.get(player, "AbilityEquipped"))
		or AbilityData.get(AbilityData.DefaultAbilityId)
	local abilityModule = ability and getModule(ability.id)
	if not ability or not abilityModule then
		return
	end

	task.spawn(runAbility, player, ability, abilityModule, if typeof(aim) == "Vector3" then aim else nil)
end

function AbilityHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.UseAbility, onUseAbility, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})

	players.PlayerRemoving:Connect(function(player: Player)
		readyAt[player] = nil
	end)
end

return AbilityHandler
