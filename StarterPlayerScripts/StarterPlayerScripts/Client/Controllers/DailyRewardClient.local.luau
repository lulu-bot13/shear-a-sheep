--[[
	The Daily Rewards window (StarterGui.DailyRewards): fills and shines the day cards, marks claimed and today's card, ticks the timer
	and claims; it opens itself once on join when a reward is waiting. DailyRewardHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.DailyRewardClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local iconIds = require(replicatedStorage.Shared.Constants.IconIds)
local iconUtil = require(replicatedStorage.Shared.Utils.IconUtil)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local alertPulse = require(script.Parent.Parent.Modules.AlertPulse)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local dailyGui = playerGui:WaitForChild("DailyRewards") :: ScreenGui
local mainFrame = dailyGui:WaitForChild("Main") :: GuiObject
local streakLabel = mainFrame:WaitForChild("Streak") :: TextLabel
local timerLabel = mainFrame:WaitForChild("Timer") :: TextLabel
local claimButton = mainFrame:WaitForChild("Claim") :: GuiButton
local daysFrame = mainFrame:WaitForChild("Days")
local dayTemplate = daysFrame:WaitForChild("DayTemplate") :: GuiObject
local day7Card = mainFrame:WaitForChild("Day7")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local hudButtons = playerGui:WaitForChild("Main"):FindFirstChild("Buttons")
local hudButton = hudButtons and hudButtons:FindFirstChild("DailyRewards")
local alertBadge = hudButton and hudButton:FindFirstChild("Alert") :: GuiObject?

--// Sounds
local uiSounds = soundService:WaitForChild("UISounds")

--// Configs
local CLONED_DAYS = 6 -- days 1 to 6 are cloned from the template; day 7 is the big pre-built card (its GemIcon is set in Studio)
-- All the wool icon for now; each day can be swapped for its own image.
local DAY_ICONS = {
	[1] = iconIds.Wool,
	[2] = iconIds.Wool,
	[3] = iconIds.Wool,
	[4] = iconIds.Wool,
	[5] = iconIds.Wool,
	[6] = iconIds.Wool,
}
local CLAIM_SOUND = "Cash" -- in SoundService.UISounds
local TODAY_PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local TODAY_PULSE_SCALE = 1.08 -- of the TodayBadge's resting UIScale
local CARD_SHINE_INTERVAL = 4 -- seconds between one card's shines; each unclaimed card keeps its own timer
local SHINE_JITTER = 0.4 -- each wait is the interval +/- up to this fraction of it, so cards drift apart
local CLAIM_SHINE_INTERVAL = 2.5 -- seconds between Claim button shines, only while a reward is ready
local SHINE_FIRST_DELAY = 0.3 -- after the window opens; each card's first shine comes at a random point after this
local ROTATING_SHINE_TAG = "RotatingShine" -- spun by ShineRotate
local SHINE_SPEED_ATTRIBUTE = "ShineSpeed" -- read by ShineRotate
local ROTATING_SHINE_SPEED = 30 -- degrees per second; mirrors ShineRotate's default, used when the Shine has no ShineSpeed of its own
local SPIN_JITTER = 0.3 -- each card's spin speed is its base +/- up to this fraction
local CARD_ART_NAME = "Background" -- a card's art image; the sweep crosses it, under the card's icons and text
local SHINE_TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SHINE_START = Vector2.new(-1, 0)
local SHINE_END = Vector2.new(1, 0)
local SHINE_ROTATION = 25
local SHINE_WIDTH = 0.14 -- fraction of the gradient the band covers
local SHINE_TRANSPARENCY = 0.4 -- at the centre of the band
local SHINE_SEQUENCE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5 - SHINE_WIDTH / 2, 1),
	NumberSequenceKeypoint.new(0.5, SHINE_TRANSPARENCY),
	NumberSequenceKeypoint.new(0.5 + SHINE_WIDTH / 2, 1),
	NumberSequenceKeypoint.new(1, 1),
})
-- The art's rounded corners are baked in, so the shine is rounded to match unless the target has its own UICorner.
local CARD_SHINE_CORNER = UDim.new(0.12, 0)
local CLAIM_SHINE_CORNER = UDim.new(0.35, 0)
local CLAIM_LATER_TEXT = "COME BACK LATER"
local READY_TEXT = "YOUR REWARD IS READY!"
local GREY_GRADIENT = ColorSequence.new(Color3.fromRGB(175, 175, 175), Color3.fromRGB(115, 115, 115)) -- matches RebirthClient
local TICK_SECONDS = 0.25
local REFRESH_RETRY_SECONDS = 2 -- asks again if the state asked for when the timer ran out hasn't come
local CLAIM_TIMEOUT = 3 -- the Claim button unlocks again if no result came back
local AUTO_OPEN_SETTLE_SECONDS = 1.5 -- the way must be clear this long, so it doesn't pop over the tutorial's completed label
local MAIN_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local CROOK_ACTIVE_ATTRIBUTE = "CrookTutorialActive" -- set on the Tutorial gui by CrookTutorialClient while it runs
local SHEAR_ACTIVE_ATTRIBUTE = "ShearTutorialActive" -- set on the Tutorial gui by ShearTutorialClient while it runs
local CROOK_NAME = "ShepherdsCrook"
local CARRY_ATTRIBUTE = "CarryingSheep" -- set by SheepCarryHandler while a sheep is carried

