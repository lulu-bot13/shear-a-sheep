--[[
	King Sheep world boss on the client: health bars, stomps and wool bursts, the arrival and defeat cutscenes with their
	effects, and the reward popup once the defeat has played out.
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
local cutscene = require(script.Parent.Parent.Modules.KingSheepCutscene)
local rewardPopup = require(script.Parent.Parent.Modules.KingSheepRewardPopup)
local vfx = require(script.Parent.Parent.Modules.KingSheepVFX)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local effectsFolder = vfx.folder

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
local REWARD_TEXT_SECONDS = 1.6
local REWARD_TEXT_RISE = 4
local REWARD_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local POOF_SPREAD = 0.25 -- extra poofs around a big boss, as a share of its size
local REVEAL_DELAY = 0.9 -- seconds into the arrival before the pillar rises, so the cutscene's camera is there for it
local EXPLODE_LEAD = 0.6 -- the blast lands this long before the server removes the defeated boss
local MIN_EXPLODE_SECONDS = 0.8
local POPUP_WAIT_SECONDS = 10 -- the most the reward popup waits for the defeat cutscene

--// State
local boss: Model? = nil
local bossConnections: { RBXScriptConnection } = {}
local timerToken = 0
local defeatShownAt = 0 -- os.clock() the blast lands, so the reward popup follows it

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
	else
		cutscene.stop("Intro") -- it escaped or was sent away mid-arrival
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
	vfx.throwWool(data.position, WOOL_PUFFS)
	local rewards = data.rewards
	local amount = if type(rewards) == "table" then rewards[tostring(player.UserId)] else nil
	if type(amount) == "number" then
		showReward(amount)
	end
end

-- A poof in the middle and four around it, so a big boss disappears in one cloud.
local function playEscape(data: { [string]: any })
	local position: Vector3 = data.position
	local spread = (if type(data.size) == "number" then data.size else 10) * POOF_SPREAD
	vfx.poof(position)
	for index = 1, 4 do
		local angle = index * math.pi / 2
		vfx.poof(position + Vector3.new(math.cos(angle) * spread, 0, math.sin(angle) * spread))
	end
end

local function getTarget(data: { [string]: any }): cutscene.Target?
	if typeof(data.pivot) ~= "CFrame" or type(data.height) ~= "number" or type(data.seconds) ~= "number" then
		return nil
	end
	return {
		pivot = data.pivot,
		center = if typeof(data.center) == "Vector3" then data.center else data.position,
		height = data.height,
		seconds = data.seconds,
	}
end

-- The arrival: the pillar and burst for everyone, and the fly-in for whoever can watch it.
local function playSpawn(data: { [string]: any })
	local target = getTarget(data)
	if not target then
		return
	end
	task.delay(REVEAL_DELAY, vfx.playReveal, { position = data.position, height = target.height })
	cutscene.playIntro(target)
end

-- The defeat: the charge-up and blast for everyone, and the ending shot for whoever can watch it.
local function playDefeat(data: { [string]: any })
	local target = getTarget(data)
	if not target then
		return
	end
	local explodeAt = math.max(target.seconds - EXPLODE_LEAD, MIN_EXPLODE_SECONDS)
	target.explodeAt = explodeAt
	defeatShownAt = os.clock() + explodeAt
	vfx.playDefeat({
		boss = if typeof(data.boss) == "Instance" and data.boss:IsA("Model") then data.boss else nil,
		center = target.center,
		height = target.height,
		explodeAt = explodeAt,
	})
	cutscene.playOutro(target)
end

local function isReward(data: any): boolean
	return type(data) == "table"
		and type(data.damage) == "number"
		and type(data.share) == "number"
		and type(data.rank) == "number"
		and type(data.shearers) == "number"
		and type(data.wool) == "number"
		and type(data.luck) == "number"
		and type(data.gems) == "number"
		and type(data.woolBonus) == "number"
		and type(data.luckBonus) == "number"
end

-- The popup waits for the blast and the ending shot, so it opens as the camera comes home.
local function showRewardPopup(reward: rewardPopup.Reward)
	local giveUpAt = os.clock() + POPUP_WAIT_SECONDS
	while os.clock() < giveUpAt and (os.clock() < defeatShownAt or cutscene.isPlaying()) do
		task.wait(0.1)
	end
	rewardPopup.show(reward)
end

local function onEffect(kind: any, data: any)
	if kind == "Reward" then
		if isReward(data) then
			task.spawn(showRewardPopup, data)
		end
		return
	end
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" then
		return
	end
	if kind == "StompWarn" and type(data.radius) == "number" then
		playStompWarn(data)
	elseif kind == "Stomp" and type(data.radius) == "number" and type(data.power) == "number" then
		playStomp(data)
	elseif kind == "WoolBurst" then
		playWoolBurst(data)
	elseif kind == "Spawn" then
		playSpawn(data)
	elseif kind == "Defeated" then
		playDefeat(data)
	elseif kind == "Escaped" then
		playEscape(data)
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
