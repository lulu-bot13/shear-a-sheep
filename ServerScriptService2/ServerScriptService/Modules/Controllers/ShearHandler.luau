--[[
	Server side of the shearing timing mini-game.

	When a player presses START SHEARING in a pen's menu, the sheep is turned side-on, the player is
	snapped to the pen and a run of timing attempts starts. For each attempt the server picks a new
	sweet spot on the timing bar and how the cursor moves, and sends both to the client. The client
	only reports where the cursor was when the player pressed; the server checks the cursor really
	could have been there, scores the press itself (PERFECT / GREAT / GOOD / POOR / MISS), takes the
	wool off the sheep and pays the wool out once, when the sheep is bare. An attempt nobody presses
	in time is a MISS, and shearing just carries on with the next one.

	Tuning: ReplicatedStorage.Shared.Constants.ShearTimingData
	Maths shared with the client: ReplicatedStorage.Shared.Utils.ShearTiming

	Location: ServerScriptService.Modules.Controllers.ShearHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local ShearTiming = require(replicatedStorage.Shared.Utils.ShearTiming)
local ShearTimingData = require(replicatedStorage.Shared.Constants.ShearTimingData)
local SheepHandler = require(script.Parent.SheepHandler)
local InventoryHandler = require(script.Parent.InventoryHandler)
local PenHandler = require(script.Parent.PenHandler)
local ShearShopHandler = require(script.Parent.ShearShopHandler)

--// Configs
local LEAVE_DISTANCE = 9.5 -- how far outside the pen (from its PlayerPos) a player is moved when they leave
local SHEEP_TURN_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOOP_STEP_SECONDS = 0.01 -- how often a waiting attempt checks whether it was pressed (the next one is sent right after)

type Attempt = ShearTiming.Attempt & {
	sentAt: number,
	resolved: boolean,
}

type Session = {
	player: Player,
	pen: any,
	sheep: Model,
	sheepId: number,
	active: boolean,
	damageMultiplier: number, -- from the player's shear
	damageScale: number, -- sheep wool / ShearTimingData.StartingWoolHealth (1 when scaling is off)
	zoneScale: number, -- shear * sheep rarity
	cursorSpeed: number, -- bar widths per second
	attemptCounter: number,
	attempt: Attempt?,
	lastSweetSpot: number?,
	random: Random,
	connections: { RBXScriptConnection },
}

local sessions: { [Player]: Session } = {}

-- The pen a player is "stationed" at: set when they start shearing and kept after a sheep is finished,
-- until they leave (so the camera can stay put between sheep).
local stationPens: { [Player]: any } = {}

local shearHandler = {}

--// Helpers -------------------------------------------------------------------

local function getSheepRoot(sheep: Model): BasePart?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Direction from the sheep's spot to the player's spot, flattened to the ground plane.
local function getPenAxis(pen: any): Vector3
	local flat = Vector3.new(pen.playerPosition.X - pen.sheepPosition.X, 0, pen.playerPosition.Z - pen.sheepPosition.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1)
end

-- Flat (ground-plane) distance from a player's character to the pen's PlayerPos; nil without a character.
local function getDistanceToPen(player: Player, pen: any): number?
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return nil
	end

	local offset = rootPart.Position - pen.playerPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

-- Turns the sheep so its flank (not its head) faces the player and the camera.
local function turnSheepSideOn(pen: any, sheep: Model)
	local root = getSheepRoot(sheep)
	if not root then
		return
	end

	local towardPlayer = getPenAxis(pen)
	-- The camera sits behind the sheep looking at the player, so the sheep's head points to the camera's right.
	local headDirection = towardPlayer:Cross(Vector3.yAxis)
	local target = CFrame.lookAt(root.Position, root.Position + headDirection)
	tweenService:Create(root, SHEEP_TURN_TWEEN, { CFrame = target }):Play()
end

-- Turns the sheep back to face the player, like when it first arrived.
local function turnSheepToPlayer(pen: any, sheep: Model)
	local root = getSheepRoot(sheep)
	if not root then
		return
	end

	local towardPlayer = getPenAxis(pen)
	local target = CFrame.lookAt(root.Position, root.Position + towardPlayer)
	tweenService:Create(root, SHEEP_TURN_TWEEN, { CFrame = target }):Play()
end

-- Moves the player onto the pen's PlayerPos, facing the sheep.
local function snapPlayerToPen(player: Player, pen: any)
	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local lookTarget = Vector3.new(pen.sheepPosition.X, pen.playerPosition.Y, pen.sheepPosition.Z)
	humanoidRootPart.CFrame = CFrame.lookAt(pen.playerPosition, lookTarget)
end

-- Puts the player just outside the pen, facing away from it.
local function movePlayerOutOfPen(player: Player, pen: any)
	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local outward = getPenAxis(pen)
	local target = pen.playerPosition + outward * LEAVE_DISTANCE + Vector3.new(0, 3, 0)
	humanoidRootPart.CFrame = CFrame.lookAt(target, target + outward)
end

--// Session lifecycle -----------------------------------------------------------

-- Tears a session down without telling the client (callers do that with the right message).
local function endSession(session: Session)
	if not session.active then
		return
	end

	session.active = false
	sessions[session.player] = nil

	for _, connection in session.connections do
		connection:Disconnect()
	end
	table.clear(session.connections)

	if session.pen.shearingPlayer == session.player then
		session.pen.shearingPlayer = nil
	end

	local currentSheepId = session.player:FindFirstChild("CurrentSheepId") :: IntValue?
	if currentSheepId then
		currentSheepId.Value = 0
	end
end

-- The sheep is bare: pay out the wool (once - the session is ended first), free the pen and tell the client.
local function finishSheep(session: Session)
	local player = session.player
	local sheepId = session.sheepId
	local woolAmount = session.sheep:GetAttribute("WoolAmount") :: number

	endSession(session)
	stationPens[player] = nil

	local newTotal = InventoryHandler.addItem(player, "Wool", woolAmount)
	print(`Added {woolAmount} wool to {player.Name}'s inventory. New total: {newTotal}`)

	SheepHandler.removeSheep(sheepId)
	network.fireClient(network.RemoteEvents.DeactivateShearing, player, true, woolAmount)
	PenHandler.onSheepRemoved(sheepId)
end

-- Takes `damage` wool off the sheep (never below 0). Returns true if that sheared it bare.
local function applyDamage(session: Session, damage: number): boolean
	local sheep = session.sheep
	local health = sheep:GetAttribute("ShearHealth")
	if type(health) ~= "number" or health <= 0 then
		return false
	end

	local newHealth = math.max(health - damage, 0)
	sheep:SetAttribute("ShearHealth", newHealth)

	if newHealth <= 0 then
		finishSheep(session)
		return true
	end
	return false
end

local function computeDamage(session: Session, tier: ShearTiming.Tier, distance: number, zones: ShearTiming.Zones): number
	local base = ShearTiming.getTierDamage(tier, distance, zones)
	return math.max(0, math.round(base * session.damageMultiplier * session.damageScale))
end

-- Settles an attempt exactly once: snip effect for a hit, then the wool comes off.
local function resolveAttempt(session: Session, attempt: Attempt, tier: ShearTiming.Tier, damage: number)
	if attempt.resolved then
		return
	end
	attempt.resolved = true

	if tier ~= "MISS" then
		ShearShopHandler.registerSnip(session.player)
	end
	-- Sent before the damage is applied: a killing blow ends the session (and the sheep) right after.
	network.fireClient(network.RemoteEvents.ShearDamage, session.player, tier, damage)
	if damage > 0 then
		applyDamage(session, damage)
	end
end

-- Picks a new sweet spot and cursor run, records it as the live attempt and sends it to the client.
local function sendAttempt(session: Session)
	session.attemptCounter += 1

	local sweetSpot = ShearTiming.pickSweetSpot(session.lastSweetSpot, session.random)
	session.lastSweetSpot = sweetSpot

	local attempt: Attempt = {
		id = session.attemptCounter,
		sweetSpot = sweetSpot,
		zones = ShearTiming.buildZones(session.zoneScale),
		cursorStart = if session.random:NextNumber() < 0.5 then 0 else 1,
		cursorSpeed = session.cursorSpeed,
		lifetime = ShearTimingData.TimeLimit,
		sentAt = os.clock(),
		resolved = false,
	}
	session.attempt = attempt

	network.fireClient(network.RemoteEvents.ShearAttempt, session.player, {
		id = attempt.id,
		sweetSpot = attempt.sweetSpot,
		zones = attempt.zones,
		cursorStart = attempt.cursorStart,
		cursorSpeed = attempt.cursorSpeed,
		lifetime = attempt.lifetime,
	})
end

-- True while the session's pen, sheep and player are all still valid and the player is still at the pen.
local function isSessionValid(session: Session): boolean
	local character = session.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local distance = getDistanceToPen(session.player, session.pen)
	return session.player.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and distance ~= nil
		and distance <= ShearTimingData.MaxShearingDistance
		and not session.pen.destroyed
		and session.sheep.Parent ~= nil
		and SheepHandler.getSheep(session.sheepId) == session.sheep
end

-- Ends a session that went invalid (player died/left/walked off, pen sold...) and tells the client.
local function abortSession(session: Session)
	if not session.active then
		return
	end

	endSession(session)
	stationPens[session.player] = nil
	if session.player.Parent then
		network.fireClient(network.RemoteEvents.DeactivateShearing, session.player, false)
	end
end

-- Runs attempt after attempt until the sheep is bare or the session is ended.
local function runAttempts(session: Session)
	task.wait(ShearTimingData.FirstAttemptDelay)

	while session.active do
		if not isSessionValid(session) then
			abortSession(session)
			return
		end

		sendAttempt(session)
		local attempt = session.attempt :: Attempt

		-- Presses may arrive up to LatencyAllowance after the client's timer ran out.
		local deadline = attempt.sentAt + attempt.lifetime + ShearTimingData.LatencyAllowance
		while session.active and not attempt.resolved and os.clock() < deadline do
			task.wait(LOOP_STEP_SECONDS)
		end

		if not session.active then
			return
		end

		if not attempt.resolved then
			resolveAttempt(session, attempt, "MISS", ShearTimingData.TimeoutDamage)
			if not session.active then
				return
			end
		end

		task.wait(ShearTimingData.CooldownBetweenAttempts)
	end
end

--// Remote handlers ---------------------------------------------------------------

local function onStartShearing(player: Player, penId: any)
	if typeof(penId) ~= "number" or sessions[player] then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Only the pen's owner gets their pens back from PenHandler, so nobody can shear someone else's sheep.
	local pen = PenHandler.getPen(player, penId)
	if not pen or pen.shearingPlayer or pen.data.automated or not pen.seated or not pen.occupiedSheepId then
		return
	end

	local distance = getDistanceToPen(player, pen)
	if not distance or distance > ShearTimingData.MaxShearingDistance then
		return
	end

	local sheepId = pen.occupiedSheepId
	local sheep = SheepHandler.getSheep(sheepId)
	local currentSheepId = player:FindFirstChild("CurrentSheepId") :: IntValue?
	if not sheep or not currentSheepId then
		return
	end

	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) ~= "number" or health <= 0 or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return -- already bare
	end

	local stats = ShearShopHandler.getStats(player)
	local rarity = ShearTimingData.getRarityModifier(sheep:GetAttribute("Rarity"))

	local session: Session = {
		player = player,
		pen = pen,
		sheep = sheep,
		sheepId = sheepId,
		active = true,
		damageMultiplier = stats.damageMultiplier,
		damageScale = if ShearTimingData.ScaleDamageToWoolHealth then maxHealth / ShearTimingData.StartingWoolHealth else 1,
		zoneScale = stats.zoneScale * rarity.zoneScale,
		cursorSpeed = ShearTimingData.CursorSpeed * stats.cursorSpeed * rarity.cursorSpeed,
		attemptCounter = 0,
		attempt = nil,
		lastSweetSpot = nil,
		random = Random.new(),
		connections = {},
	}
	sessions[player] = session
	stationPens[player] = pen
	pen.shearingPlayer = player
	currentSheepId.Value = sheepId

	table.insert(session.connections, humanoid.Died:Connect(function()
		abortSession(session)
	end))

	snapPlayerToPen(player, pen)
	turnSheepSideOn(pen, sheep)

	print(`{player.Name} started shearing {sheep.Name}.`)
	network.fireClient(network.RemoteEvents.ActivateShearing, player, sheepId, pen.sheepPosition, pen.playerPosition)

	task.spawn(runAttempts, session)
end

local function onStopShearing(player: Player)
	shearHandler.leavePen(player)
end

-- The client pressed: `position` is where it says the cursor was (0..1) on attempt `attemptId`.
local function onShearPress(player: Player, attemptId: any, position: any)
	local session = sessions[player]
	if not session or not session.active then
		return
	end

	local attempt = session.attempt
	if not attempt or attempt.resolved or typeof(attemptId) ~= "number" or attempt.id ~= attemptId then
		return -- stale, duplicate or made-up attempt
	end
	if typeof(position) ~= "number" or position ~= position or position < 0 or position > 1 then
		return
	end

	local elapsed = os.clock() - attempt.sentAt
	if elapsed > attempt.lifetime + ShearTimingData.LatencyAllowance then
		return -- too late; the attempt times out as a miss
	end

	local windowStart = elapsed - ShearTimingData.LatencyAllowance
	local windowEnd = math.min(elapsed, attempt.lifetime)
	if not ShearTiming.wasPositionReachable(attempt, position, windowStart, windowEnd) then
		warn(`ShearHandler: rejected an impossible press from {player.Name}.`)
		resolveAttempt(session, attempt, "MISS", 0)
		return
	end

	local distance = math.abs(position - attempt.sweetSpot)
	local tier = ShearTiming.classify(distance, attempt.zones)
	resolveAttempt(session, attempt, tier, computeDamage(session, tier, distance, attempt.zones))
end

--// Public API ------------------------------------------------------------------------

-- True while the player is in the shearing mini-game.
function shearHandler.isShearing(player: Player): boolean
	return sessions[player] ~= nil
end

--[[
	Leaves the pen station: ends the mini-game if one is running (the sheep keeps whatever
	wool it has left), moves the player out of the pen and tells the client to release the camera.
]]--
function shearHandler.leavePen(player: Player)
	local session = sessions[player]
	local pen = if session then session.pen else stationPens[player]
	if not pen then
		network.fireClient(network.RemoteEvents.DeactivateShearing, player, false)
		return
	end

	local sheep = if session then session.sheep else nil
	if session then
		endSession(session)
	end
	stationPens[player] = nil

	if not pen.destroyed then
		if sheep and sheep.Parent then
			turnSheepToPlayer(pen, sheep)
		end
		movePlayerOutOfPen(player, pen)
	end

	network.fireClient(network.RemoteEvents.DeactivateShearing, player, false)
end

function shearHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.StartShearing, onStartShearing)
	network.connectEvent(network.RemoteEvents.StopShearing, onStopShearing)
	network.connectEvent(network.RemoteEvents.ShearPress, onShearPress)

	players.PlayerRemoving:Connect(function(player: Player)
		stationPens[player] = nil
		local session = sessions[player]
		if session then
			endSession(session)
		end
	end)
end

return shearHandler
