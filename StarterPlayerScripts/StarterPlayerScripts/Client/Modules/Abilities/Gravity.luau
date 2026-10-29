--[[
	Gravity's effect for everyone: the caster's sheep float up, wobble while their wool rains down as puffs, then drop back with a dust puff.
	The server anchors them and sends the timeline; this only moves the roots locally, on the server's clock.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Abilities.Gravity
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local GroundBurst = require(script.Parent.Parent.GroundBurst)

--// Instances
local localPlayer = players.LocalPlayer
local vfxFolder = replicatedStorage:WaitForChild("Assets"):FindFirstChild("VFX")

--// Configs
local SHEEP_TAG = "Sheep"
local AURA_NAME = "GravityAura" -- optional Attachment in Assets.VFX, copied onto each lifted sheep
local START_SOUND_ID = "rbxassetid://81041899079235" -- the moment the ability is cast
local RISE_SOUND_ID = "rbxassetid://93437354284012" -- as the sheep lift off
local LAND_SOUND_ID = "rbxassetid://75168747667192" -- the thud when they come back down
local SOUND_LIFETIME = 5
local TURN_ANGLE = math.rad(70) -- each sheep turns this far and back over the flight
local BOB_HEIGHT = 0.6 -- studs up and down while hanging
local BOB_SPEED = 3
local SHAKE_ANGLE = math.rad(14) -- the side-to-side wobble that shakes the wool out
local SHAKE_SPEED = 26
local MAX_PUFFS = 90 -- wool puffs across all sheep, so a full farm doesn't flood the client
local MAX_PUFFS_PER_SHEEP = 5
local PUFF_MIN_SECONDS = 0.5
local PUFF_MAX_SECONDS = 0.8
local PUFF_SHRINK_SECONDS = 0.2
local PARK_CFRAME = CFrame.new(0, 10000, 0)

type Entry = {
	sheep: Model,
	root: BasePart,
	id: any,
	base: CFrame,
	groundY: number,
	color: Color3,
	phase: number,
	aura: Instance?,
}

--// State
local random = Random.new()
local idlePuffs: { Part } = {}

local puffFolder = Instance.new("Folder")
puffFolder.Name = "GravityPuffs"
puffFolder.Parent = workspace

local Gravity = {}

--// Helpers -------------------------------------------------------------------------

local function isValid(entry: Entry): boolean
	local sheep = entry.sheep
	return sheep.Parent ~= nil and collectionService:HasTag(sheep, SHEEP_TAG) and sheep:GetAttribute("id") == entry.id
end

local function playSound(soundId: string, position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = attachment
	sound:Play()
	task.delay(math.max(sound.TimeLength, SOUND_LIFETIME), function()
		attachment:Destroy()
	end)
end

local function attachAura(root: BasePart): Instance?
	local template = vfxFolder and vfxFolder:FindFirstChild(AURA_NAME)
	if not template or not template:IsA("Attachment") then
		return nil
	end

	local aura = template:Clone()
	aura.Parent = root
	return aura
end

local function acquirePuff(): Part
	local puff = table.remove(idlePuffs)
	if puff then
		return puff
	end

	local newPuff = Instance.new("Part")
	newPuff.Name = "WoolPuff"
	newPuff.Shape = Enum.PartType.Ball
	newPuff.Material = Enum.Material.SmoothPlastic
	newPuff.Anchored = true
	newPuff.CanCollide = false
	newPuff.CanTouch = false
	newPuff.CanQuery = false
	newPuff.CastShadow = false
	newPuff.Parent = puffFolder
	return newPuff
end

local function releasePuff(puff: Part)
	puff.CFrame = PARK_CFRAME
	table.insert(idlePuffs, puff)
end

-- A tuft of wool that drops from the hanging sheep to the grass under it and shrinks away.
local function dropPuff(entry: Entry)
	if not isValid(entry) then
		return
	end

	local puff = acquirePuff()
	local size = random:NextNumber(0.6, 1.2)
	local scatter = Vector3.new(random:NextNumber(-1.5, 1.5), random:NextNumber(-0.5, 0.5), random:NextNumber(-1.5, 1.5))
	local start = entry.root.Position + scatter
	local landing = Vector3.new(start.X + scatter.X, entry.groundY + size / 2, start.Z + scatter.Z)
	puff.Size = Vector3.one * size
	puff.Color = entry.color
	puff.CFrame = CFrame.new(start)

	local fall = tweenService:Create(puff, TweenInfo.new(random:NextNumber(PUFF_MIN_SECONDS, PUFF_MAX_SECONDS), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(landing),
	})
	local shrink = tweenService:Create(puff, TweenInfo.new(PUFF_SHRINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.3), {
		Size = Vector3.one * 0.05,
	})
	fall.Completed:Once(function()
		shrink:Play()
	end)
	shrink.Completed:Once(function()
		releasePuff(puff)
	end)
	fall:Play()
end

-- How far up the sheep is and how it is turned, `elapsed` seconds into the flight.
local function getPose(entry: Entry, elapsed: number, rise: number, hang: number, fall: number, height: number): CFrame
	local total = rise + hang + fall
	local turn = TURN_ANGLE * math.sin(math.pi * math.clamp(elapsed / total, 0, 1))
	local lift, wobble = 0, 0

	if elapsed <= 0 then
		lift = 0
	elseif elapsed < rise then
		lift = height * (1 - math.cos(math.pi * elapsed / rise)) / 2
	elseif elapsed < rise + hang then
		local hanging = elapsed - rise
		local fade = math.min(hanging / 0.25, 1) -- eases into the bob instead of snapping
		lift = height + math.sin(hanging * BOB_SPEED + entry.phase) * BOB_HEIGHT * fade
		wobble = math.sin(hanging * SHAKE_SPEED + entry.phase) * SHAKE_ANGLE * fade
	elseif elapsed < total then
		local falling = (elapsed - rise - hang) / fall
		lift = height * (1 - falling * falling)
	end

	return (entry.base + Vector3.new(0, lift, 0)) * CFrame.Angles(0, turn, wobble)
end

--// Effect --------------------------------------------------------------------------

local function buildEntries(list: { any }): { Entry }
	local entries: { Entry } = {}
	for _, item in list do
		local sheep = type(item) == "table" and item.sheep
		local base = type(item) == "table" and item.base
		if typeof(sheep) ~= "Instance" or not sheep:IsA("Model") or typeof(base) ~= "CFrame" then
			continue -- streamed out on this client
		end

		local root = sheep:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			continue
		end

		local humanoid = sheep:FindFirstChildOfClass("Humanoid")
		local standHeight = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2)
		table.insert(entries, {
			sheep = sheep,
			root = root,
			id = sheep:GetAttribute("id"),
			base = base,
			groundY = base.Position.Y - standHeight,
			color = if typeof(item.color) == "Color3" then item.color else Color3.new(1, 1, 1),
			phase = random:NextNumber(0, math.pi * 2),
			aura = attachAura(root),
		})
	end
	return entries
end

local function getCenter(entries: { Entry }): Vector3
	local sum = Vector3.zero
	for _, entry in entries do
		sum += entry.base.Position
	end
	return sum / #entries
end

local function scheduleWoolRain(entries: { Entry }, rainAt: number, hang: number)
	local perSheep = math.clamp(math.floor(MAX_PUFFS / #entries), 1, MAX_PUFFS_PER_SHEEP)
	for _, entry in entries do
		for _ = 1, perSheep do
			task.delay(math.max(rainAt + random:NextNumber(0, hang * 0.85), 0), dropPuff, entry)
		end
	end
end

local function playLanding(caster: Player, entries: { Entry })
	for _, entry in entries do
		if entry.sheep.Parent ~= nil then -- landing shears them bare, so they may have lost the Sheep tag already
			GroundBurst.play(entry.base.Position, {
				chunkCount = 0,
				debrisCount = 0,
				dustCount = 6,
				shockwaveRadius = 4,
				ignore = { entry.sheep },
			})
		end
	end

	local center = getCenter(entries)
	playSound(LAND_SOUND_ID, center)
	if caster == localPlayer then
		GroundBurst.play(center, { chunkCount = 0, debrisCount = 0, dustCount = 0, shockwaveRadius = 0, shake = 0.6, shakeRange = 150 })
	end
end

function Gravity.onEffect(caster: Player, info: any)
	if type(info) ~= "table" or type(info.sheep) ~= "table" or type(info.startsAt) ~= "number" then
		return
	end
	local rise, hang, fall, height = info.riseSeconds, info.hangSeconds, info.fallSeconds, info.height
	if type(rise) ~= "number" or type(hang) ~= "number" or type(fall) ~= "number" or type(height) ~= "number" then
		return
	end

	local entries = buildEntries(info.sheep)
	if #entries == 0 then
		return
	end

	local startsAt: number = info.startsAt
	local secondsToStart = startsAt - workspace:GetServerTimeNow()
	local total = rise + hang + fall
	local center = getCenter(entries)
	playSound(START_SOUND_ID, center)
	task.delay(math.max(secondsToStart, 0), playSound, RISE_SOUND_ID, center)
	scheduleWoolRain(entries, secondsToStart + rise, hang)
	task.delay(math.max(secondsToStart + total, 0), playLanding, caster, entries)

	local connection: RBXScriptConnection
	connection = runService.RenderStepped:Connect(function()
		local elapsed = workspace:GetServerTimeNow() - startsAt
		local finished = elapsed >= total
		for _, entry in entries do
			if isValid(entry) then
				entry.root.CFrame = if finished then entry.base else getPose(entry, elapsed, rise, hang, fall, height)
			end
		end

		if finished then
			connection:Disconnect()
			for _, entry in entries do
				if entry.aura then
					entry.aura:Destroy()
				end
			end
		end
	end)
end

return Gravity
