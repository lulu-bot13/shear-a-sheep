--[[
	Plays the wool collect effect after a sheep is sheared: wool drops on the ground and is pulled into the character
	(or flies straight in with DROP_WOOL_ON_GROUND off), and the wool counter swells as it goes up.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.WoolCollectClient
]]--

--// Services
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sound Effects
local uiSounds = soundService:WaitForChild("UISounds")
local popSfx = uiSounds:FindFirstChild("Pop")

--// Configs
local DROP_WOOL_ON_GROUND = true -- false = the puffs fly straight from the sheep into the character instead
local DROP_PIECE_COUNT = 6 -- at most; fewer when there is less wool, like the icons
local DROP_FALL_SECONDS = 0.45 -- arcing out of the sheep onto the ground
local DROP_REST_SECONDS = 0.5 -- lying on the ground before being pulled in
local DROP_PULL_SECONDS = 0.22 -- the parabola up to the character
local DROP_STAGGER_SECONDS = 0.05
local DROP_FALL_HEIGHT = 2.5 -- studs each arc rises above a straight line at its middle
local DROP_PULL_HEIGHT = 5
local DROP_SCATTER_RADIUS = 4.5
local DROP_PIECE_SIZE = 0.8
local DROP_LIFETIME_SECONDS = 5 -- a piece is cleaned up after this whatever happens
local DROP_TRAIL_SECONDS = 0.18 -- how long each piece's trail lingers behind it
local TOTAL_HIDE_SECONDS = 1.2 -- the running total on the character hides this long after the last piece arrives

local PUFF_COUNT = 16
local PUFF_BURST_SECONDS = 0.3 -- splashing out of the sheep
local PUFF_FLIGHT_SECONDS = 0.5 -- curving in to the character
local PUFF_STAGGER_SECONDS = 0.012
local PUFF_POP_GAP_SECONDS = 0.05 -- minimum spacing between pops as wool lands on the character
local POP_PITCH_STEP = 0.04 -- each pop in a run is slightly higher
local POP_MAX_STEPS = 10
local HOLD_TIMEOUT_SECONDS = 5 -- the counter is never held back longer than this, whatever happens

local COUNTER_GROW_SCALE = 1.15 -- the wool counter swells to this when wool is added...
local COUNTER_GROW_SECONDS = 0.12
local COUNTER_HOLD_SECONDS = 0.7 -- ...stays big this long...
local COUNTER_SHRINK_SECONDS = 0.2 -- ...then settles back

local SHARE_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SHARE_STROKE_COLOR = Color3.fromRGB(40, 70, 110)

local WOOL_EDGE_COLOR = Color3.fromRGB(176, 214, 245)

--// State
local holdToken = 0
local totalGui: BillboardGui? = nil
local totalLabel: TextLabel? = nil
local totalAmount = 0
local totalToken = 0
local counterTweens: { Tween } = {}

--// Helpers -------------------------------------------------------------------

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local ab = a:Lerp(b, t)
	local bc = b:Lerp(c, t)
	return ab:Lerp(bc, t)
end

local function easeOut(t: number): number
	return 1 - (1 - t) ^ 3
end

local function easeIn(t: number): number
	return t * t
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- `t` of the way from `a` to `b` along an arc that peaks `height` above the straight line at its middle.
local function parabola(a: Vector3, b: Vector3, height: number, t: number): Vector3
	return a:Lerp(b, t) + Vector3.new(0, 4 * height * t * (1 - t), 0)
end

-- `amount` split into `count` whole shares that add up to it; the first shares carry one extra each.
local function splitShares(amount: number, count: number): { number }
	local baseShare = math.floor(amount / count)
	local leftover = amount - baseShare * count
	local shares = table.create(count)
	for index = 1, count do
		shares[index] = baseShare + (if index <= leftover then 1 else 0)
	end
	return shares
end

