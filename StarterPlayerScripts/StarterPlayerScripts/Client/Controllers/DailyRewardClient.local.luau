--[[
	The Daily Rewards window (StarterGui.DailyRewards): fills the day cards with the server's rewards, marks claimed and today's card,
	ticks the timer and claims; it opens itself once on join when a reward is waiting. DailyRewardHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.DailyRewardClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
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
local CLONED_DAYS = 6 -- days 1 to 6 are cloned from the template; day 7 is the big pre-built card
-- All the wool icon for now; each day can be swapped for its own image.
local DAY_ICONS = {
	[1] = iconIds.Wool,
	[2] = iconIds.Wool,
	[3] = iconIds.Wool,
	[4] = iconIds.Wool,
	[5] = iconIds.Wool,
	[6] = iconIds.Wool,
	[7] = iconIds.Wool,
}
local CLAIM_SOUND = "Cash" -- in SoundService.UISounds
local TODAY_OUTLINE_COLOR = Color3.new(1, 1, 1)
local TODAY_OUTLINE_THICKNESS = 4
local TODAY_PULSE = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local TODAY_PULSE_TRANSPARENCY = 0.5
local CLAIM_LATER_TEXT = "COME BACK LATER"
local READY_TEXT = "YOUR REWARD IS READY!"
local GREY_COLOR = Color3.fromRGB(150, 150, 150)
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

type Card = {
	icon: ImageLabel?,
	multiplier: TextLabel?,
	amount: TextLabel?,
	claimed: GuiObject?,
	todayBadge: GuiObject?,
	outline: UIStroke?,
	outlineColor: Color3,
	outlineThickness: number,
	outlineTransparency: number,
	pulse: Tween?,
}

--// State
local state: any = nil -- the last DailyRewardState from the server
local deadline = 0 -- os.clock() the next reward opens, from state.secondsLeft
local nextRefreshAt = 0
local claiming = false
local claimToken = 0
local cards: { [number]: Card } = {}

local claimLabel: any = if claimButton:IsA("TextButton") and claimButton.Text ~= "" then claimButton
	else claimButton:FindFirstChildWhichIsA("TextLabel", true) or claimButton
local claimText = claimLabel.Text
local claimGradient = claimButton:FindFirstChildOfClass("UIGradient")
local claimGradientColor = if claimGradient then claimGradient.Color else nil
local claimColor = claimButton.BackgroundColor3

--// Cards ---------------------------------------------------------------------------

local function findChild(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

local function addCard(frame: Instance)
	local day = frame:GetAttribute("Day")
	if not frame:IsA("GuiObject") or type(day) ~= "number" then
		return
	end

	local outline = findChild(frame, "Outline", "UIStroke") :: UIStroke?
	local card: Card = {
		icon = findChild(frame, "Icon", "ImageLabel"),
		multiplier = findChild(frame, "Multiplier", "TextLabel"),
		amount = findChild(frame, "Amount", "TextLabel"),
		claimed = findChild(frame, "Claimed", "GuiObject"),
		todayBadge = findChild(frame, "TodayBadge", "GuiObject"),
		outline = outline,
		outlineColor = if outline then outline.Color else TODAY_OUTLINE_COLOR,
		outlineThickness = if outline then outline.Thickness else 1,
		outlineTransparency = if outline then outline.Transparency else 0,
		pulse = nil,
	}
	cards[day] = card
end

-- Today's card gets a white, thicker outline that gently fades in and out; the others keep their Studio outline.
local function setToday(card: Card, isToday: boolean)
	if card.todayBadge then
		card.todayBadge.Visible = isToday
	end
	local outline = card.outline
	if not outline then
		return
	end

	if isToday then
		if card.pulse then
			return
		end
		outline.Color = TODAY_OUTLINE_COLOR
		outline.Thickness = TODAY_OUTLINE_THICKNESS
		outline.Transparency = 0
		local pulse = tweenService:Create(outline, TODAY_PULSE, { Transparency = TODAY_PULSE_TRANSPARENCY })
		card.pulse = pulse
		pulse:Play()
	else
		if card.pulse then
			card.pulse:Cancel()
			card.pulse = nil
		end
		outline.Color = card.outlineColor
		outline.Thickness = card.outlineThickness
		outline.Transparency = card.outlineTransparency
	end
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
			if card.multiplier then
				card.multiplier.Text = `+ x{string.format("%g", reward.multiplier)} more`
			end
			if card.amount then
				card.amount.Text = `+{numberFormatter:Format(reward.amount, 1)} Wool`
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

-- Greyed out with "COME BACK LATER" while nothing can be claimed; the text stays white either way.
local function renderClaimButton()
	local ready = state ~= nil and state.claimable == true
	claimLabel.Text = if ready then claimText else CLAIM_LATER_TEXT
	if claimGradient and claimGradientColor then
		claimGradient.Color = if ready then claimGradientColor else GREY_GRADIENT
	else
		claimButton.BackgroundColor3 = if ready then claimColor else GREY_COLOR
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
	clone:SetAttribute("Day", day)
	local dayLabel = findChild(clone, "DayLabel", "TextLabel") :: TextLabel?
	if dayLabel then
		dayLabel.Text = `DAY {day}`
	end
	clone.Visible = true
	clone.Parent = daysFrame
	addCard(clone)
end
addCard(day7Card)
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
		network.fireServer(network.RemoteEvents.RequestDailyRewardState)
	end,
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
		alerts.show(`+{numberFormatter:Format(reward.amount, 1)} Wool!`, "success")
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
