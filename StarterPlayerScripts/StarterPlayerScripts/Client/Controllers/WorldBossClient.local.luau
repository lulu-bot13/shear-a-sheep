--[[
	King Sheep world boss on the client: Main.BossBar and the boss's BossHealthBar follow its Health / MaxHealth attributes,
	and WorldBossEffect plays the stomp (ring, then knockback on your own character), wool bursts and the poof when it leaves.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.WorldBossClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local settings = require(script.Parent.Parent.Modules.Settings)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local vfxFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX", 10)
local poofTemplate = if vfxFolder then vfxFolder:WaitForChild("PoofAttachment", 10) else nil
if not poofTemplate then
	warn("WorldBossClient: ReplicatedStorage.Assets.VFX.PoofAttachment is missing; build it in Studio.")
end

--// Configs
local BOSS_TAG = "WorldBoss" -- WorldBossData.Tag on the server
local STATE_ATTRIBUTE = "WorldBossState"
local AT_ATTRIBUTE = "WorldBossAt"
local BAR_NAME = "BossBar" -- in StarterGui.Main
local BILLBOARD_NAME = "BossHealthBar"
local GUI_WAIT_SECONDS = 10
local FILL_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DEFAULT_NAME = "King Sheep"

local WARN_COLOR = Color3.fromRGB(255, 70, 70)
local WARN_TRANSPARENCY = 0.55
local RING_THICKNESS = 0.2
local SHOCKWAVE_COLOR = Color3.fromRGB(255, 225, 150)
local SHOCKWAVE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local KNOCKBACK_LIFT = 0.6 -- upward speed, as a share of the stomp's power
local KNOCKBACK_HEIGHT = 12 -- studs above/below the stomp a character still gets knocked

local WOOL_PUFFS = 14
local WOOL_PUFF_LIFETIME = 1.4
local WOOL_COLOR = Color3.fromRGB(250, 248, 240)
local REWARD_TEXT_SECONDS = 1.6
local REWARD_TEXT_RISE = 4
local REWARD_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local POOF_DEFAULT_EMIT_COUNT = 20
local POOF_SPREAD = 0.25 -- extra poofs around a big boss, as a share of its size

--// State
local boss: Model? = nil
local bossConnections: { RBXScriptConnection } = {}
local timerToken = 0

local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "WorldBossEffects"
effectsFolder.Parent = workspace

--// Helpers ------------------------------------------------------------------------

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function getState(): string
	local state = workspace:GetAttribute(STATE_ATTRIBUTE)
	return if type(state) == "string" then state else "None"
end

-- Looked up each time, so a Main recreated on respawn is still found.
local function getBossBar(): Frame?
	local main = playerGui:FindFirstChild("Main")
	local bar = main and main:FindFirstChild(BAR_NAME)
	return if bar and bar:IsA("Frame") then bar else nil
end

local function getHealthFraction(model: Model): number
	local health = model:GetAttribute("Health")
	local maxHealth = model:GetAttribute("MaxHealth")
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return 1
	end
	return math.clamp(health / maxHealth, 0, 1)
end

local function tweenFill(track: Instance?, fraction: number)
	local fill = track and track:FindFirstChild("Fill")
	if fill and fill:IsA("GuiObject") then
		tweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(fraction, 1) }):Play()
	end
end

local function setText(parent: Instance?, name: string, text: string)
	local label = parent and parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--// Bars --------------------------------------------------------------------------

local function updateTimeLeft()
	local bar = getBossBar()
	local at = workspace:GetAttribute(AT_ATTRIBUTE)
	if bar and type(at) == "number" then
		setText(bar, "TimeLeft", formatTime(at - workspace:GetServerTimeNow()))
	end
end