local REASON_TEXT = {
	NotReady = "Come back later for your next reward!",
	NotLoaded = "Still loading, try again in a moment",
}

type Shine = {
	frame: Frame,
	gradient: UIGradient,
	tween: Tween,
}

type Card = {
	icon: ImageLabel?,
	amount: TextLabel?,
	claimed: GuiObject?,
	todayBadge: GuiObject?,
	todayScale: UIScale?,
	todayBaseScale: number,
	pulse: Tween?,
	shine: Shine,
	shineAt: number, -- os.clock() this card's next shine is due
}

--// State
local state: any = nil -- the last DailyRewardState from the server
local deadline = 0 -- os.clock() the next reward opens, from state.secondsLeft
local nextRefreshAt = 0
local claiming = false
local claimToken = 0
local cards: { [number]: Card } = {}
local shineLoop: RBXScriptConnection? = nil
local nextClaimShineAt = 0
local random = Random.new()

local claimLabel: any = if claimButton:IsA("TextButton") and claimButton.Text ~= "" then claimButton
	else claimButton:FindFirstChildWhichIsA("TextLabel", true) or claimButton
local claimText = claimLabel.Text
local claimGradient = claimButton:FindFirstChildOfClass("UIGradient")
local claimGradientColor = if claimGradient then claimGradient.Color else nil

--// Helpers ---------------------------------------------------------------------------

local function findChild(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

--// Shines ------------------------------------------------------------------------------

-- Just under all of the target's own children (text, icons, overlays), unless the gui sorts ZIndex globally.
local function getShineZIndex(target: GuiObject): number
	local gui = target:FindFirstAncestorWhichIsA("LayerCollector")
	if gui and gui.ZIndexBehavior == Enum.ZIndexBehavior.Global then
		return target.ZIndex
	end
	local lowest: number? = nil
	for _, child in target:GetChildren() do
		if child:IsA("GuiObject") then
			lowest = math.min(lowest or child.ZIndex, child.ZIndex)
		end
	end
	return if lowest then lowest - 1 else 1
end

-- The first UICorner found on the given instances, in order, else the default.
local function getCorner(default: UDim, ...: Instance): UDim
	for _, instance in { ... } do
		local corner = instance:FindFirstChildOfClass("UICorner")
		if corner then
			return corner.CornerRadius
		end
	end
	return default
end

-- A white frame over the target, cut down to a diagonal band by its gradient; the band crosses it when played.
local function addShine(target: GuiObject, cornerRadius: UDim): Shine
	local frame = Instance.new("Frame")
	frame.Name = "ShineSweep"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Interactable = false
	frame.Visible = false
	frame.ZIndex = getShineZIndex(target)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = cornerRadius
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = SHINE_ROTATION
	gradient.Transparency = SHINE_SEQUENCE
	gradient.Offset = SHINE_START
	gradient.Parent = frame

	local tween = tweenService:Create(gradient, SHINE_TWEEN, { Offset = SHINE_END })
	tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			frame.Visible = false
		end
	end)

	frame.Parent = target
	return { frame = frame, gradient = gradient, tween = tween }
