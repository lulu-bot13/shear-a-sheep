--[[
	The Offline Earnings popup (StarterGui.OfflineEarnings), opened on join when wool is waiting, and the "Don't leave!" warning
	(StarterGui.LeaveWarning) shown while the Roblox menu is open. OfflineIncomeHandler decides the amounts.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.OfflineEarningsClient
]]--

--// Services
local guiService = game:GetService("GuiService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local offlineGui = playerGui:WaitForChild("OfflineEarnings") :: ScreenGui
local mainFrame = offlineGui:WaitForChild("Main") :: GuiObject
local rewardCard = mainFrame:WaitForChild("Reward")
local amountLabel = rewardCard:WaitForChild("Amount") :: TextLabel
local awayLabel = mainFrame:WaitForChild("Away") :: TextLabel
local tipLabel = mainFrame:WaitForChild("Tip") :: TextLabel
local claimButton = mainFrame:WaitForChild("Claim") :: GuiButton
local leaveGui = playerGui:WaitForChild("LeaveWarning") :: ScreenGui
local leaveFrame = leaveGui:WaitForChild("Main") :: GuiObject
local leaveSubtitle = leaveFrame:WaitForChild("Subtitle") :: TextLabel
local leaveHint = leaveFrame:WaitForChild("Hint") :: TextLabel
local rateCard = leaveFrame:WaitForChild("Rate")
local rateHeader = rateCard:WaitForChild("Header") :: TextLabel
local rateAmount = rateCard:WaitForChild("Amount") :: TextLabel
local rateBadge = rateCard:WaitForChild("Badge") :: TextLabel
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui

--// Sounds
local uiSounds = soundService:WaitForChild("UISounds")

--// Configs
local CLAIM_SOUND = "Cash" -- in SoundService.UISounds
local COUNT_TWEEN = TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local CLAIM_PULSE = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local CLAIM_PULSE_SCALE = 1.06
local LEAVE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LEAVE_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local LEAVE_WOBBLE = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local LEAVE_WOBBLE_DEGREES = 2
local TICK_SECONDS = 0.25
local AUTO_OPEN_SETTLE_SECONDS = 1 -- a little under DailyRewardClient's, so this one opens first and the daily reward waits for it
local MAIN_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local CROOK_ACTIVE_ATTRIBUTE = "CrookTutorialActive"
local SHEAR_ACTIVE_ATTRIBUTE = "ShearTutorialActive"
local CROOK_NAME = "ShepherdsCrook"
local CARRY_ATTRIBUTE = "CarryingSheep"

--// State
local state: any = nil -- the last OfflineEarningsState from the server
local claimed = false -- the shown amount was already sent off this visit
local autoOpening = false
local countValue: NumberValue? = nil

--// Helpers ---------------------------------------------------------------------------

local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

local function formatShort(value: number): string
	return if value < 1000 then formatWithCommas(value) else tostring(numberFormatter:Format(value, 1) or formatWithCommas(value))
end

-- "2H 14M", "45M", or "3H" on the hour.
local function formatDuration(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor(seconds % 3600 / 60)
	if hours > 0 and minutes > 0 then
		return `{hours}H {minutes}M`
	end
	return if hours > 0 then `{hours}H` else `{math.max(minutes, 1)}M`
end

local function getScale(guiObject: GuiObject): UIScale
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = guiObject
	end
	return scale :: UIScale
end

local function playSound(name: string)
	local sound = uiSounds:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

--// Offline Earnings window ---------------------------------------------------------------

local function claim()
	if claimed or not state or state.wool <= 0 then
		return
	end
	claimed = true
	network.fireServer(network.RemoteEvents.ClaimOfflineEarnings)
end

local function render()
	if not state then
		return
	end
	local maxHours = math.floor(state.maxSeconds / 3600 + 0.5)
	tipLabel.Text = `Podium sheep earn up to {maxHours} hours of wool while you're offline!`
	if state.awaySeconds <= 0 then
		awayLabel.Text = "SAVED FROM YOUR LAST VISIT"
	elseif state.awaySeconds >= state.maxSeconds then
		awayLabel.Text = `AWAY FOR {formatDuration(state.awaySeconds)} (MAX)`
	else
		awayLabel.Text = `AWAY FOR {formatDuration(state.awaySeconds)}`
	end
end

-- The amount counts up from 0 each time the window opens.
local function countUp()
	if countValue then
		countValue:Destroy()
	end
	local target = if state then state.wool else 0
	local value = Instance.new("NumberValue")
	countValue = value
	value.Changed:Connect(function(shown: number)
		amountLabel.Text = `+{formatShort(shown)}`
	end)
	amountLabel.Text = "+0"
	tweenService:Create(value, COUNT_TWEEN, { Value = target }):Play()
end

local window = windowsManager.register("OfflineEarnings", {
	gui = offlineGui,
	frame = mainFrame,
	onOpen = function()
		render()
		countUp()
	end,
	onClose = claim, -- closing with X still pays out, so nothing earned is ever lost
})

claimButton.Activated:Connect(function()
	if not claimed then
		playSound(CLAIM_SOUND)
	end
	claim()
	window.close()
end)

local claimScale = getScale(claimButton)
local claimBaseScale = claimScale.Scale
tweenService:Create(claimScale, CLAIM_PULSE, { Scale = claimBaseScale * CLAIM_PULSE_SCALE }):Play()

--// Auto open -----------------------------------------------------------------------------

local function isUsingCrook(): boolean
	local character = player.Character
	return (character ~= nil and character:FindFirstChild(CROOK_NAME) ~= nil) or player:GetAttribute(CARRY_ATTRIBUTE) ~= nil
end

-- Not over a tutorial, while carrying a sheep, or over a window the player opened.
local function canAutoOpen(): boolean
	return tutorialGui:GetAttribute(MAIN_DONE_ATTRIBUTE) == true
		and tutorialGui:GetAttribute(CROOK_ACTIVE_ATTRIBUTE) ~= true
		and tutorialGui:GetAttribute(SHEAR_ACTIVE_ATTRIBUTE) ~= true
		and not isUsingCrook()
		and not windowsManager.anyOpen()
end

local function autoOpen()
	if autoOpening then
		return
	end
	autoOpening = true

	local clearSince: number? = nil
	while state and state.wool > 0 and not claimed and not window.isOpen() do
		if not canAutoOpen() then
			clearSince = nil
		elseif not clearSince then
			clearSince = os.clock()
		elseif os.clock() - clearSince >= AUTO_OPEN_SETTLE_SECONDS then
			window.open()
			break
		end
		task.wait(TICK_SECONDS)
	end
	autoOpening = false
end

--// Leave warning -------------------------------------------------------------------------

local leaveScale = getScale(leaveFrame)
local leaveBaseScale = leaveScale.Scale
local leaveBaseRotation = leaveFrame.Rotation
local leaveTweens: { Tween } = {}
local leaveToken = 0

local function renderLeave()
	local perMinute = if state then state.perMinute else 0
	local maxHours = if state then math.floor(state.maxSeconds / 3600 + 0.5) else 3
	rateBadge.Text = `UP TO {maxHours} HOURS`
	if perMinute > 0 then
		leaveSubtitle.Text = "Join back to collect your offline earnings!"
		rateHeader.Text = "YOUR SHEEP EARN"
		rateAmount.Text = `+{formatShort(perMinute)} WOOL/MIN`
		leaveHint.Text = "while you're offline!"
	else
		leaveSubtitle.Text = "Your sheep can earn wool while you're away!"
		rateHeader.Text = "PODIUM SHEEP EARN"
		rateAmount.Text = "WOOL OFFLINE"
		leaveHint.Text = "Put sheep on your podiums first!"
	end
end

-- Cancels whatever the warning was doing and plays the new tween (the pop, wobble or shrink).
local function playLeave(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	for _, tween in leaveTweens do
		tween:Cancel()
	end
	local tween = tweenService:Create(instance, info, goal)
	leaveTweens = { tween }
	tween:Play()
	return tween
end

-- Pops in, then wobbles side to side until the menu closes.
local function showLeaveWarning()
	leaveToken += 1
	local token = leaveToken
	renderLeave()
	if not leaveGui.Enabled then
		leaveScale.Scale = 0
		leaveFrame.Rotation = leaveBaseRotation - LEAVE_WOBBLE_DEGREES
	end
	leaveGui.Enabled = true
	playLeave(leaveScale, LEAVE_IN, { Scale = leaveBaseScale }).Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and token == leaveToken then
			table.insert(leaveTweens, tweenService:Create(leaveFrame, LEAVE_WOBBLE, { Rotation = leaveBaseRotation + LEAVE_WOBBLE_DEGREES }))
			leaveTweens[#leaveTweens]:Play()
		end
	end)
end

local function hideLeaveWarning()
	leaveToken += 1
	local token = leaveToken
	playLeave(leaveScale, LEAVE_OUT, { Scale = 0 }).Completed:Once(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and token == leaveToken then
			leaveGui.Enabled = false
			leaveScale.Scale = leaveBaseScale
			leaveFrame.Rotation = leaveBaseRotation
		end
	end)
end

--// Setup -------------------------------------------------------------------------------

leaveGui.Enabled = false
guiService.MenuOpened:Connect(showLeaveWarning)
guiService.MenuClosed:Connect(hideLeaveWarning)

network.connectEvent(network.RemoteEvents.OfflineEarningsState, function(newState: any)
	state = newState
	if state.wool > 0 and not claimed then
		task.spawn(autoOpen)
	elseif state.wool <= 0 then
		claimed = false -- ready for anything earned later this visit (e.g. a Studio test)
	end
	if window.isOpen() then
		render()
	end
	if leaveGui.Enabled then
		renderLeave()
	end
end)

network.fireServer(network.RemoteEvents.RequestOfflineEarnings)