local function updateBars()
	local bar = getBossBar()
	local current = boss
	local active = current ~= nil and getState() == "Active"
	if bar then
		bar.Visible = active
	end
	if not current then
		return
	end

	local fraction = getHealthFraction(current)
	local name = current:GetAttribute("SheepName")
	if bar then
		setText(bar, "BossName", string.upper(if type(name) == "string" then name else DEFAULT_NAME))
		local track = bar:FindFirstChild("Track")
		tweenFill(track, fraction)
		setText(track, "HealthText", `{math.ceil(fraction * 100)}%`)
	end

	local billboard = current:FindFirstChild(BILLBOARD_NAME, true)
	if billboard then
		tweenFill(billboard:FindFirstChild("Track"), fraction)
	end
end

-- Ticks Main.BossBar.TimeLeft once a second while the boss is Active.
local function tickTimer(token: number)
	if token ~= timerToken then
		return
	end
	updateTimeLeft()
	task.delay(1, tickTimer, token)
end

local function onStateChanged()
	timerToken += 1
	if getState() == "Active" then
		tickTimer(timerToken)
	end
	updateBars()
end

local function clearBoss()
	for _, connection in bossConnections do
		connection:Disconnect()
	end
	table.clear(bossConnections)
	boss = nil
	updateBars()
end

local function setBoss(instance: Instance)
	if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then
		return
	end
	clearBoss()
	boss = instance
	table.insert(bossConnections, instance:GetAttributeChangedSignal("Health"):Connect(updateBars))
	table.insert(bossConnections, instance:GetAttributeChangedSignal("MaxHealth"):Connect(updateBars))
	-- The billboard can stream in after the model.
	table.insert(bossConnections, instance.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == BILLBOARD_NAME then
			updateBars()
		end
	end))
	updateBars()
end

--// Effects -----------------------------------------------------------------------