-- A "+N" with a white fill and blue outline.
local function makeAmountLabel(amount: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = SHARE_TEXT_COLOR
	label.Text = `+{amount}`

	local stroke = Instance.new("UIStroke")
	stroke.Color = SHARE_STROKE_COLOR
	stroke.Thickness = 2
	stroke.Parent = label

	label.Parent = parent
	return label
end

-- Plays a fresh copy of the pop so overlapping pops don't cut each other off.
local function playPop(speed: number)
	if not popSfx or not popSfx:IsA("Sound") then
		return
	end
	local sound = popSfx:Clone()
	sound.PlaybackSpeed = popSfx.PlaybackSpeed * speed
	sound.Parent = uiSounds
	sound:Play()
	debris:AddItem(sound, math.max(sound.TimeLength, 1) + 0.5)
end

-- Returns a function that plays one pop per call, spaced at least `gap` apart and rising in pitch.
local function newPopSequence(gap: number): () -> ()
	local nextTime = 0
	local count = 0
	return function()
		local now = os.clock()
		local playAt = math.max(now, nextTime)
		nextTime = playAt + gap
		local speed = 1 + math.min(count, POP_MAX_STEPS) * POP_PITCH_STEP
		count += 1
		task.delay(playAt - now, playPop, speed)
	end
end

local function getCharacterRoot(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Holds back `change` more wool from the counter (negative = lets some through).
local function changeHeld(change: number)
	local held = player:GetAttribute("WoolLabelHold")
	player:SetAttribute("WoolLabelHold", math.max((if type(held) == "number" then held else 0) + change, 0))
end

local function getScale(label: GuiObject): UIScale
	local scale = label:FindFirstChild("CollectScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "CollectScale"
		scale.Parent = label
	end
	return scale :: UIScale
end

-- The total over the character bounces a little every time a piece lands in it.
local function punchLabel(label: GuiObject)
	local scale = getScale(label)
	scale.Scale = 1.18
	tweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--// Wool counter ------------------------------------------------------------------------

-- The counter swells, stays big for a moment, then settles; more wool while it's big keeps it big.
local function growCounter(label: GuiObject)
	for _, tween in counterTweens do
		tween:Cancel()
	end

	local scale = getScale(label)
	local grow = tweenService:Create(scale, TweenInfo.new(COUNTER_GROW_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = COUNTER_GROW_SCALE })
	local shrink = tweenService:Create(scale, TweenInfo.new(COUNTER_SHRINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, 0, false, COUNTER_HOLD_SECONDS), { Scale = 1 })
	counterTweens = { grow, shrink }

	grow.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			shrink:Play()
		end
	end)
	grow:Play()
end

-- Lets `amount` of the held wool through to the counter.
local function addToCounter(amount: number)
	changeHeld(-amount)

	local main = playerGui:FindFirstChild("Main")
	local label = main and main:FindFirstChild("WoolAmount")
	if label and label:IsA("GuiObject") then
		growCounter(label)
	end
end

--// Wool to the character -------------------------------------------------------------------

local function makeWoolPart(name: string, size: number, color: Color3, position: Vector3, lifetime: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Position = position
	part.Parent = workspace
	debris:AddItem(part, lifetime)
	return part
end

-- A trail streaming behind the piece as it moves.
local function addTrail(piece: BasePart, color: Color3)
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, DROP_PIECE_SIZE * 0.3, 0)
	top.Parent = piece
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -DROP_PIECE_SIZE * 0.3, 0)
	bottom.Parent = piece

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(color, WOOL_EDGE_COLOR)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Lifetime = DROP_TRAIL_SECONDS
	trail.FaceCamera = true
	trail.LightEmission = 0.4
	trail.Parent = piece
end

-- The "+N" on the character's root that adds up every piece as it arrives, then hides once the pieces stop coming.
local function addToTotal(root: BasePart, share: number)
	if not root.Parent then
		return
	end

	if not totalGui or not totalLabel or totalGui.Parent ~= root then
		if totalGui then
			totalGui:Destroy()
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "WoolTotal"
		gui.Size = UDim2.fromScale(2.4, 1)
		gui.AlwaysOnTop = true
		gui.Adornee = root
		gui.Parent = root

		local label = makeAmountLabel(0, gui)
		label.Size = UDim2.fromScale(1, 1)
		totalGui = gui
		totalLabel = label
		totalAmount = 0
	end

	local gui = totalGui :: BillboardGui
	local label = totalLabel :: TextLabel
	totalAmount += share
	label.Text = `+{totalAmount}`
	gui.Enabled = true
	punchLabel(label)

	totalToken += 1
	local token = totalToken
	task.delay(TOTAL_HIDE_SECONDS, function()
		if token == totalToken then
			gui.Enabled = false
			totalAmount = 0
		end
	end)
end

-- Where a piece scattered to `point` comes to rest: the ground under it, skipping sheep (they don't collide with players).
local function findGround(point: Vector3, size: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	params.CollisionGroup = "Players"
	params.RespectCanCollide = true

	local result = workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -25, 0), params)
	local ground = if result then result.Position else point - Vector3.new(0, 2.5, 0)
	return ground + Vector3.new(0, size / 2, 0)
end

--[[
	The wool splits into pieces (one whole share each) that fall around the sheep showing their "+share".
	Each is then pulled in along a parabola, adding its share to the total on the character's root and to the counter.
	The counter is already holding back `amount` (set when the event arrived).
]]
local function dropWool(origin: Vector3, amount: number, color: Color3)
	local rootPart = getCharacterRoot()
	local pieceCount = math.min(DROP_PIECE_COUNT, math.floor(amount))
	if not rootPart or pieceCount <= 0 then
		addToCounter(amount)
		return
	end

	local popPiece = newPopSequence(PUFF_POP_GAP_SECONDS)

	for index, share in splitShares(amount, pieceCount) do
		task.delay((index - 1) * DROP_STAGGER_SECONDS, function()
			local piece = makeWoolPart("WoolPiece", DROP_PIECE_SIZE, color, origin, DROP_LIFETIME_SECONDS)

			local angle = math.random() * math.pi * 2
			local scatter = Vector3.new(math.cos(angle), 0, math.sin(angle)) * DROP_SCATTER_RADIUS * (0.4 + math.random() * 0.6)
			local ground = findGround(origin + scatter, DROP_PIECE_SIZE)

			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromScale(1.4, 0.6)
			tag.StudsOffset = Vector3.new(0, 0.8, 0)
			tag.AlwaysOnTop = true
			tag.Parent = piece
			makeAmountLabel(share, tag).Size = UDim2.fromScale(1, 1)
			addTrail(piece, color)

			local startTime = os.clock()
			local connection: RBXScriptConnection
			connection = runService.Heartbeat:Connect(function()
				if not piece.Parent then
					connection:Disconnect()
					addToCounter(share)
					return
				end

				local elapsed = os.clock() - startTime
				if elapsed < DROP_FALL_SECONDS then
					piece.Position = parabola(origin, ground, DROP_FALL_HEIGHT, elapsed / DROP_FALL_SECONDS)
					return
				end

				local currentRoot = getCharacterRoot() or rootPart
				local pullElapsed = elapsed - DROP_FALL_SECONDS - DROP_REST_SECONDS
				if pullElapsed < 0 then
					piece.Position = ground
					return
				end

				local t = math.min(pullElapsed / DROP_PULL_SECONDS, 1)
				piece.Position = parabola(ground, currentRoot.Position, DROP_PULL_HEIGHT, smoothstep(t))
				piece.Size = Vector3.one * DROP_PIECE_SIZE * (1 - 0.5 * t)

				if t >= 1 then
					connection:Disconnect()
					piece:Destroy()
					popPiece()
					addToTotal(currentRoot, share)
					addToCounter(share)
				end
			end)
		end)
	end
end

-- The original effect: puffs splash out of the sheep and curve straight into the character.
local function collectWool(origin: Vector3, amount: number, color: Color3)
	local rootPart = getCharacterRoot()
	if not rootPart then
		addToCounter(amount)
		return
	end

	local landed = 0
	local released = false
	local popPuff = newPopSequence(PUFF_POP_GAP_SECONDS)

	for index = 1, PUFF_COUNT do
		task.delay((index - 1) * PUFF_STAGGER_SECONDS, function()
			local puff = makeWoolPart("WoolPuff", 0.5 + math.random() * 0.45, color, origin, 3)

			local outward = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			outward = if outward.Magnitude > 0.05 then outward.Unit else Vector3.xAxis
			local burstPoint = origin + outward * (2 + math.random() * 2.5) + Vector3.new(0, 1.5 + math.random() * 2.5, 0)
			local side = Vector3.new(-outward.Z, 0, outward.X) * (math.random() - 0.5) * 6

			local startTime = os.clock()
			local connection: RBXScriptConnection
			connection = runService.Heartbeat:Connect(function()
				local elapsed = os.clock() - startTime
				if not puff.Parent then
					connection:Disconnect()
					return
				end

				if elapsed < PUFF_BURST_SECONDS then
					puff.Position = origin:Lerp(burstPoint, easeOut(elapsed / PUFF_BURST_SECONDS))
					return
				end

				-- Curve in to the character, following them if they move.
				local currentRoot = getCharacterRoot() or rootPart
				local target = currentRoot.Position + Vector3.new(0, 0.5, 0)
				local control = burstPoint:Lerp(target, 0.5) + Vector3.new(0, 3, 0) + side
				local t = math.min((elapsed - PUFF_BURST_SECONDS) / PUFF_FLIGHT_SECONDS, 1)
				puff.Position = bezier(burstPoint, control, target, easeIn(t))
				puff.Size = Vector3.one * math.max(puff.Size.X * (1 - 0.04 * t), 0.2)

				-- Complete
				if t >= 1 then
					connection:Disconnect()
					puff:Destroy()
					popPuff()
					landed += 1
					if landed >= PUFF_COUNT * 0.6 and not released then
						released = true
						addToCounter(amount)
					end
				end
			end)
		end)
	end
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.SheepSheared, function(origin: Vector3, amount: number, color: Color3)
	-- Hold the wool back straight away, before the counter shows it.
	changeHeld(amount)
	holdToken += 1
	local token = holdToken
	task.delay(HOLD_TIMEOUT_SECONDS, function()
		if token == holdToken then
			player:SetAttribute("WoolLabelHold", 0) -- something went wrong; show the real number
		end
	end)

	task.wait()
	if DROP_WOOL_ON_GROUND then
		dropWool(origin, amount, color)
	else
		collectWool(origin, amount, color)
	end
end)
