--[[
	Every shear hit splits the wool / Luck it knocked off into pooled DropTemplates that fall around the sheep, get pulled into
	the character, and add up on a total over its root. The HUD counters swell as they land.

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
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local player = players.LocalPlayer
local dropTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("DropTemplate") :: BasePart

--// Sound Effects
local uiSounds = soundService:WaitForChild("UISounds")
local popSfx = uiSounds:FindFirstChild("Pop")

--// Configs
local DROPS_PER_FULL_SHEEP = 50 -- a hit taking 10% of a sheep's health drops 5
local MAX_DROPS_PER_HIT = 8 -- per currency; never more drops than the amount itself
local MAX_ACTIVE_DROPS = 60 -- past this, a hit's wool goes straight to the counter
local PREWARM_DROPS = 16
local DROP_FALL_SECONDS = 0.45 -- arcing out of the sheep onto the ground
local DROP_BOUNCE_SECONDS = 0.16 -- one quick hop off the ground, then straight to the character
local DROP_BOUNCE_HEIGHT = 0.9
local DROP_PULL_SECONDS = 0.22 -- the parabola up to the character
local DROP_STAGGER_SECONDS = 0.04
local DROP_FALL_HEIGHT = 2.5 -- studs each arc rises above a straight line at its middle
local DROP_PULL_HEIGHT = 5
local DROP_SCATTER_RADIUS = 4.5
local DROP_GROUND_LIFT = 0.6 -- studs a drop rests above the ground
local PARK_CFRAME = CFrame.new(0, 10000, 0) -- idle drops wait out of sight here instead of being reparented

local TOTAL_OFFSET = Vector3.new(0, 4, 0)
local TOTAL_STACK_OFFSET = Vector3.new(0, 5.5, 0) -- the Luck total, while the wool total is showing too
local TOTAL_HIDE_SECONDS = 1.2 -- a total hides this long after its last drop arrives

local PUFF_POP_GAP_SECONDS = 0.05 -- minimum spacing between pops as drops land on the character
local POP_PITCH_STEP = 0.04 -- each pop in a run is slightly higher
local POP_MAX_STEPS = 10
local HOLD_TIMEOUT_SECONDS = 5 -- the counters are never held back longer than this, whatever happens

type Kind = "Wool" | "Luck"

local ICONS: { [Kind]: string } = {
	Wool = "rbxassetid://112199646421676",
	Luck = "rbxassetid://86611651520562",
}
local HOLD_ATTRIBUTES: { [Kind]: string } = { Wool = "WoolLabelHold", Luck = "LuckLabelHold" }

-- One pooled DropTemplate clone and the pieces of it that get updated.
type DropObject = {
	part: BasePart,
	gui: BillboardGui,
	icon: ImageLabel,
	label: TextLabel,
	trail: Trail?,
}

type ActiveDrop = {
	object: DropObject,
	kind: Kind,
	amount: number,
	origin: Vector3,
	ground: Vector3,
	startAt: number,
	started: boolean,
	root: BasePart, -- pulled towards the current character's root, or this one if it is gone
	pop: () -> (),
}

type Total = {
	gui: BillboardGui,
	label: TextLabel,
	amount: number,
	token: number,
}

-- The server's payout for one sheep a swing hit (see ShearHandler).
type DropInfo = {
	position: Vector3,
	wool: number,
	luck: number,
	fraction: number,
	luckDrops: boolean,
}

--// State
local holdToken = 0
local idleDrops: { DropObject } = {}
local activeDrops: { ActiveDrop } = {}
local totals: { [Kind]: Total } = {}
local heartbeatConnection: RBXScriptConnection? = nil
local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

-- Created by this client, so the drops only exist locally.
local dropFolder = Instance.new("Folder")
dropFolder.Name = "WoolDrops"
dropFolder.Parent = workspace

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.CollisionGroup = "Players" -- skips sheep, which don't collide with players
groundParams.RespectCanCollide = true

--// Helpers -------------------------------------------------------------------

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

-- Lets the icon and text spill past their frames instead of being cut off.
local function disableClipping(gui: BillboardGui)
	gui.ClipsDescendants = false
	for _, descendant in gui:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ClipsDescendants = false
		end
	end
end

local function formatAmount(amount: number): string
	return `+{numberFormatter:Format(amount, 1)}`
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

-- Holds back `change` more of this currency from its counter (negative = lets some through).
local function changeHeld(kind: Kind, change: number)
	local attribute = HOLD_ATTRIBUTES[kind]
	local held = player:GetAttribute(attribute)
	player:SetAttribute(attribute, math.max((if type(held) == "number" then held else 0) + change, 0))
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

-- The total over the character bounces a little every time a drop lands in it.
local function punchLabel(label: GuiObject)
	local scale = getScale(label)
	scale.Scale = 1.18
	tweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Where a drop scattered to `point` comes to rest: just above the ground under it.
local function findGround(point: Vector3): Vector3
	groundParams.FilterDescendantsInstances = if player.Character then { player.Character, dropFolder } else { dropFolder }
	local result = workspace:Raycast(point + Vector3.new(0, 3, 0), Vector3.new(0, -25, 0), groundParams)
	local ground = if result then result.Position else point - Vector3.new(0, 2.5, 0)
	return ground + Vector3.new(0, DROP_GROUND_LIFT, 0)
end

--// HUD counters ------------------------------------------------------------------------

-- Lets `amount` of the held currency through to its counter, which ClientStart pulses as it goes up.
local function addToCounter(kind: Kind, amount: number)
	changeHeld(kind, -amount)
end

--// Totals over the character ---------------------------------------------------------------

local function getTotal(kind: Kind, root: BasePart): Total
	local total = totals[kind]
	if total and total.gui.Parent == root then
		return total
	end
	if total then
		total.gui:Destroy()
	end

	local gui = (dropTemplate:FindFirstChild("BillboardGui") :: BillboardGui):Clone()
	gui.Name = `{kind}Total`
	gui.AlwaysOnTop = true
	gui.Enabled = false
	disableClipping(gui)
	gui.Adornee = root
	gui.Parent = root
	;(gui:FindFirstChild("Icon") :: ImageLabel).Image = ICONS[kind]

	local newTotal = { gui = gui, label = gui:FindFirstChild("TextLabel") :: TextLabel, amount = 0, token = 0 }
	totals[kind] = newTotal
	return newTotal
end

-- Adds a landed drop to the "+N" on the character's root, which hides once the drops stop coming.
local function addToTotal(kind: Kind, root: BasePart, amount: number)
	if not root.Parent then
		return
	end

	local total = getTotal(kind, root)
	total.amount += amount
	total.label.Text = formatAmount(total.amount)
	total.gui.Enabled = true
	punchLabel(total.label)

	if kind == "Luck" then
		local woolTotal = totals["Wool" :: Kind]
		local stacked = woolTotal ~= nil and woolTotal.gui.Enabled and woolTotal.gui.Parent == root
		total.gui.StudsOffset = if stacked then TOTAL_STACK_OFFSET else TOTAL_OFFSET
	else
		total.gui.StudsOffset = TOTAL_OFFSET
	end

	total.token += 1
	local token = total.token
	task.delay(TOTAL_HIDE_SECONDS, function()
		if token == total.token then
			total.gui.Enabled = false
			total.amount = 0
		end
	end)
end

--// Drop pool ---------------------------------------------------------------------

local function createDropObject(): DropObject
	local part = dropTemplate:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = PARK_CFRAME

	local gui = part:FindFirstChild("BillboardGui") :: BillboardGui
	gui.Enabled = false
	disableClipping(gui)
	local trail = part:FindFirstChildOfClass("Trail")
	if trail then
		trail.Enabled = false
	end

	part.Parent = dropFolder
	return {
		part = part,
		gui = gui,
		icon = gui:FindFirstChild("Icon") :: ImageLabel,
		label = gui:FindFirstChild("TextLabel") :: TextLabel,
		trail = trail,
	}
end

local function releaseDrop(object: DropObject)
	object.gui.Enabled = false
	if object.trail then
		object.trail.Enabled = false
	end
	object.part.CFrame = PARK_CFRAME
	table.insert(idleDrops, object)
end

for _ = 1, PREWARM_DROPS do
	table.insert(idleDrops, createDropObject())
end

--// Drop movement -----------------------------------------------------------------

-- Where a drop is `elapsed` seconds after it started, or nil once it has reached the character.
local function getDropPosition(drop: ActiveDrop, elapsed: number, target: Vector3): Vector3?
	if elapsed < DROP_FALL_SECONDS then
		return parabola(drop.origin, drop.ground, DROP_FALL_HEIGHT, elapsed / DROP_FALL_SECONDS)
	end

	local bounceElapsed = elapsed - DROP_FALL_SECONDS
	if bounceElapsed < DROP_BOUNCE_SECONDS then
		local t = bounceElapsed / DROP_BOUNCE_SECONDS
		return drop.ground + Vector3.new(0, 4 * DROP_BOUNCE_HEIGHT * t * (1 - t), 0)
	end

	local pullElapsed = bounceElapsed - DROP_BOUNCE_SECONDS
	if pullElapsed >= DROP_PULL_SECONDS then
		return nil
	end
	return parabola(drop.ground, target, DROP_PULL_HEIGHT, smoothstep(pullElapsed / DROP_PULL_SECONDS))
end

local function arrive(drop: ActiveDrop, root: BasePart)
	releaseDrop(drop.object)
	drop.pop()
	addToTotal(drop.kind, root, drop.amount)
	addToCounter(drop.kind, drop.amount)
end

-- One loop moves every drop in a single BulkMoveTo, and only runs while there are drops.
local function stepDrops()
	local now = os.clock()
	local currentRoot = getCharacterRoot()
	local count = 0

	for index = #activeDrops, 1, -1 do
		local drop = activeDrops[index]
		local elapsed = now - drop.startAt
		if elapsed < 0 then
			continue
		end

		if not drop.started then
			drop.started = true
			drop.object.gui.Enabled = true
			if drop.object.trail then
				drop.object.trail:Clear()
				drop.object.trail.Enabled = true
			end
		end

		local root = currentRoot or drop.root
		local position = getDropPosition(drop, elapsed, root.Position)
		if position then
			count += 1
			moveParts[count] = drop.object.part
			moveCFrames[count] = CFrame.new(position)
		else
			activeDrops[index] = activeDrops[#activeDrops]
			activeDrops[#activeDrops] = nil
			arrive(drop, root)
		end
	end

	for index = #moveParts, count + 1, -1 do
		moveParts[index] = nil
		moveCFrames[index] = nil
	end
	if count > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end

	if #activeDrops == 0 and heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function spawnDrops(kind: Kind, origin: Vector3, amount: number, count: number, root: BasePart, pop: () -> ())
	local now = os.clock()
	for index, share in splitShares(amount, count) do
		local object = table.remove(idleDrops) or createDropObject()
		object.icon.Image = ICONS[kind]
		object.label.Text = formatAmount(share)
		object.part.CFrame = CFrame.new(origin)

		local angle = math.random() * math.pi * 2
		local scatter = Vector3.new(math.cos(angle), 0, math.sin(angle)) * DROP_SCATTER_RADIUS * (0.4 + math.random() * 0.6)

		table.insert(activeDrops, {
			object = object,
			kind = kind,
			amount = share,
			origin = origin,
			ground = findGround(origin + scatter),
			startAt = now + (index - 1) * DROP_STAGGER_SECONDS,
			started = false,
			root = root,
			pop = pop,
		})
	end

	if not heartbeatConnection then
		heartbeatConnection = runService.Heartbeat:Connect(stepDrops)
	end
end

--[[
	Splits one hit's `amount` into drops: more the bigger a share of the sheep the hit took, never more than the amount,
	the per-hit cap or the free room under MAX_ACTIVE_DROPS. With no room it goes straight to the total and counter.
	The counter is already holding `amount` back.
]]
local function dropCurrency(kind: Kind, origin: Vector3, amount: number, fraction: number, pop: () -> ())
	local root = getCharacterRoot()
	local wanted = math.clamp(math.round(fraction * DROPS_PER_FULL_SHEEP), 1, MAX_DROPS_PER_HIT)
	local count = math.min(wanted, math.floor(amount), MAX_ACTIVE_DROPS - #activeDrops)

	if not root or count <= 0 then
		if root then
			addToTotal(kind, root, amount)
		end
		addToCounter(kind, amount)
		return
	end
	spawnDrops(kind, origin, amount, count, root, pop)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.SheepSheared, function(drops: { DropInfo })
	-- Hold the payout back straight away, before the counters show it. A Luck sheep's wool isn't dropped, so it isn't held.
	for _, info in drops do
		if info.wool > 0 and not info.luckDrops then
			changeHeld("Wool", info.wool)
		end
		if info.luck > 0 then
			changeHeld("Luck", info.luck)
		end
	end

	holdToken += 1
	local token = holdToken
	task.delay(HOLD_TIMEOUT_SECONDS, function()
		if token == holdToken then
			-- Something went wrong; show the real numbers.
			player:SetAttribute("WoolLabelHold", 0)
			player:SetAttribute("LuckLabelHold", 0)
		end
	end)

	local pop = newPopSequence(PUFF_POP_GAP_SECONDS)
	for _, info in drops do
		if info.wool > 0 and not info.luckDrops then
			dropCurrency("Wool", info.position, info.wool, info.fraction, pop)
		end
		if info.luck > 0 then
			dropCurrency("Luck", info.position, info.luck, info.fraction, pop)
		end
	end
end)
