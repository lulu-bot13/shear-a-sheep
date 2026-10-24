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
local READY_ALERT_Y = 0.35 -- screen height (scale) of the "Rebirth available" alert

local REASON_TEXT = {
	NotReady = "Not enough wool to rebirth",
	MaxRebirths = "Rebirths are MAXED",
	Busy = "Already rebirthing",
}

-- Luck icons falling down the screen after a rebirth. Spawning + the slowest fall add up to EFFECT_SECONDS.
local LUCK_ICON_IMAGE = "rbxassetid://86611651520562" -- "rbxassetid://..."; empty uses the first icon in the rebirth screen's RewardsFrame
local EFFECT_SECONDS = 3.5
local FALL_ICON_COUNT = 40
local FALL_SPAWN_SECONDS = 1.5
local FALL_MIN_SECONDS = 1.4
local FALL_MAX_SECONDS = EFFECT_SECONDS - FALL_SPAWN_SECONDS
local FALL_MIN_SIZE = 36
local FALL_MAX_SIZE = 72

--// State
local state: any = nil -- the last RebirthState from the server
local wasReady = false -- so the "Rebirth available" alert shows once each time the bar reaches 100%
local rebirthButtonText = if rebirthButton:IsA("TextButton") then rebirthButton.Text else ""

local effectGui = Instance.new("ScreenGui")
effectGui.Name = "RebirthEffectGui"
effectGui.ResetOnSpawn = false
effectGui.IgnoreGuiInset = true
effectGui.DisplayOrder = rebirthGui.DisplayOrder + 1
effectGui.Parent = playerGui

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

--// Rebirth effect ---------------------------------------------------------------------

local function getLuckIconImage(): string
	if LUCK_ICON_IMAGE ~= "" then
		return LUCK_ICON_IMAGE
	end
	local rowIcon = rewardsFrame:FindFirstChildWhichIsA("ImageLabel")
	return if rowIcon then rowIcon.Image else ""
end

local function makeLuckIcon(image: string, size: number): GuiObject
	local icon: GuiObject
	if image ~= "" then
		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Image = image
		icon = imageLabel
	else
		local clover = Instance.new("TextLabel")
		clover.Text = "🍀"
		clover.TextScaled = true
		icon = clover
	end

	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromOffset(size, size)
	icon.Parent = effectGui
	return icon
end

-- Luck icons rain down from above the screen at random spots, sizes and spins.
local function playLuckRain()
	local image = getLuckIconImage()

	for _ = 1, FALL_ICON_COUNT do
		task.delay(math.random() * FALL_SPAWN_SECONDS, function()
			local icon = makeLuckIcon(image, math.random(FALL_MIN_SIZE, FALL_MAX_SIZE))
			local x = math.random()
			local drift = (math.random() - 0.5) * 0.12
			local fallSeconds = FALL_MIN_SECONDS + math.random() * (FALL_MAX_SECONDS - FALL_MIN_SECONDS)

			icon.Position = UDim2.fromScale(x, -0.1)
			icon.Rotation = math.random(-30, 30)

			local fallInfo = TweenInfo.new(fallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local fall = tweenService:Create(icon, fallInfo, {
				Position = UDim2.fromScale(x + drift, 1.1),
				Rotation = icon.Rotation + math.random(-180, 180),
			})
			fall.Completed:Once(function()
				icon:Destroy()
			end)
			fall:Play()
		end)
	end
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

	rebirthCount.Text = `Rebirths: {state.rebirths}`
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
		alerts.showCenter("Rebirth available", nil, READY_ALERT_Y)
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
		alerts.showCenter("REBIRTHED", `Rebirth {rebirths or "?"}`)
		if rebirthedSound then
			rebirthedSound:Play()
		end
		playLuckRain()
	else
		alerts.show(REASON_TEXT[reason or ""] or "Can't rebirth", "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

network.fireServer(network.RemoteEvents.RequestRebirthState)
