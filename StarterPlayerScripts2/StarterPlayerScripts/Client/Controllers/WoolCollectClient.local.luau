--[[
	The wool payoff effects.

	Finishing a sheep by hand (ShearingClient fires the player's "WoolCollected" bindable with where the
	sheep stood and how much wool it gave):
		1. wool puffs splash out of the sheep, then curve in to the player's character
		2. wool icons burst out of the character's spot on the screen and curve to the wool counter,
		   which pops and counts up as each one lands (ClientStart shows the wool minus WoolLabelHold)

	A worker finishing a sheep (the server's WorkerWoolGained): a "+N" billboard appears where the sheep
	stood, floats up and fades away.

	The icon is ShearTimingData.WoolIconImage; without one a plain white puff is drawn.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.WoolCollectClient
]]--

--// Services
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local ShearTimingData = require(replicatedStorage.Shared.Constants.ShearTimingData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local woolCollected = player:WaitForChild("WoolCollected") :: BindableEvent

--// Configs
local PUFF_COUNT = 16
local PUFF_BURST_SECONDS = 0.3 -- splashing out of the sheep
local PUFF_FLIGHT_SECONDS = 0.5 -- curving in to the character
local PUFF_STAGGER_SECONDS = 0.012
local ICON_COUNT = 12
local ICON_BURST_SECONDS = 0.22
local ICON_FLIGHT_SECONDS = 0.55
local ICON_STAGGER_SECONDS = 0.045
local HOLD_TIMEOUT_SECONDS = 5 -- the counter is never held back longer than this, whatever happens
local WORKER_TEXT_RISE_STUDS = 4
local WORKER_TEXT_SECONDS = 1.4

local WOOL_COLOR = Color3.fromRGB(255, 250, 240)
local WOOL_EDGE_COLOR = Color3.fromRGB(176, 214, 245)
local WORKER_TEXT_COLOR = Color3.fromRGB(78, 80, 90) -- dark grey
local WORKER_TEXT_STROKE = Color3.fromRGB(240, 240, 245) -- light outline, so the dark text reads against the grass
local FONT = Enum.Font.SourceSansBold

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
	if ShearTimingData.WoolIconImage ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = ShearTimingData.WoolIconImage
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

--[[
	Icons burst out around `start` (a screen point) and curve to the wool counter. Each one releases an equal
	share of the held wool when it lands; the last releases whatever is left.
]]
local function flyIcons(start: Vector2, distance: number, amount: number)
	local counterPoint, counter = getCounterPoint()
	if not counterPoint or not counter then
		changeHeld(-amount)
		return
	end

	-- Closer camera = bigger burst and bigger icons.
	local nearness = math.clamp(24 / math.max(distance, 4), 0.6, 1.8)
	local burstRadius = 90 * nearness
	local iconSize = math.floor(34 * math.clamp(nearness, 0.8, 1.4))

	local remaining = amount
	local share = amount / ICON_COUNT

	for index = 1, ICON_COUNT do
		task.delay((index - 1) * ICON_STAGGER_SECONDS, function()
			local icon = makeIcon(iconSize)
			icon.Position = UDim2.fromOffset(start.X, start.Y)

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
						connection:Disconnect()
						icon:Destroy()
						punchCounter(counter)
						local release = if index == ICON_COUNT then remaining else share
						remaining -= release
						changeHeld(-release)
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

				if t >= 1 then
					connection:Disconnect()
					puff:Destroy()
					landed += 1
					if landed >= PUFF_COUNT * 0.6 and not startedIcons then
						startIcons()
					end
				end
			end)
		end)
	end
end

woolCollected.Event:Connect(function(origin: Vector3, amount: number, color: Color3)
	-- Hold the wool back straight away, before the counter shows it.
	changeHeld(amount)
	holdToken += 1
	local token = holdToken
	task.delay(HOLD_TIMEOUT_SECONDS, function()
		if token == holdToken then
			player:SetAttribute("WoolLabelHold", 0) -- something went wrong; show the real number
		end
	end)

	-- Wait a frame: the HUD was only just switched back on and its labels need to be laid out.
	task.wait()
	collectWool(origin, amount, color)
end)

--// Worker wool ------------------------------------------------------------------------

-- "+N" rising from where a worker's sheep stood.
local function showWorkerWool(position: Vector3, amount: number)
	local anchor = Instance.new("Part")
	anchor.Name = "WorkerWoolAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = workspace
	debris:AddItem(anchor, WORKER_TEXT_SECONDS + 0.5)

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(220, 56)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 150
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextSize = 40
	label.TextColor3 = WORKER_TEXT_COLOR
	label.Text = `+{numberFormatter:Format(amount, 1) or amount} Wool`
	label.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = WORKER_TEXT_STROKE
	stroke.Thickness = 3
	stroke.Parent = label

	local rise = TweenInfo.new(WORKER_TEXT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenService:Create(billboard, rise, { StudsOffset = Vector3.new(0, WORKER_TEXT_RISE_STUDS, 0) }):Play()

	local fade = TweenInfo.new(WORKER_TEXT_SECONDS * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(WORKER_TEXT_SECONDS * 0.55, function()
		tweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		tweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.WorkerWoolGained, showWorkerWool)
