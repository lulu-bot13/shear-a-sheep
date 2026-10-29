--!strict

--[[
	Bat Overhaul: a swarm of bats covers the player's plot while their shears snip the wool off every sheep, then the bats leave them all bare.
	The server holds the sheep and shears them in pulses on the clients' timeline; the clients draw the bats and the flying shears.
	Location: ServerScriptService.Modules.Abilities.BatOverhaul
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local PlotHandler = require(script.Parent.Parent.Controllers.PlotHandler)
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)
local ShearHandler = require(script.Parent.Parent.Controllers.ShearHandler)
local SheepWanderHandler = require(script.Parent.Parent.Controllers.SheepWanderHandler)

--// Configs
local START_LEAD = 0.2 -- seconds between telling the clients and the bats setting off, so they start on time

-- One sheep under the swarm.
type Target = {
	sheep: Model,
	id: number,
}

local BatOverhaul = {}

local function getHealth(sheep: Model): number
	local health = sheep:GetAttribute("ShearHealth")
	return if type(health) == "number" then health else 0
end

-- False once the sheep was removed or pooled (and maybe reused as a different sheep).
local function isStillThere(target: Target): boolean
	return SheepHandler.getSheep(target.id) == target.sheep
end

local function collectSheep(player: Player, maxSheep: number): { Target }
	local targets: { Target } = {}
	for id, sheep in SheepHandler.getAllSheep() do
		if #targets >= maxSheep then
			break
		end
		if SheepHandler.getOwnerId(sheep) == player.UserId and getHealth(sheep) > 0 then
			table.insert(targets, { sheep = sheep, id = id })
		end
	end
	return targets
end

-- The SheepArea's box on the player's plot, so the bats cover all of it and not only where the sheep are.
local function getArea(player: Player): (CFrame?, Vector3?)
	local plot = PlotHandler.getPlayerPlot(player)
	local area = plot and plot:FindFirstChild(FarmData.SheepAreaName)
	if area and area:IsA("BasePart") then
		return area.CFrame, area.Size
	elseif area and area:IsA("Model") then
		return area:GetBoundingBox()
	end
	return nil, nil
end

local function getWoolly(targets: { Target }, minHealth: number): { Model }
	local models: { Model } = {}
	for _, target in targets do
		if isStillThere(target) and getHealth(target.sheep) > minHealth then
			table.insert(models, target.sheep)
		end
	end
	return models
end

-- Snips a share of the wool off each sheep, leaving 1 so none is finished (and vanishes) while the bats still cover it.
local function snipWool(player: Player, targets: { Target }, pulsesLeft: number)
	ShearHandler.shearSheep(player, getWoolly(targets, 1), function(sheep: Model): number
		return (getHealth(sheep) - 1) / pulsesLeft
	end)
end

local function playSwarm(player: Player, ability: AbilityData.AbilityInfo, targets: { Target }, startsAt: number)
	local stats = ability.stats
	local pulses = math.max(math.floor(stats.snipPulses), 1)

	task.wait(math.max(startsAt - workspace:GetServerTimeNow(), 0) + stats.arriveSeconds)
	for pulse = 1, pulses do
		if not player.Parent then
			return
		end
		snipWool(player, targets, pulses - pulse + 1)
		task.wait(stats.swarmSeconds / pulses)
	end

	task.wait(stats.leaveSeconds)
	if player.Parent then
		ShearHandler.shearSheep(player, getWoolly(targets, 0), function(_, maxHealth: number): number
			return maxHealth
		end)
	end
end

function BatOverhaul.run(player: Player, ability: AbilityData.AbilityInfo): boolean?
	local stats = ability.stats
	local startedAt = os.clock()
	local targets = collectSheep(player, stats.maxSheep)
	if #targets == 0 then
		return false
	end

	local effectSheep = {}
	for _, target in targets do
		SheepWanderHandler.holdSheep(target.sheep)
		table.insert(effectSheep, {
			sheep = target.sheep,
			color = SheepHandler.getWoolColor(target.sheep),
		})
	end

	local areaCFrame, areaSize = getArea(player)
	local startsAt = workspace:GetServerTimeNow() + START_LEAD
	network.fireAllClients(network.RemoteEvents.AbilityEffect, player, ability.id, {
		startsAt = startsAt,
		arriveSeconds = stats.arriveSeconds,
		swarmSeconds = stats.swarmSeconds,
		leaveSeconds = stats.leaveSeconds,
		snipPulses = math.max(math.floor(stats.snipPulses), 1),
		areaCFrame = areaCFrame,
		areaSize = areaSize,
		sheep = effectSheep,
	})

	playSwarm(player, ability, targets, startsAt)
	task.wait(math.max(ability.duration - (os.clock() - startedAt), 0))
end

return BatOverhaul