end

local function playShine(shine: Shine)
	shine.tween:Cancel()
	shine.gradient.Offset = SHINE_START
	shine.frame.Visible = true
	shine.tween:Play()
end

local function stopShine(shine: Shine)
	shine.tween:Cancel()
	shine.frame.Visible = false
end

--// Cards ---------------------------------------------------------------------------

--[[
	A card's spinning "Shine" image is handed to ShineRotate with its own starting angle and speed. The day cards are all
	cloned from DayTemplate in the same frame, so without this they would spin in perfect lockstep. Called before parenting,
	since ShineRotate reads the starting angle when the tagged clone arrives.
]]
local function setUpRotatingShine(card: Instance)
	local rotatingShine = findChild(card, "Shine", "ImageLabel") :: ImageLabel?
	if not rotatingShine then
		return
	end
	local studioSpeed = rotatingShine:GetAttribute(SHINE_SPEED_ATTRIBUTE)
	local baseSpeed = if type(studioSpeed) == "number" then studioSpeed else ROTATING_SHINE_SPEED
	rotatingShine.Rotation = random:NextNumber(0, 360)
	rotatingShine:SetAttribute(SHINE_SPEED_ATTRIBUTE, baseSpeed * random:NextNumber(1 - SPIN_JITTER, 1 + SPIN_JITTER))
	rotatingShine:AddTag(ROTATING_SHINE_TAG)
end

-- The wait until a card's next shine, a little different each time so the cards never fall into step.
local function getCardShineWait(): number
	return CARD_SHINE_INTERVAL * (1 + random:NextNumber(-SHINE_JITTER, SHINE_JITTER))
end

local function addCard(frame: Instance, day: number)
	if not frame:IsA("GuiObject") then
		return
	end

	local art = findChild(frame, CARD_ART_NAME, "GuiObject") :: GuiObject?
	local shineTarget = art or frame
	local shineCorner = getCorner(CARD_SHINE_CORNER, shineTarget, frame)

	local todayBadge = findChild(frame, "TodayBadge", "GuiObject") :: GuiObject?
	local todayScale: UIScale? = nil
	if todayBadge then
		todayScale = todayBadge:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		todayScale.Parent = todayBadge
	end
	cards[day] = {
		icon = findChild(frame, "Icon", "ImageLabel"),
		amount = findChild(frame, "Amount", "TextLabel") or findChild(frame, "AmountText", "TextLabel"),
		claimed = findChild(frame, "Claimed", "GuiObject"),
		todayBadge = todayBadge,
		todayScale = todayScale,
		todayBaseScale = if todayScale then todayScale.Scale else 1,
		pulse = nil,
		shine = addShine(shineTarget, shineCorner),
		shineAt = 0,
	}
end

-- Today's card shows its TodayBadge, gently growing and shrinking; the card art keeps its own border.
local function setToday(card: Card, isToday: boolean)
	if card.todayBadge then
		card.todayBadge.Visible = isToday
	end
	local scale = card.todayScale
	if not scale then
		return
	end

	if isToday and not card.pulse then
		local pulse = tweenService:Create(scale, TODAY_PULSE, { Scale = card.todayBaseScale * TODAY_PULSE_SCALE })
		card.pulse = pulse
		pulse:Play()
	elseif not isToday and card.pulse then
		card.pulse:Cancel()
		card.pulse = nil
		scale.Scale = card.todayBaseScale
	end
