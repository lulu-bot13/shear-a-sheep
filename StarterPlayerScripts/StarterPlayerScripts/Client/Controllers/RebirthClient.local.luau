--[[
	The rebirth screen (StarterGui.RebirthScreen): uses the UI as built in Studio and only fills in the before -> after Luck.
	Only displays what the server sends; RebirthHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local alertPulse = require(script.Parent.Parent.Modules.AlertPulse)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local luckRain = require(script.Parent.Parent.Modules.LuckRain)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

local DEBUG = false

local function debugLog(message: string)
	if DEBUG then
		print(`[RebirthClient] {message}`)
	end
end

debugLog("script started")

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
local rebirthCount = mainFrame:WaitForChild("RebirthCount") :: TextLabel

local requirementBar = mainFrame:WaitForChild("RequirementBar") :: Frame
local requirementProgress = requirementBar:WaitForChild("Progress") :: Frame
local woolCount = requirementBar:WaitForChild("WoolCount") :: TextLabel

-- The before -> after labels built in Studio.
local rewardsFrame = mainFrame:WaitForChild("RewardsFrame") :: Frame
local luckBefore = rewardsFrame:WaitForChild("BeforeAmount") :: TextLabel
local luckAfter = rewardsFrame:WaitForChild("AfterAmount") :: TextLabel

--// Sounds
local rebirthedSound = soundService:WaitForChild("UISounds"):FindFirstChild("Rebirthed") :: Sound?

debugLog(`found the UI (Rebirth button is a {rebirthButton.ClassName}, open button is a {openButton.ClassName})`)

--// Configs
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LUCK_BEFORE_COLOR = Color3.fromRGB(170, 170, 170)
local LUCK_AFTER_COLOR = Color3.fromRGB(170, 235, 170)

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
local wasReady = false -- so the "Rebirth Available" alert shows once each time the bar reaches 100%
local rebirthButtonText = if rebirthButton:IsA("TextButton") then rebirthButton.Text else ""

--// Helpers -------------------------------------------------------------------------

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- 248239 -> "248,239"
local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

-- "x3.7 (248,239)": the luck multiplier, then the Luck it comes from.
local function formatLuck(luck: number, factor: number): string
	return `{formatMultiplier(factor)} ({formatWithCommas(luck)})`
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

local function render()
	if not state then
		return
	end

	rebirthCount.Text = tostring(state.rebirths)
	luckBefore.Text = formatLuck(state.luck, state.luckFactor)
	luckAfter.Text = formatLuck(state.nextLuck, state.nextLuckFactor)

	-- Requirement bar: fills with wool towards the next rebirth's cost.
	local ratio = getProgress()
	local size = requirementProgress.Size
	tweenService:Create(requirementProgress, BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()
	woolCount.Text = if state.maxed
		then "MAX"
		else `{numberFormatter:Format(math.floor(state.wool), 1)}/{numberFormatter:Format(state.woolCost, 1)}`

	-- The wool needed is already on the requirement bar, so the button keeps its Studio text until it's ready.
	if rebirthButton:IsA("TextButton") then
		rebirthButton.Text = if state.maxed
			then "Max Rebirths"
			elseif state.canRebirth then "Rebirth!"
			else rebirthButtonText
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
		render()
		network.fireServer(network.RemoteEvents.RequestRebirthState)
	end,
})

luckBefore.TextColor3 = LUCK_BEFORE_COLOR
luckAfter.TextColor3 = LUCK_AFTER_COLOR
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

rebirthButton.MouseButton1Click:Connect(function()
	if not state then
		debugLog("clicked Rebirth, but no state from the server yet; asking for it")
		network.fireServer(network.RemoteEvents.RequestRebirthState)
	elseif state.canRebirth and not state.maxed then
		debugLog("clicked Rebirth, sending RequestRebirth")
		network.fireServer(network.RemoteEvents.RequestRebirth)
	else
		debugLog(`clicked Rebirth, not ready: wool {state.wool}/{state.woolCost}, canRebirth {state.canRebirth}, maxed {state.maxed}`)
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

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number?)
	debugLog(`rebirth result: success {success}, reason {reason}`)
	if success then
		announcements.show("Rebirthed", `🎊 REBIRTH {rebirths or "?"} 🎊`)
		if rebirthedSound then
			rebirthedSound:Play()
		end
		luckRain.play(rebirthGui)
	else
		alerts.show(REASON_TEXT[reason or ""] or "Can't rebirth", "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

network.fireServer(network.RemoteEvents.RequestRebirthState)
