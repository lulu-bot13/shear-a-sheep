--!strict

--[[
	Scrolls the rainbow across every Rainbow sheep's name: SheepHandler tags a UIGradient on those labels, this cycles its colours.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

--// Configs
local RAINBOW_TAG = "RainbowName" -- mirrors MutationData.RainbowGradientTag
local KEYPOINTS = 8 -- colour stops across the name
local BANDS = 1 -- full rainbows across the name at once
local CYCLE_SECONDS = 2 -- one full trip through the rainbow
local SATURATION = 0.65
local VALUE = 1
local UPDATE_SECONDS = 1 / 30

--// State
local gradients: { [UIGradient]: boolean } = {}
local gradientCount = 0
local elapsed = 0

-- The rainbow, shifted along by `phase` (0 to 1) so it seems to slide to the left.
local function buildRainbow(phase: number): ColorSequence
	local keypoints = table.create(KEYPOINTS + 1)
	for i = 0, KEYPOINTS do
		local t = i / KEYPOINTS
		local hue = (t * BANDS + phase) % 1
		keypoints[i + 1] = ColorSequenceKeypoint.new(t, Color3.fromHSV(hue, SATURATION, VALUE))
	end
	return ColorSequence.new(keypoints)
end

local function onHeartbeat(deltaTime: number)
	elapsed += deltaTime
	if elapsed < UPDATE_SECONDS or gradientCount == 0 then
		return
	end
	elapsed = 0

	local rainbow = buildRainbow((os.clock() / CYCLE_SECONDS) % 1) -- one sequence shared by all, so every name moves in step
	for gradient in gradients do
		gradient.Color = rainbow
	end
end

local function onTagged(instance: Instance)
	if instance:IsA("UIGradient") and not gradients[instance] then
		gradients[instance] = true
		gradientCount += 1
	end
end

local function onUntagged(instance: Instance)
	if gradients[instance :: UIGradient] then
		gradients[instance :: UIGradient] = nil
		gradientCount -= 1
	end
end

--// Setup -------------------------------------------------------------------------------

for _, instance in collectionService:GetTagged(RAINBOW_TAG) do
	onTagged(instance)
end
collectionService:GetInstanceAddedSignal(RAINBOW_TAG):Connect(onTagged)
collectionService:GetInstanceRemovedSignal(RAINBOW_TAG):Connect(onUntagged)
runService.Heartbeat:Connect(onHeartbeat)
