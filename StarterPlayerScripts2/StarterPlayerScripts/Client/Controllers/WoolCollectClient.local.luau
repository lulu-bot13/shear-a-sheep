--[[
	Plays the wool collect effect after a sheep is sheared: puffs fly into the character, then icons fly to the wool counter.

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
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sound Effects
local uiSounds = soundService:WaitForChild("UISounds")
local popSfx = uiSounds:FindFirstChild("Pop")

--// Configs
local PUFF_COUNT = 16
local PUFF_BURST_SECONDS = 0.3 -- splashing out of the sheep
local PUFF_FLIGHT_SECONDS = 0.5 -- curving in to the character
local PUFF_STAGGER_SECONDS = 0.012
local ICON_COUNT = 12
local ICON_BURST_SECONDS = 0.22
local ICON_FLIGHT_SECONDS = 0.55
local ICON_STAGGER_SECONDS = 0.045
local PUFF_POP_GAP_SECONDS = 0.05 -- minimum spacing between pops as puffs land on the character
local ICON_POP_GAP_SECONDS = 0.06 -- ...and as icons land on the counter
local POP_PITCH_STEP = 0.04 -- each pop in a run is slightly higher
local POP_MAX_STEPS = 10
local HOLD_TIMEOUT_SECONDS = 5 -- the counter is never held back longer than this, whatever happens

local SHARE_LABEL_WIDTH = 2.2 -- the "+N" label's size, relative to its icon
local SHARE_LABEL_HEIGHT = 0.9
local SHARE_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SHARE_STROKE_COLOR = Color3.fromRGB(40, 70, 110)

local WOOL_COLOR = Color3.fromRGB(255, 250, 240)
local WOOL_EDGE_COLOR = Color3.fromRGB(176, 214, 245)

--// State
local holdToken = 0

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WoolCollectGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true -- so positions from WorldToViewportPoint line up
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

--// Helpers -------------------------------------------------------------------

local function bezier(a: Vector3, b: Vector3, c: Vector3, t: number): Vector3
	local ab = a:Lerp(b, t)
	local bc = b:Lerp(c, t)
	return ab:Lerp(bc, t)
end

local function bezier2(a: Vector2, b: Vector2, c: Vector2, t: number): Vector2
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

-- The wool counter's centre on screen, or nil while it can't be found.
local function getCounterPoint(): (Vector2?, GuiObject?)
	local main = playerGui:FindFirstChild("Main")
	local label = main and main:FindFirstChild("WoolAmount")
	if not label or not label:IsA("GuiObject") then
		return nil, nil
	end
	return label.AbsolutePosition + label.AbsoluteSize / 2, label
end

-- Holds back `change` more wool from the counter (negative = lets some through).
local function changeHeld(change: number)
	local held = player:GetAttribute("WoolLabelHold")
	player:SetAttribute("WoolLabelHold", math.max((if type(held) == "number" then held else 0) + change, 0))
end

--// Stage 2: icons to the counter ------------------------------------------------------

local function makeIcon(size: number): GuiObject
	local icon: GuiObject
	if WoolData.WoolIconImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = WoolData.WoolIconImage
		icon = image
	else
		local puff = Instance.new("Frame")
		puff.BackgroundColor3 = WOOL_COLOR
		puff.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = puff
		local stroke = Instance.new("UIStroke")
		stroke.Color = WOOL_EDGE_COLOR
		stroke.Thickness = 2
		stroke.Parent = puff
		icon = puff
	end

	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.Parent = screenGui
	return icon
end

-- The counter bounces a little every time wool lands in it.
local function punchCounter(label: GuiObject)
	local scale = label:FindFirstChild("CollectScale") :: UIScale?
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "CollectScale"
		scale.Parent = label
	end
	scale.Scale = 1.18
	tweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The "+N" riding on an icon, so the player sees how the wool they just earned adds up.
local function addShareLabel(icon: GuiObject, share: number)
	local label = Instance.new("TextLabel")
	label.Name = "Share"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 0)
	label.Size = UDim2.fromScale(SHARE_LABEL_WIDTH, SHARE_LABEL_HEIGHT)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = SHARE_TEXT_COLOR
	label.Text = `+{share}`
	label.ZIndex = icon.ZIndex + 1
	label.Parent = icon

	local stroke = Instance.new("UIStroke")
	stroke.Color = SHARE_STROKE_COLOR
	stroke.Thickness = 2
	stroke.Parent = label
end

--[[
	Icons burst out around `start` (a screen point) and curve to the wool counter. The wool is split into whole
	shares, one per icon (at most ICON_COUNT icons; fewer when there is less wool, so 5 wool is five "+1"s). Each icon
	shows its "+share" and releases exactly that much of the held wool when it lands, so the shares add up to `amount`.
]]
local function flyIcons(start: Vector2, distance: number, amount: number)
	local counterPoint, counter = getCounterPoint()
	local iconCount = math.min(ICON_COUNT, math.floor(amount))
	if not counterPoint or not counter or iconCount <= 0 then
		changeHeld(-amount)
		return
	end

	-- Closer camera = bigger burst and bigger icons.
	local nearness = math.clamp(24 / math.max(distance, 4), 0.6, 1.8)
	local burstRadius = 90 * nearness
	local iconSize = math.floor(34 * math.clamp(nearness, 0.8, 1.4))

	local baseShare = math.floor(amount / iconCount)
	local leftover = amount - baseShare * iconCount -- the first icons carry one extra each
	local popIcon = newPopSequence(ICON_POP_GAP_SECONDS)

	for index = 1, iconCount do
		local share = baseShare + (if index <= leftover then 1 else 0)

		task.delay((index - 1) * ICON_STAGGER_SECONDS, function()
			local icon = makeIcon(iconSize)
			icon.Position = UDim2.fromOffset(start.X, start.Y)
			addShareLabel(icon, share)

			local angle = math.random() * math.pi * 2
			local burstPoint = start + Vector2.new(math.cos(angle), math.sin(angle)) * burstRadius * (0.5 + math.random() * 0.5)
			-- The curve bows away from a straight line so the icons swoop instead of travelling in a beeline.
			local target = counterPoint + Vector2.new(math.random(-8, 8), math.random(-6, 6))
			local control = burstPoint:Lerp(target, 0.5) + Vector2.new(-(target - burstPoint).Y, (target - burstPoint).X).Unit * (60 + math.random() * 80) * (if math.random() < 0.5 then 1 else -1)

			local startTime = os.clock()
			local connection: RBXScriptConnection
			connection = runService.RenderStepped:Connect(function()
				local elapsed = os.clock() - startTime
				local position: Vector2
				if elapsed < ICON_BURST_SECONDS then
					position = start:Lerp(burstPoint, easeOut(elapsed / ICON_BURST_SECONDS))
				else
					local t = math.min((elapsed - ICON_BURST_SECONDS) / ICON_FLIGHT_SECONDS, 1)
					position = bezier2(burstPoint, control, target, easeIn(t))
					icon.Size = UDim2.fromOffset(iconSize * (1 - 0.45 * t), iconSize * (1 - 0.45 * t))
					if t >= 1 then
						popIcon()
						connection:Disconnect()
						icon:Destroy()
						punchCounter(counter)
						changeHeld(-share)
						return
					end
				end
				icon.Position = UDim2.fromOffset(position.X, position.Y)
			end)
		end)
	end
end

--// Stage 1: puffs to the character ---------------------------------------------------------

-- The counter is already holding back `amount` (set when the event arrived).
local function collectWool(origin: Vector3, amount: number, color: Color3)
	local camera = workspace.CurrentCamera
	local rootPart = getCharacterRoot()
	if not camera or not rootPart then
		changeHeld(-amount)
		return
	end

	local landed = 0
	local startedIcons = false
	local popPuff = newPopSequence(PUFF_POP_GAP_SECONDS)

	local function startIcons()
		startedIcons = true
		local currentRoot = getCharacterRoot()
		local viewportPoint, onScreen = camera:WorldToViewportPoint(if currentRoot then currentRoot.Position else rootPart.Position)
		local distance = (camera.CFrame.Position - (if currentRoot then currentRoot.Position else rootPart.Position)).Magnitude

		local point = Vector2.new(viewportPoint.X, viewportPoint.Y)
		-- Behind the camera (or far off screen) the icons come up from the bottom centre instead.
		local viewport = camera.ViewportSize
		if not onScreen or viewportPoint.Z < 0 then
			point = Vector2.new(viewport.X / 2, viewport.Y * 0.75)
		end
		point = Vector2.new(math.clamp(point.X, 40, viewport.X - 40), math.clamp(point.Y, 40, viewport.Y - 40))

		flyIcons(point, distance, amount)
	end

	for index = 1, PUFF_COUNT do
		task.delay((index - 1) * PUFF_STAGGER_SECONDS, function()
			local puff = Instance.new("Part")
			puff.Name = "WoolPuff"
			puff.Shape = Enum.PartType.Ball
			puff.Size = Vector3.one * (0.5 + math.random() * 0.45)
			puff.Color = color
			puff.Material = Enum.Material.SmoothPlastic
			puff.Anchored = true
			puff.CanCollide = false
			puff.CanTouch = false
			puff.CanQuery = false
			puff.CastShadow = false
			puff.Position = origin
			puff.Parent = workspace
			debris:AddItem(puff, 3)

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
					if landed >= PUFF_COUNT * 0.6 and not startedIcons then
						startIcons()
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
	collectWool(origin, amount, color)
end)
