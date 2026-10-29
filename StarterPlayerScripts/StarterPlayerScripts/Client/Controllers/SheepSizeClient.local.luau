--!strict

--[[
	Gives Giant and Colossal sheep a soft glow in their size colour, and pops an announcement when one spawns on your plot.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SheepSizeClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")

--// Modules
local announcements = require(script.Parent.Parent.Modules.Announcements)

--// Configs
local SHEEP_TAG = "Sheep"
local AURA_NAME = "SizeAura"
local ANNOUNCED_TIERS = { Giant = true, Colossal = true } -- mirrors the server's SheepSizeData ids
local FRESH_SECONDS = 3 -- older sheep are ones streaming in, not new spawns
local ROOT_TIMEOUT = 5
local LIGHT_RANGE = 10 -- studs
local LIGHT_BRIGHTNESS = 1.5
local PARTICLE_RATE = 4 -- per second

--// State
local localPlayer = players.LocalPlayer
local tracked: { [Instance]: boolean } = {}

--// Helpers -------------------------------------------------------------------------

local function addAura(root: BasePart, color: Color3)
	local aura = Instance.new("Attachment")
	aura.Name = AURA_NAME

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = LIGHT_RANGE
	light.Brightness = LIGHT_BRIGHTNESS
	light.Shadows = false
	light.Parent = aura

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.Rate = PARTICLE_RATE
	sparkles.Lifetime = NumberRange.new(1.2, 2)
	sparkles.Speed = NumberRange.new(1, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new(0.3, 1)
	sparkles.Parent = aura

	aura.Parent = root
end

local function announce(sheep: Instance, color: Color3)
	local tier = sheep:GetAttribute("SizeTier")
	local name = sheep:GetAttribute("SheepName")
	local weight = sheep:GetAttribute("Weight")
	if type(tier) ~= "string" or type(name) ~= "string" then
		return
	end

	-- SheepName already carries the size prefix; only that word is coloured.
	local coloredName = string.gsub(name, tier, `<font color="#{color:ToHex()}">{string.upper(tier)}</font>`, 1)
	local weightText = if type(weight) == "number" then ` ({weight} kg)` else ""
	announcements.show("ClaimAlert", `A {coloredName} appeared!{weightText}`, true)
end

local function onSheepAdded(sheep: Instance)
	local tier = sheep:GetAttribute("SizeTier")
	local color = sheep:GetAttribute("SizeColor")
	if type(tier) ~= "string" or not ANNOUNCED_TIERS[tier] or typeof(color) ~= "Color3" then
		return
	end
	tracked[sheep] = true

	local spawnedAt = sheep:GetAttribute("SpawnedAt")
	if sheep:GetAttribute("OwnerId") == localPlayer.UserId
		and type(spawnedAt) == "number"
		and workspace:GetServerTimeNow() - spawnedAt <= FRESH_SECONDS
	then
		announce(sheep, color)
	end

	task.spawn(function()
		local root = sheep:FindFirstChild("HumanoidRootPart") or sheep:WaitForChild("HumanoidRootPart", ROOT_TIMEOUT)
		if tracked[sheep] and root and root:IsA("BasePart") and not root:FindFirstChild(AURA_NAME) then
			addAura(root, color)
		end
	end)
end

-- The tag comes off as a bare sheep vanishes, or when it streams out or is pooled away.
local function onSheepRemoved(sheep: Instance)
	if not tracked[sheep] then
		return
	end
	tracked[sheep] = nil

	local root = sheep:FindFirstChild("HumanoidRootPart")
	local aura = root and root:FindFirstChild(AURA_NAME)
	if aura then
		aura:Destroy()
	end
end

--// Setup -------------------------------------------------------------------------------

for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
	onSheepAdded(sheep)
end
collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(onSheepRemoved)
