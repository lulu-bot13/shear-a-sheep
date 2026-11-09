--!strict

--[[
	Tweens each sheep's HealthHUD bar down as it is sheared, shading it from green through yellow to orange.
	Runs locally from ShearHealth so the bar drains smoothly; SheepHandler only shows the HUD and sets its text.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SheepHealthBarClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// References
local healthHudTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("UI"):WaitForChild("SheepProgression")
local fullBarSize = (healthHudTemplate:FindFirstChild("Bar", true) :: Frame).Size

--// Configs
local SHEEP_TAG = "Sheep"
local HEALTH_HUD_NAME = "HealthHUD" -- built by SheepHandler on each sheep's HumanoidRootPart
local FULL_COLOR = Color3.fromRGB(90, 220, 100)
local HALF_COLOR = Color3.fromRGB(255, 215, 60)
local LOW_COLOR = Color3.fromRGB(255, 140, 40)
local DRAIN_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// Types
type Entry = {
	connections: { RBXScriptConnection },
	tween: Tween?,
	ratio: number?, -- what the bar last showed; nil until it has been found
}

--// State
local entries: { [Instance]: Entry } = {}

-- Green when full, yellow at half, orange when nearly bare.
local function getColor(ratio: number): Color3
	if ratio >= 0.5 then
		return HALF_COLOR:Lerp(FULL_COLOR, (ratio - 0.5) * 2)
	end
	return LOW_COLOR:Lerp(HALF_COLOR, ratio * 2)
end

local function getBar(sheep: Instance): Frame?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	local hud = root and root:FindFirstChild(HEALTH_HUD_NAME)
	local bar = hud and hud:FindFirstChild("Bar", true)
	return if bar and bar:IsA("Frame") then bar else nil
end

local function getRatio(sheep: Instance): number?
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return nil
	end
	return math.clamp(health / maxHealth, 0, 1)
end

-- Drains the bar when health drops; snaps it when the sheep first appears or is refilled (a pooled model reused).
local function updateBar(sheep: Instance, entry: Entry)
	local bar = getBar(sheep)
	local ratio = getRatio(sheep)
	if not bar or not ratio then
		return
	end

	if entry.tween then
		entry.tween:Cancel()
		entry.tween = nil
	end

	local size = UDim2.new(fullBarSize.X.Scale * ratio, fullBarSize.X.Offset * ratio, fullBarSize.Y.Scale, fullBarSize.Y.Offset)
	local color = getColor(ratio)
	local draining = entry.ratio ~= nil and ratio < entry.ratio
	entry.ratio = ratio

	if draining then
		local tween = tweenService:Create(bar, DRAIN_TWEEN, { Size = size, BackgroundColor3 = color })
		entry.tween = tween
		tween:Play()
	else
		bar.Size = size
		bar.BackgroundColor3 = color
	end
end

local function onSheepAdded(sheep: Instance)
	if entries[sheep] then
		return
	end

	local entry: Entry = { connections = {}, tween = nil, ratio = nil }
	entries[sheep] = entry

	table.insert(entry.connections, sheep:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateBar(sheep, entry)
	end))
	-- The root and its HUD can stream in after the tagged model does.
	table.insert(entry.connections, sheep.DescendantAdded:Connect(function(descendant: Instance)
		if descendant.Name == HEALTH_HUD_NAME then
			updateBar(sheep, entry)
		end
	end))
	updateBar(sheep, entry)
end

local function onSheepRemoved(sheep: Instance)
	local entry = entries[sheep]
	if not entry then
		return
	end

	entries[sheep] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	if entry.tween then
		entry.tween:Cancel()
	end
end

for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
	onSheepAdded(sheep)
end
collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(onSheepRemoved)
