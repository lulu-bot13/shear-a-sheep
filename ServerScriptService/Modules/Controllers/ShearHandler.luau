--[[
	Server side of the shearing mini-game.

	When a player presses START SHEARING in a pen's menu, the sheep is turned side-on,
	the player is snapped to the pen and the server starts sending "waves" of circles.
	Each wave is a few weak points on the sheep; the client shows a circle on each and
	reports the ones the player pops. The server decides damage (never the client),
	checks timing, heals the sheep for misses on harder rarities, and awards a critical
	when a whole wave is popped quickly.

	Location: ServerScriptService.Modules.Controllers.ShearHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SheepHandler = require(script.Parent.SheepHandler)
local InventoryHandler = require(script.Parent.InventoryHandler)
local PenHandler = require(script.Parent.PenHandler)
local ShearData = require(script.Parent.Parent.Constants.ShearData)

--// Configs
local MAX_START_DISTANCE = 14 -- how far from the pen's PlayerPos a player may be to start shearing
local LEAVE_DISTANCE = 9.5 -- how far outside the pen (from its PlayerPos) a player is moved when they leave
local SHEEP_TURN_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LOOP_STEP_SECONDS = 0.05

type Session = {
	player: Player,
	pen: any,
	sheep: Model,
	sheepId: number,
	difficulty: any,
	active: boolean,
	waveCounter: number,
	wave: any?,
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

-- Picks `count` distinct weak points (weighted), keeping them apart from each other.
local function pickWeakPoints(count: number): { any }
	local pool = table.clone(ShearData.WeakPoints)
	local picked: { any } = {}

	local attempts = 0
	while #picked < count and #pool > 0 and attempts < 40 do
		attempts += 1

		local totalWeight = 0
		for _, point in pool do
			totalWeight += point.weight
		end

		local roll = math.random() * totalWeight
		local chosenIndex = #pool
		for index, point in pool do
			roll -= point.weight
			if roll <= 0 then
				chosenIndex = index
				break
			end
		end

		local candidate = pool[chosenIndex]
		local farEnough = true
		for _, existing in picked do
			if (existing.offset - candidate.offset).Magnitude < ShearData.MinPointSeparation then
				farEnough = false
				break
			end
		end

		table.remove(pool, chosenIndex)
		if farEnough then
			table.insert(picked, candidate)
		end
	end

	-- Fallback: never send a short wave just because the separation rule was too strict.
	local fillIndex = 1
	while #picked < count and fillIndex <= #ShearData.WeakPoints do
		local point = ShearData.WeakPoints[fillIndex]
		if not table.find(picked, point) then
			table.insert(picked, point)
		end
		fillIndex += 1
	end

	return picked
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

-- The sheep is fully sheared: pay out the wool, free the pen and tell the client.
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

-- Changes the sheep's health by `delta` (negative = damage). Returns true if it just died.
local function changeHealth(session: Session, delta: number): boolean
	local sheep = session.sheep
	local maxHealth = sheep:GetAttribute("MaxShearHealth") :: number
	local health = sheep:GetAttribute("ShearHealth") :: number

	local newHealth = math.clamp(health + delta, 0, maxHealth)
	sheep:SetAttribute("ShearHealth", newHealth)

	if newHealth <= 0 then
		finishSheep(session)
		return true
	end
	return false
end

-- Builds the next wave, records it as the session's live wave and sends it to the client.
local function sendWave(session: Session)
	session.waveCounter += 1

	local difficulty = session.difficulty
	local wave = {
		id = session.waveCounter,
		sentAt = os.clock(),
		lifetime = difficulty.lifetime,
		critWindow = difficulty.critWindow,
		points = {},
		total = 0,
		hits = 0,
		damage = 0,
		firstHitAt = nil,
		resolved = false,
	}

	local payload = {}
	for _, point in pickWeakPoints(ShearData.WaveSize) do
		local damage = math.max(1, math.round(ShearData.HitDamage * point.multiplier))
		wave.points[point.id] = { damage = damage, hit = false }
		wave.total += 1

		table.insert(payload, {
			id = point.id,
			offset = point.offset,
			multiplier = point.multiplier,
			damage = damage,
		})
	end

	session.wave = wave
	network.fireClient(
		network.RemoteEvents.ShearWave,
		session.player,
		wave.id,
		wave.lifetime,
		difficulty.sizeScale,
		wave.critWindow,
		payload
	)
end

-- Circles that ran out of time cost the player: harder sheep regrow some health.
local function expireWave(session: Session)
	local wave = session.wave
	if not wave then
		return
	end

	local missed = 0
	for _, point in wave.points do
		if not point.hit then
			missed += 1
		end
	end

	wave.resolved = true

	local healRatio = session.difficulty.missHeal
	if missed > 0 and healRatio > 0 then
		local maxHealth = session.sheep:GetAttribute("MaxShearHealth") :: number
		changeHealth(session, math.round(maxHealth * healRatio * missed))
	end
end

-- True while the session's pen, sheep and player are all still valid.
local function isSessionValid(session: Session): boolean
	local character = session.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return session.player.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and not session.pen.destroyed
		and session.sheep.Parent ~= nil
		and SheepHandler.getSheep(session.sheepId) == session.sheep
end

-- Ends a session that went invalid (player died/left, pen sold...) and tells the client.
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

-- Runs wave after wave until the sheep is sheared or the session is ended.
local function runWaves(session: Session)
	task.wait(ShearData.FirstWaveDelaySeconds)

	while session.active do
		if not isSessionValid(session) then
			abortSession(session)
			return
		end

		sendWave(session)
		local wave = session.wave

		local deadline = wave.sentAt + wave.lifetime + ShearData.HitGraceSeconds
		while session.active and not wave.resolved and os.clock() < deadline do
			task.wait(LOOP_STEP_SECONDS)
		end

		if not session.active then
			return
		end

		if not wave.resolved then
			expireWave(session)
			if not session.active then
				return
			end
		end

		task.wait(ShearData.WaveGapSeconds)
	end
end

--// Remote handlers ---------------------------------------------------------------

local function onStartShearing(player: Player, penId: any)
	if typeof(penId) ~= "number" or sessions[player] then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return
	end

	local pen = PenHandler.getPen(player, penId)
	if not pen or pen.shearingPlayer or not pen.seated or not pen.occupiedSheepId then
		return
	end

	if (rootPart.Position - pen.playerPosition).Magnitude > MAX_START_DISTANCE then
		return
	end

	local sheepId = pen.occupiedSheepId
	local sheep = SheepHandler.getSheep(sheepId)
	local currentSheepId = player:FindFirstChild("CurrentSheepId") :: IntValue?
	if not sheep or not currentSheepId then
		return
	end

	local health = sheep:GetAttribute("ShearHealth")
	if type(health) ~= "number" or health <= 0 then
		return
	end

	local session: Session = {
		player = player,
		pen = pen,
		sheep = sheep,
		sheepId = sheepId,
		difficulty = ShearData.getDifficulty(sheep:GetAttribute("Rarity") :: string?),
		active = true,
		waveCounter = 0,
		wave = nil,
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

	task.spawn(runWaves, session)
end

local function onStopShearing(player: Player)
	shearHandler.leavePen(player)
end

local function onShearHit(player: Player, waveId: any, pointId: any)
	local session = sessions[player]
	if not session or not session.active then
		return
	end

	local wave = session.wave
	if not wave or wave.resolved or typeof(waveId) ~= "number" or wave.id ~= waveId then
		return
	end
	if typeof(pointId) ~= "string" then
		return
	end

	local point = wave.points[pointId]
	if not point or point.hit then
		return
	end

	local now = os.clock()
	if now - wave.sentAt > wave.lifetime + ShearData.HitGraceSeconds then
		return
	end

	point.hit = true
	wave.hits += 1
	wave.damage += point.damage
	wave.firstHitAt = wave.firstHitAt or now

	if changeHealth(session, -point.damage) then
		return
	end

	-- Last circle of the wave popped: a fast enough clear is a critical.
	if wave.hits >= wave.total then
		wave.resolved = true

		if now - wave.firstHitAt <= wave.critWindow then
			local bonus = math.round(wave.damage * (ShearData.CritMultiplier - 1))
			network.fireClient(network.RemoteEvents.ShearFeedback, player, "Crit", bonus)
			changeHealth(session, -bonus)
		end
	end
end

--// Public API ------------------------------------------------------------------------

-- True while the player is in the shearing mini-game.
function shearHandler.isShearing(player: Player): boolean
	return sessions[player] ~= nil
end

--[[
	Leaves the pen station: ends the mini-game if one is running (the sheep keeps whatever
	health it has left), moves the player out of the pen and tells the client to release the camera.
]]--
function shearHandler.leavePen(player: Player)
	local session = sessions[player]
	local pen = if session then session.pen else stationPens[player]
	if not pen then
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
	network.connectEvent(network.RemoteEvents.ShearHit, onShearHit)

	players.PlayerRemoving:Connect(function(player: Player)
		stationPens[player] = nil
		local session = sessions[player]
		if session then
			endSession(session)
		end
	end)
end

return shearHandler