end

-- "+N Wool" or "+N Gems", from the reward's kind.
local function formatReward(reward: any): string
	return `+{numberFormatter:Format(reward.amount, 1)} {reward.kind}`
end

local function renderCards()
	local dayCount = #state.rewards
	-- Right after the last day the whole loop shows claimed, until the next one opens.
	local claimedCount = state.streak % dayCount
	if claimedCount == 0 and state.streak > 0 and not state.claimable then
		claimedCount = dayCount
	end

	for day, card in cards do
		local reward = state.rewards[day]
		if reward then
			if card.icon then
				iconUtil.setImage(card.icon, DAY_ICONS[day] or card.icon.Image)
			end
			if card.amount then
				card.amount.Text = formatReward(reward)
			end
		end
		if card.claimed then
			card.claimed.Visible = day <= claimedCount
		end
		setToday(card, state.claimable and day == state.today)
	end
end

--// Rendering --------------------------------------------------------------------------

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%02d:%02d:%02d", whole // 3600, whole % 3600 // 60, whole % 60)
end

local function renderTimer()
	if not state then
		return
	end
	timerLabel.Text = if state.claimable then READY_TEXT else `NEXT REWARD IN {formatTime(deadline - os.clock())}`
end

-- Greyed out through its UIGradient with "COME BACK LATER" while nothing can be claimed; the text stays white either way.
local function renderClaimButton()
	local ready = state ~= nil and state.claimable == true
	claimLabel.Text = if ready then claimText else CLAIM_LATER_TEXT
	if claimGradient and claimGradientColor then
		claimGradient.Color = if ready then claimGradientColor else GREY_GRADIENT
	end
	claimButton.AutoButtonColor = ready
end

local function render()
	if not state then
		return
	end
	streakLabel.Text = `STREAK: {state.streak} {if state.streak == 1 then "DAY" else "DAYS"}`
	renderCards()
	renderTimer()
	renderClaimButton()
end

local function updateHud()
	if alertBadge then
		alertBadge.Visible = state ~= nil and state.claimable == true
	end
end

local function playClaimSound()
	local sound = uiSounds:FindFirstChild(CLAIM_SOUND)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

--// Shine loop --------------------------------------------------------------------------

local claimShine = addShine(claimButton, getCorner(CLAIM_SHINE_CORNER, claimButton))

-- Each unclaimed card shines on its own jittered timer, and Claim on its own while it's ready.
local function stepShines()
	local now = os.clock()
	for _, card in cards do
		if now >= card.shineAt then
			card.shineAt = now + getCardShineWait()
			if not (card.claimed and card.claimed.Visible) then
				playShine(card.shine)
			end
		end
	end

	if now >= nextClaimShineAt then
		nextClaimShineAt = now + CLAIM_SHINE_INTERVAL
		if state and state.claimable then
			playShine(claimShine)
		end
	end
end

local function startShines()
	if shineLoop then
		return
	end
	local firstAt = os.clock() + SHINE_FIRST_DELAY
	for _, card in cards do
		card.shineAt = firstAt + random:NextNumber(0, CARD_SHINE_INTERVAL)
	end
	nextClaimShineAt = firstAt
	shineLoop = runService.Heartbeat:Connect(stepShines)
end

local function stopShines()
	if shineLoop then
		shineLoop:Disconnect()
		shineLoop = nil
	end
	for _, card in cards do
		stopShine(card.shine)
	end
	stopShine(claimShine)
end

--// Auto open ---------------------------------------------------------------------------

local function isUsingCrook(): boolean
	local character = player.Character
	return (character ~= nil and character:FindFirstChild(CROOK_NAME) ~= nil) or player:GetAttribute(CARRY_ATTRIBUTE) ~= nil
end

