--!strict

--[[
	Scrolls the rainbow across a Rainbow sheep's popup name and wraps Rainbow sheep in a Highlight that tweens round the rainbow.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.MutationClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Configs
local RAINBOW_TAG = "RainbowName" -- mirrors MutationData.RainbowGradientTag
local SHEEP_TAG = "Sheep"
local MUTATION_ATTRIBUTE = "Mutation" -- mirrors MutationData.Attribute
local RAINBOW_MUTATION = "Rainbow"
local HIGHLIGHT_NAME = "RainbowHighlight"
local HIGHLIGHT_CYCLE_SECONDS = 3 -- one full trip round the rainbow
local HIGHLIGHT_SATURATION = 0.8
local FILL_TRANSPARENCY = 0.8
local OUTLINE_TRANSPARENCY = 0
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
local highlightTweens: { [Instance]: { Tween } } = {}

--[[
	The six hue corners at one saturation: tweening straight between neighbours keeps saturation and brightness fixed,
	so linear RGB tweens trace the exact HSV rainbow with no per-frame Lua.
]]
local hueStops = table.create(6)
for i = 0, 5 do
	hueStops[i + 1] = Color3.fromHSV(i / 6, HIGHLIGHT_SATURATION, 1)
end
local stageInfo = TweenInfo.new(HIGHLIGHT_CYCLE_SECONDS / #hueStops, Enum.EasingStyle.Linear)

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

--// Rainbow highlight ---------------------------------------------------------------------

-- Each stage's tween plays the next when it finishes, so the colour loops forever; a cancel stops the chain.
local function addHighlight(sheep: Instance)
	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.FillTransparency = FILL_TRANSPARENCY
	highlight.OutlineTransparency = OUTLINE_TRANSPARENCY
	highlight.FillColor = hueStops[#hueStops]
	highlight.OutlineColor = hueStops[#hueStops]

	local tweens = table.create(#hueStops)
	for i, color in hueStops do
		tweens[i] = tweenService:Create(highlight, stageInfo, { FillColor = color, OutlineColor = color })
	end
	for i, tween in tweens do
		local nextTween = tweens[i % #tweens + 1]
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				nextTween:Play()
			end
		end)
	end

	highlight.Parent = sheep
	highlightTweens[sheep] = tweens
	tweens[1]:Play()
end

local function removeHighlight(sheep: Instance)
	local tweens = highlightTweens[sheep]
	if not tweens then
		return
	end
	highlightTweens[sheep] = nil
	for _, tween in tweens do
		tween:Destroy()
	end

	local highlight = sheep:FindFirstChild(HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end
end

local function onSheepAdded(sheep: Instance)
	if sheep:GetAttribute(MUTATION_ATTRIBUTE) == RAINBOW_MUTATION and not highlightTweens[sheep] then
		addHighlight(sheep)
	end
end

--// Setup -------------------------------------------------------------------------------

for _, instance in collectionService:GetTagged(RAINBOW_TAG) do
	onTagged(instance)
end
collectionService:GetInstanceAddedSignal(RAINBOW_TAG):Connect(onTagged)
collectionService:GetInstanceRemovedSignal(RAINBOW_TAG):Connect(onUntagged)
runService.Heartbeat:Connect(onHeartbeat)

-- The Sheep tag comes off when a model is pooled or streams out, so a reused model never keeps a stale highlight.
for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
	onSheepAdded(sheep)
end
collectionService:GetInstanceAddedSignal(SHEEP_TAG):Connect(onSheepAdded)
collectionService:GetInstanceRemovedSignal(SHEEP_TAG):Connect(removeHighlight)