-- A flat neon disc lying on the ground (a cylinder's axis is its X, so it is turned to stand on end).
local function makeDisc(position: Vector3, diameter: number, color: Color3, transparency: number): Part
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = transparency
	disc.Size = Vector3.new(RING_THICKNESS, diameter, diameter)
	disc.CFrame = CFrame.new(position + Vector3.new(0, RING_THICKNESS / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = effectsFolder
	return disc
end

local function playStompWarn(data: { [string]: any })
	local seconds = if type(data.seconds) == "number" then data.seconds else 1
	local disc = makeDisc(data.position, data.radius * 2, WARN_COLOR, 1)
	local pulse = TweenInfo.new(seconds / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
	tweenService:Create(disc, pulse, { Transparency = WARN_TRANSPARENCY }):Play()
	debris:AddItem(disc, seconds)
end

-- The shockwave everyone sees; only your own character is pushed (the client owns its physics).
local function playStomp(data: { [string]: any })
	local position: Vector3 = data.position
	local radius: number = data.radius
	local wave = makeDisc(position, 2, SHOCKWAVE_COLOR, 0.2)
	tweenService:Create(wave, SHOCKWAVE_TWEEN, { Size = Vector3.new(RING_THICKNESS, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
	debris:AddItem(wave, SHOCKWAVE_TWEEN.Time)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	local offset = root.Position - position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > radius or math.abs(offset.Y) > KNOCKBACK_HEIGHT then
		return
	end

	local direction = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
	local power: number = data.power
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	root.AssemblyLinearVelocity = direction * power + Vector3.new(0, power * KNOCKBACK_LIFT, 0)
end

local function throwWool(position: Vector3, count: number)
	for _ = 1, settings.effectCount(count) do
		local puff = Instance.new("Part")
		puff.Shape = Enum.PartType.Ball
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = WOOL_COLOR
		puff.Size = Vector3.one * (1 + math.random())
		puff.CanCollide = false
		puff.CanQuery = false
		puff.CanTouch = false
		puff.CastShadow = false
		puff.CFrame = CFrame.new(position + Vector3.new(0, 3, 0))
		puff.Parent = effectsFolder
		local angle = math.random() * math.pi * 2
		puff.AssemblyLinearVelocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (14 + math.random() * 10)
			+ Vector3.new(0, 25 + math.random() * 15, 0)
		debris:AddItem(puff, WOOL_PUFF_LIFETIME)
	end
end

-- "+X Wool" floating up over your own head.
local function showReward(amount: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(6, 1.6)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = root
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = REWARD_TEXT_COLOR
	label.Text = `+{numberFormatter:Format(amount, 1) or amount} Wool`
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label

	local tweenInfo = TweenInfo.new(REWARD_TEXT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenService:Create(billboard, tweenInfo, { StudsOffsetWorldSpace = Vector3.new(0, 3 + REWARD_TEXT_RISE, 0) }):Play()
	tweenService:Create(label, tweenInfo, { TextTransparency = 1 }):Play()
	tweenService:Create(stroke, tweenInfo, { Transparency = 1 }):Play()
	debris:AddItem(billboard, REWARD_TEXT_SECONDS)
end

local function playWoolBurst(data: { [string]: any })
	throwWool(data.position, WOOL_PUFFS)
	local rewards = data.rewards
	local amount = if type(rewards) == "table" then rewards[tostring(player.UserId)] else nil
	if type(amount) == "number" then
		showReward(amount)
	end
end

local function playPoof(position: Vector3)
	if not poofTemplate then
		return
	end
	local poof = poofTemplate:Clone()
	poof.Parent = workspace.Terrain
	poof.WorldPosition = position

	local lifetime = 0
	for _, descendant in poof:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount")
			descendant:Emit(settings.effectCount(if type(emitCount) == "number" then emitCount else POOF_DEFAULT_EMIT_COUNT))
			lifetime = math.max(lifetime, descendant.Lifetime.Max)
		end
	end
	debris:AddItem(poof, lifetime + 0.5)
end

-- A poof in the middle and four around it, so a big boss disappears in one cloud.
local function playLeave(data: { [string]: any }, defeated: boolean)
	local position: Vector3 = data.position
	local spread = (if type(data.size) == "number" then data.size else 10) * POOF_SPREAD
	playPoof(position)
	for index = 1, 4 do
		local angle = index * math.pi / 2
		playPoof(position + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread))
	end
	if defeated then
		throwWool(position, WOOL_PUFFS * 2)
	end
end

local function onEffect(kind: any, data: any)
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	if kind == "StompWarn" and type(data.radius) == "number" then
		playStompWarn(data)
	elseif kind == "Stomp" and type(data.radius) == "number" and type(data.power) == "number" then
		playStomp(data)
	elseif kind == "WoolBurst" then
		playWoolBurst(data)
	elseif kind == "Defeated" or kind == "Escaped" then
		playLeave(data, kind == "Defeated")
	end
end

--// Setup ---------------------------------------------------------------------------

task.spawn(function()
	local main = playerGui:WaitForChild("Main", GUI_WAIT_SECONDS)
	if not main or not main:WaitForChild(BAR_NAME, GUI_WAIT_SECONDS) then
		warn(`WorldBossClient: PlayerGui.Main.{BAR_NAME} is missing; build it in Studio.`)
	end
end)

-- Main is rebuilt on respawn; the new copy starts hidden with Studio's text.
playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "Main" then
		child:WaitForChild(BAR_NAME, GUI_WAIT_SECONDS)
		updateBars()
		updateTimeLeft()
	end
end)

workspace:GetAttributeChangedSignal(STATE_ATTRIBUTE):Connect(onStateChanged)
workspace:GetAttributeChangedSignal(AT_ATTRIBUTE):Connect(updateTimeLeft)

collectionService:GetInstanceAddedSignal(BOSS_TAG):Connect(setBoss)
collectionService:GetInstanceRemovedSignal(BOSS_TAG):Connect(function(instance: Instance)
	if instance == boss then
		clearBoss()
	end
end)
for _, instance in collectionService:GetTagged(BOSS_TAG) do
	setBoss(instance)
end
onStateChanged()

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.WorldBossEffect, onEffect)