-- Not over the main, Crook or new-shear tutorial, the crook's hidden UI, or a window the player opened.
local function canAutoOpen(): boolean
	return tutorialGui:GetAttribute(MAIN_DONE_ATTRIBUTE) == true
		and tutorialGui:GetAttribute(CROOK_ACTIVE_ATTRIBUTE) ~= true
		and tutorialGui:GetAttribute(SHEAR_ACTIVE_ATTRIBUTE) ~= true
		and not isUsingCrook()
		and not windowsManager.anyOpen()
end

local function autoOpenOnce(window: windowsManager.Window)
	while not state do
		task.wait(TICK_SECONDS)
	end

	local clearSince: number? = nil
	while state.claimable do
		if not canAutoOpen() then
			clearSince = nil
		elseif not clearSince then
			clearSince = os.clock()
		elseif os.clock() - clearSince >= AUTO_OPEN_SETTLE_SECONDS then
			window.open()
			return
		end
		task.wait(TICK_SECONDS)
	end
end

--// Setup -------------------------------------------------------------------------------

dayTemplate.Visible = false
for day = 1, CLONED_DAYS do
	local leftover = daysFrame:FindFirstChild(`Day{day}`)
	if leftover then
		leftover:Destroy()
	end
end
for day = 1, CLONED_DAYS do
	local clone = dayTemplate:Clone()
	clone.Name = `Day{day}`
	clone.LayoutOrder = day
	local dayLabel = findChild(clone, "DayLabel", "TextLabel") :: TextLabel?
	if dayLabel then
		dayLabel.Text = `DAY {day}`
	end
	clone.Visible = true
	setUpRotatingShine(clone)
	clone.Parent = daysFrame
	addCard(clone, day)
end
setUpRotatingShine(day7Card)
addCard(day7Card, CLONED_DAYS + 1)
for _, card in cards do
	if card.claimed then
		card.claimed.Visible = false
	end
	if card.todayBadge then
		card.todayBadge.Visible = false
	end
end

local window = windowsManager.register("DailyRewards", {
	gui = dailyGui,
	frame = mainFrame,
	openButton = if hudButton and hudButton:IsA("GuiButton") then hudButton else nil,
	onOpen = function()
		render()
		startShines()
		network.fireServer(network.RemoteEvents.RequestDailyRewardState)
	end,
	onClose = stopShines,
})

updateHud()
if alertBadge then
	alertPulse.attach(alertBadge)
end

claimButton.Activated:Connect(function()
	if claiming or not state then
		return
	end
	if not state.claimable then
		alerts.show(REASON_TEXT.NotReady, "error")
		return
	end

	claiming = true
	claimToken += 1
	local token = claimToken
	network.fireServer(network.RemoteEvents.ClaimDailyReward)
	task.delay(CLAIM_TIMEOUT, function()
		if token == claimToken then
			claiming = false
		end
	end)
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.DailyRewardState, function(newState: any)
	if type(newState) ~= "table" or type(newState.rewards) ~= "table" then
		return
	end
	state = newState
	deadline = os.clock() + (tonumber(newState.secondsLeft) or 0)
	nextRefreshAt = 0
	updateHud()
	if window.isOpen() then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.DailyRewardResult, function(success: boolean, reason: string?, reward: any)
	claiming = false
	claimToken += 1
	if success and type(reward) == "table" then
		playClaimSound()
		alerts.show(`{formatReward(reward)}!`, "success")
	else
		alerts.show(REASON_TEXT[reason or ""] or "Couldn't claim the reward", "error")
	end
end)

-- The timer ticks here; once it runs out the server is asked whether the next reward is open.
task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		local now = os.clock()
		if state and not state.claimable and now >= deadline and now >= nextRefreshAt then
			nextRefreshAt = now + REFRESH_RETRY_SECONDS
			network.fireServer(network.RemoteEvents.RequestDailyRewardState)
		end
		if window.isOpen() then
			renderTimer()
		end
	end
end)

network.fireServer(network.RemoteEvents.RequestDailyRewardState)
task.spawn(autoOpenOnce, window)
