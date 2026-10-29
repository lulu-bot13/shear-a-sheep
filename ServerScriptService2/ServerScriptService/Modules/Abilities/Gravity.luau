--!strict

--[[
	Gravity: lifts every one of the player's sheep into the sky, shakes their wool out in pulses while they hang, then drops them back bare.
	The server only anchors them and sets their hang and landing spots; the clients tween the flight in between.
	Location: ServerScriptService.Modules.Abilities.Gravity
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local SheepHandler = require(script.Parent.Parent.Controllers.SheepHandler)
local ShearHandler = require(script.Parent.Parent.Controllers.ShearHandler)
local SheepWanderHandler = require(script.Parent.Parent.Controllers.SheepWanderHandler)

--// Configs
local START_LEAD = 0.2 -- seconds between telling the clients and lifting, so they start the flight on time

-- One sheep in the air and where it goes back to.
type Lifted = {
	sheep: Model,
	id: number,
	root: BasePart,
	base: CFrame,
	wasAnchored: boolean,
}

local Gravity = {}

local function getHealth(sheep: Model): number
	local health = sheep:GetAttribute("ShearHealth")
	return if type(health) == "number" then health else 0
end

-- False once the sheep was sheared bare, removed or pooled (and maybe reused as a different sheep).
local function isStillLifted(entry: Lifted): boolean
	return SheepHandler.getSheep(entry.id) == entry.sheep and entry.root.Parent ~= nil
end

local function collectSheep(player: Player, maxSheep: number): { Lifted }
	local lifted: { Lifted } = {}
	for id, sheep in SheepHandler.getAllSheep() do
		if #lifted >= maxSheep then
			break
		end
		if SheepHandler.getOwnerId(sheep) ~= player.UserId or getHealth(sheep) <= 0 then
			continue
		end

		local root = sheep:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(lifted, {
				sheep = sheep,
				id = id,
				root = root,
				base = root.CFrame,
				wasAnchored = root.Anchored,
			})
		end
	end
	return lifted
end

local function getStillLifted(lifted: { Lifted }): { Model }
	local models: { Model } = {}
	for _, entry in lifted do
		if isStillLifted(entry) then
			table.insert(models, entry.sheep)
		end
	end
	return models
end

-- Pulls a share of the wool off each sheep, leaving 1 so none is finished (and vanished) in mid-air.
local function shakeWool(player: Player, lifted: { Lifted }, pulsesLeft: number)
	local targets: { Model } = {}
	for _, sheep in getStillLifted(lifted) do
		if getHealth(sheep) > 1 then
			table.insert(targets, sheep)
		end
	end

	ShearHandler.shearSheep(player, targets, function(sheep: Model): number
		return (getHealth(sheep) - 1) / pulsesLeft
	end, false)
end

local function land(lifted: { Lifted })
	for _, entry in lifted do
		if isStillLifted(entry) then
			entry.root.CFrame = entry.base
		end
	end
end

-- Any sheep that somehow kept its wool goes back on its spot and walks again.
local function release(lifted: { Lifted })
	for _, entry in lifted do
		if isStillLifted(entry) and getHealth(entry.sheep) > 0 then
			entry.root.CFrame = entry.base
			entry.root.Anchored = entry.wasAnchored
			SheepWanderHandler.holdSheep(entry.sheep)
		end
	end
end

local function playLift(player: Player, ability: AbilityData.AbilityInfo, lifted: { Lifted }, startsAt: number)
	local stats = ability.stats
	local lift = Vector3.new(0, stats.height, 0)
	local pulses = math.max(math.floor(stats.shakePulses), 1)

	task.wait(math.max(startsAt - workspace:GetServerTimeNow(), 0) + stats.riseSeconds)
	for _, entry in lifted do
		if isStillLifted(entry) then
			entry.root.CFrame = entry.base + lift -- the hits and wool drops then come from up in the sky
		end
	end

	for pulse = 1, pulses do
		if player.Parent then
			shakeWool(player, lifted, pulses - pulse + 1)
		end
		task.wait(stats.hangSeconds / pulses)
	end

	task.wait(stats.fallSeconds)
	land(lifted)
	if player.Parent then
		ShearHandler.shearSheep(player, getStillLifted(lifted), function(_, maxHealth: number): number
			return maxHealth
		end, false)
	end
end

function Gravity.run(player: Player, ability: AbilityData.AbilityInfo): boolean?
	local stats = ability.stats
	local startedAt = os.clock()
	local lifted = collectSheep(player, stats.maxSheep)
	if #lifted == 0 then
		return false
	end

	local effectSheep = {}
	for _, entry in lifted do
		SheepWanderHandler.holdSheep(entry.sheep)
		entry.root.AssemblyLinearVelocity = Vector3.zero
		entry.root.Anchored = true
		entry.base = entry.root.CFrame
		table.insert(effectSheep, {
			sheep = entry.sheep,
			base = entry.base,
			color = SheepHandler.getWoolColor(entry.sheep),
		})
	end

	local startsAt = workspace:GetServerTimeNow() + START_LEAD
	network.fireAllClients(network.RemoteEvents.AbilityEffect, player, ability.id, {
		startsAt = startsAt,
		riseSeconds = stats.riseSeconds,
		hangSeconds = stats.hangSeconds,
		fallSeconds = stats.fallSeconds,
		height = stats.height,
		sheep = effectSheep,
	})

	-- Whatever goes wrong, no sheep may be left hanging in the sky.
	local success, err = pcall(playLift, player, ability, lifted, startsAt)
	release(lifted)
	if not success then
		error(err, 0)
	end

	task.wait(math.max(ability.duration - (os.clock() - startedAt), 0))
end

return Gravity
