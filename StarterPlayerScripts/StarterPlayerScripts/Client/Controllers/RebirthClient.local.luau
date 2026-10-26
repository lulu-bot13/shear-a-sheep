--[[
	The rebirth screen (StarterGui.RebirthScreen): uses the UI as built in Studio and fills in the cost and the before -> after luck multiplier.
	Only displays what the server sends; RebirthHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local alertBadge = openButton:FindFirstChild("Alert", true) :: GuiObject? -- optional badge on the HUD button
local hudProgress = openButton:WaitForChild("Progress") :: TextLabel

local rebirthGui = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local mainFrame = rebirthGui:WaitForChild("Main") :: Frame
local rebirthButton = mainFrame:WaitForChild("Rebirth") :: GuiButton
local rebirthButtonLabel = rebirthButton:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel -- the button's own Text stays ""
local rebirthButtonGradient = rebirthButton:FindFirstChildOfClass("UIGradient")
local amountButton = mainFrame:WaitForChild("Amount") :: GuiButton -- the 1X / MAX switch
local amountKnob = amountButton:WaitForChild("Knob") :: GuiObject
local amountLabel = amountButton:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel? -- the button's own Text stays ""
local rebirthCount = mainFrame:WaitForChild("RebirthCount") :: TextLabel
local prestigeCount = mainFrame:WaitForChild("Prestiges") :: TextLabel

local woolPrice = mainFrame:WaitForChild("WoolPrice") :: TextLabel

local requirementTip = mainFrame:WaitForChild("RequirementTip") :: GuiObject
local requirementText = requirementTip:WaitForChild("RequirementText") :: TextLabel
local keepNote = requirementTip:WaitForChild("KeepNote") :: TextLabel

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local alertPulse = require(script.Parent.Parent.Modules.AlertPulse)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local luckRain = require(script.Parent.Parent.Modules.LuckRain)
local rebirthVFX = require(script.Parent.Parent.Modules.RebirthVFX)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[RebirthClient] {message}`)
	end
end

debugLog("script started")

-- The before -> after labels built in Studio.
local rewardsFrame = mainFrame:WaitForChild("RewardsFrame") :: Frame
local rewardBefore = rewardsFrame:WaitForChild("BeforeAmount") :: TextLabel
local rewardAfter = rewardsFrame:WaitForChild("AfterAmount") :: TextLabel

--// Sounds
local rebirthedSound = soundService:WaitForChild("UISounds"):FindFirstChild("Rebirthed") :: Sound?

debugLog(`found the UI (Rebirth button is a {rebirthButton.ClassName}, open button is a {openButton.ClassName})`)

--// Configs
local REWARD_BEFORE_COLOR = Color3.fromRGB(170, 170, 170)
local REWARD_AFTER_COLOR = Color3.fromRGB(170, 235, 170)
local KEEP_NOTE_TEXT = "Only costs wool! Your upgrades, sheep and Luck are kept."
-- What the RequirementTip labels say once the player can Prestige.
local PRESTIGE_TIP_TEXT = {
	RequirementText = "REBIRTHS MAXED, PRESTIGE TO GO FURTHER!",
	KeepNote = `<font color="#FF5A5A">RESETS ALL STATS (index and shear count stays the same)</font>`,
}
local GREY_GRADIENT = ColorSequence.new(Color3.fromRGB(175, 175, 175), Color3.fromRGB(115, 115, 115))
local AMOUNTS = { 1, "max" } -- what the Amount switch flips between; "max" is as many as the player can afford
local KNOB_MAX_POSITION = UDim2.fromScale(0.492, 0.5)
local KNOB_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STATE_REQUEST_SECONDS = 0.55 -- just over RebirthServer's cooldown, which drops state requests sent sooner

-- The HUD button wiggles every few seconds while a rebirth is ready.
local ALERT_SHAKE_SECONDS = 3
local ALERT_SHAKE_ANGLES = { -10, 10, -8, 8, -4, 4, 0 }
local CLICK_SHAKE_ANGLES = { -3, 3, -2, 2, 0 }

local REASON_TEXT = {
	NotReady = "Not enough wool to rebirth",
	MaxRebirths = "Rebirths are MAXED",
	Busy = "Already rebirthing",
}

--// State
local state: any = nil -- the last RebirthState from the server
local prestigeState: any = nil -- the last PrestigeState; once it can Prestige, the Rebirth button prestiges instead
local wasReady = false -- so the "Rebirth Available" alert shows once each time the bar reaches 100%
local normalGradient = if rebirthButtonGradient then rebirthButtonGradient.Color else nil -- the purple, restored once affordable
local amountIndex = 1 -- into AMOUNTS; back to 1X every time the screen opens
local nextStateRequest = 0
local stateRequestQueued = false
local tipTexts: { [TextLabel]: string } = {} -- each RequirementTip label's own text, restored while the player can't Prestige
local knobOnePosition = amountKnob.Position -- the 1X side, as built in Studio

--// Helpers -------------------------------------------------------------------------

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- "x1.08 Luck"
local function formatRewards(luckFactor: number): string
	return `{formatMultiplier(luckFactor)} Luck`
end

local function canPrestige(): boolean
	return prestigeState ~= nil and prestigeState.canPrestige == true
end

local function getSelectedAmount(): number | string
	return AMOUNTS[amountIndex]
end

-- Asks for the state for the selected amount; one sent too soon after the last goes out once the cooldown ends.
local function requestState()
	if stateRequestQueued then
		return
	end
	local delaySeconds = nextStateRequest - os.clock()
	if delaySeconds > 0 then
		stateRequestQueued = true
		task.delay(delaySeconds, function()
			stateRequestQueued = false
			requestState()
		end)
		return
	end
	nextStateRequest = os.clock() + STATE_REQUEST_SECONDS
	network.fireServer(network.RemoteEvents.RequestRebirthState, getSelectedAmount())
end

local function setAmountIndex(index: number)
	amountIndex = index
	local amount = getSelectedAmount()
	if amountLabel then
		amountLabel.Text = if amount == "max" then "MAX" else `{amount}X`
	end
	amountButton:SetAttribute("Amount", amount)
	local knobPosition = if amount == "max" then KNOB_MAX_POSITION else knobOnePosition
	tweenService:Create(amountKnob, KNOB_TWEEN, { Position = knobPosition }):Play()
end

local function toggleAmount()
	setAmountIndex(amountIndex % #AMOUNTS + 1)
	requestState()
end

-- Wiggles around the button's current angle, so it ends where it started.
local function shake(button: GuiObject, angles: { number })
	task.spawn(function()
		local baseRotation = button.Rotation
		for _, angle in angles do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = baseRotation + angle }):Play()
			task.wait(0.04)
		end
	end)
end

--// Rendering --------------------------------------------------------------------------

-- How far the player's wool is towards the next rebirth, 0 to 1.
local function getProgress(): number
	if state.maxed or state.woolCost <= 0 then
		return 1
	end
	return math.clamp(state.wool / state.woolCost, 0, 1)
end

local function renderRequirementTip(prestigeReady: boolean)
	for label, originalText in tipTexts do
		label.Text = if prestigeReady then PRESTIGE_TIP_TEXT[label.Name] else originalText
	end
end

local function render()
	if not state then
		return
	end

	rebirthCount.Text = `You have {state.rebirths} {if state.rebirths == 1 then "rebirth" else "rebirths"}`
	prestigeCount.Text = `You have {state.prestiges} prestige`
	rewardBefore.Text = formatRewards(state.luckFactor)
	rewardAfter.Text = if state.maxed then "MAX" else formatRewards(state.amountLuckFactor)

	woolPrice.Text = if state.maxed then "MAX" else numberFormatter:Format(state.amountCost, 1)
	local prestigeReady = canPrestige()
	renderRequirementTip(prestigeReady)

	local affordable = state.amountCanRebirth and not state.maxed
	rebirthButtonLabel.Text = if prestigeReady then "PRESTIGE"
		elseif state.maxed then "MAX"
		elseif affordable then "CONFIRM"
		else "Not Enough"
	if rebirthButtonGradient and normalGradient then
		rebirthButtonGradient.Color = if affordable or prestigeReady then normalGradient else GREY_GRADIENT
	end
end

-- The HUD button's "Alert" badge shows while a rebirth is ready, and Progress shows the wool percentage.
local function updateHud()
	if alertBadge then
		alertBadge.Visible = state ~= nil and state.canRebirth == true
	end
	if state then
		-- Rounded down, so 100% only shows once the rebirth is actually affordable.
		hudProgress.Text = if state.maxed then "MAX" else `{math.floor(getProgress() * 100)}%`
	end
end

--// Setup -------------------------------------------------------------------------------

local window = windowsManager.register("Rebirth", {
	gui = rebirthGui,
	frame = mainFrame,
	openButton = openButton,
	onOpen = function()
		setAmountIndex(1)
		render()
		requestState()
	end,
})

setAmountIndex(1)

rewardBefore.TextColor3 = REWARD_BEFORE_COLOR
rewardAfter.TextColor3 = REWARD_AFTER_COLOR

-- The Studio note still warns that rebirths reset progress.
for _, descendant in mainFrame:GetDescendants() do
	if descendant:IsA("TextLabel") and descendant.Text:lower():find("reset") then
		descendant.Text = KEEP_NOTE_TEXT
	end
end
for _, label in { requirementText, keepNote } do
	tipTexts[label] = label.Text
end
keepNote.RichText = true -- its Prestige text is coloured with a font tag
hudProgress.Text = "0%"
updateHud()
if alertBadge then
	alertPulse.attach(alertBadge)
end

task.spawn(function()
	while true do
		task.wait(ALERT_SHAKE_SECONDS)
		if state and state.canRebirth and not window.isOpen() then
			shake(openButton, ALERT_SHAKE_ANGLES)
		end
	end
end)

amountButton.MouseButton1Click:Connect(toggleAmount)
-- The Knob sits on top of the switch, so it would swallow clicks if it's a button too.
if amountKnob:IsA("GuiButton") then
	amountKnob.MouseButton1Click:Connect(toggleAmount)
end

rebirthButton.MouseButton1Click:Connect(function()
	if canPrestige() then
		debugLog("clicked Prestige, sending RequestPrestige")
		network.fireServer(network.RemoteEvents.RequestPrestige)
	elseif not state or state.amount ~= getSelectedAmount() then
		debugLog("clicked Rebirth, but no state for the selected amount yet; asking for it")
		requestState()
	elseif state.amountCanRebirth and not state.maxed then
		debugLog(`clicked Rebirth, sending RequestRebirth x{getSelectedAmount()}`)
		network.fireServer(network.RemoteEvents.RequestRebirth, getSelectedAmount())
	else
		debugLog(`clicked Rebirth, not ready: wool {state.wool}/{state.amountCost}, amountCanRebirth {state.amountCanRebirth}, maxed {state.maxed}`)
		alerts.show(if state.maxed then REASON_TEXT.MaxRebirths else REASON_TEXT.NotReady, "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

debugLog("button clicks connected, waiting for the network")
network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthState, function(newState: any)
	debugLog(`got state: rebirths {newState.rebirths}, wool {newState.wool}/{newState.woolCost}, canRebirth {newState.canRebirth}`)
	state = newState
	local ready = newState.canRebirth == true and not newState.maxed
	if ready and not wasReady then
		announcements.show("RebirthAlert", "Rebirth Available")
	end
	wasReady = ready
	updateHud()
	if window.isOpen() then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number?, count: number?)
	debugLog(`rebirth result: success {success}, reason {reason}, count {count}`)
	if success then
		local times = if count and count > 1 then ` x{count}` else ""
		announcements.show("Rebirthed", `Rebirthed{times} ({rebirths or "?"})`)
		if rebirthedSound then
			rebirthedSound:Play()
		end
		luckRain.play(rebirthGui)
		if player.Character then
			rebirthVFX.play(player.Character)
		end
	else
		alerts.show(REASON_TEXT[reason or ""] or "Can't rebirth", "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

network.connectEvent(network.RemoteEvents.PrestigeState, function(newState: any)
	prestigeState = newState
	if window.isOpen() then
		render()
	end
end)

requestState()
network.fireServer(network.RemoteEvents.RequestPrestigeState)
