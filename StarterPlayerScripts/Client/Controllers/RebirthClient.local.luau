--[[
	The rebirth screen. Only DISPLAYS what the server sends (RebirthHandler decides everything).

	Flow:
		openButton pressed        -> the rebirth screen toggles open and asks the server for fresh state
		RebirthState (server)     -> the labels, requirement rows and rebirth button are redrawn
		rebirthButton pressed     -> RequestRebirth is sent (only when the state says canRebirth)
		RebirthResult (server)    -> success / failure message on the rebirth button

	The UI is built by hand in Studio. Fill in the UI REFERENCES block below by pointing each
	variable at your instance. Nothing is created or searched for by this script. The ones marked
	REQUIRED must be filled in; the rest can stay nil and are simply skipped.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// UI REFERENCES (fill these in) -------------------------------------------------------
-- Example: local rebirthGui = playerGui:WaitForChild("Rebirth") :: ScreenGui

local rebirthGui = nil :: ScreenGui? -- REQUIRED: the rebirth screen that opens and closes
local openButton = nil :: GuiButton? -- REQUIRED: the HUD button that opens / closes the rebirth screen
local rebirthButton = nil :: TextButton? -- REQUIRED: the button inside the screen that performs the rebirth
local closeButton = nil :: GuiButton? -- the X on the rebirth screen

local rebirthsLabel = nil :: TextLabel? -- "Rebirths: 3" (or "Rebirths: 20 / 20")
local multiplierLabel = nil :: TextLabel? -- current wool multiplier, "x2.5"
local nextMultiplierLabel = nil :: TextLabel? -- multiplier after the next rebirth, "x3"

-- One label per requirement row, shown as "Wool: 120 / 500". The ids come from RebirthHandler.getState.
local moneyRequirementLabel = nil :: TextLabel?
local woolRequirementLabel = nil :: TextLabel?
local pensRequirementLabel = nil :: TextLabel?
local workersRequirementLabel = nil :: TextLabel?

--// Configs
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local MESSAGE_SECONDS = 1.5
local COLOR_MET = Color3.fromRGB(90, 220, 110)
local COLOR_UNMET = Color3.fromRGB(235, 90, 90)
local BUTTON_COLORS = {
	Ready = Color3.fromRGB(70, 200, 100),
	NotReady = Color3.fromRGB(120, 120, 120),
	Maxed = Color3.fromRGB(230, 190, 60),
}

local REASON_TEXT = {
	Busy = "Please wait...",
	Shearing = "Finish shearing first",
	MaxRebirths = "Max rebirths reached",
	NotReady = "Requirements not met",
}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

--// State
local state: any = nil -- the last RebirthState from the server
local messageToken = 0
local openScale: UIScale? = nil

--// Helpers -------------------------------------------------------------------------

local function formatNumber(value: number): string
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end

	if index == 1 then
		return tostring(math.floor(value))
	end

	local text = string.format("%.2f", value):gsub("%.?0+$", "")
	return text .. SUFFIXES[index]
end

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function setRequirement(label: TextLabel?, name: string, current: number, required: number, met: boolean)
	if not label then
		return
	end

	label.Text = `{name}: {formatNumber(current)} / {formatNumber(required)}`
	label.TextColor3 = if met then COLOR_MET else COLOR_UNMET
	label:SetAttribute("Met", met)
end

--// Rendering --------------------------------------------------------------------------

local function renderButton()
	local button = rebirthButton
	if not button then
		return
	end

	if not state then
		button.Text = "Rebirth"
		button.BackgroundColor3 = BUTTON_COLORS.NotReady
		return
	end

	if state.maxed then
		button.Text = "Max Rebirths"
		button.BackgroundColor3 = BUTTON_COLORS.Maxed
	elseif state.canRebirth then
		button.Text = "Rebirth!"
		button.BackgroundColor3 = BUTTON_COLORS.Ready
	else
		button.Text = "Rebirth"
		button.BackgroundColor3 = BUTTON_COLORS.NotReady
	end

	button:SetAttribute("CanRebirth", state.canRebirth)
end

local function render()
	if not state then
		return
	end

	if rebirthsLabel then
		rebirthsLabel.Text = `Rebirths: {state.rebirths} / {state.maxRebirths}`
	end
	if multiplierLabel then
		multiplierLabel.Text = formatMultiplier(state.multiplier)
	end
	if nextMultiplierLabel then
		nextMultiplierLabel.Text = if state.maxed then "MAX" else formatMultiplier(state.nextMultiplier)
	end

	-- Maxed out: nothing left to ask for, so the rows are cleared.
	local rows = {
		Money = moneyRequirementLabel,
		Wool = woolRequirementLabel,
		Pens = pensRequirementLabel,
		Workers = workersRequirementLabel,
	}
	if state.maxed then
		for _, label in rows do
			label.Text = "-"
			label.TextColor3 = COLOR_MET
		end
	else
		setRequirement(moneyRequirementLabel, "Money", state.money, state.moneyCost, state.money >= state.moneyCost)
		for _, requirement in state.requirements do
			setRequirement(rows[requirement.id], requirement.label, requirement.current, requirement.required, requirement.met)
		end
	end

	messageToken += 1 -- a pending message must not overwrite the fresh text
	renderButton()
end

-- Shows a short message on the rebirth button, then goes back to its normal text.
local function flashMessage(text: string)
	local button = rebirthButton
	if not button then
		return
	end

	messageToken += 1
	local token = messageToken
	button.Text = text
	shake(button)

	task.delay(MESSAGE_SECONDS, function()
		if token == messageToken then
			renderButton()
		end
	end)
end

--// Open / close -----------------------------------------------------------------------

local function closeScreen()
	if rebirthGui and rebirthGui.Enabled then
		rebirthGui.Enabled = false
	end
end

local function openScreen()
	local gui = rebirthGui
	if not gui or gui.Enabled then
		return
	end

	render()
	network.fireServer(network.RemoteEvents.RequestRebirthState)

	if openScale then
		openScale.Scale = 0.85
		tweenService:Create(openScale, OPEN_TWEEN, { Scale = 1 }):Play()
	end
	gui.Enabled = true
end

local function toggleScreen()
	if rebirthGui and rebirthGui.Enabled then
		closeScreen()
	else
		openScreen()
	end
end

--// Setup -------------------------------------------------------------------------------

local gui = rebirthGui
local openUiButton = openButton
local confirmButton = rebirthButton
if not gui or not openUiButton or not confirmButton then
	warn("RebirthClient: fill in rebirthGui, openButton and rebirthButton in the UI REFERENCES block. Rebirth UI is off.")
	return
end

gui.Enabled = false

-- The popup scales in on the first child frame of the screen (or the screen's own first GuiObject).
local scaleTarget = gui:FindFirstChildWhichIsA("GuiObject")
if scaleTarget then
	openScale = scaleTarget:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	openScale.Parent = scaleTarget
end

openUiButton.MouseButton1Click:Connect(toggleScreen)

if closeButton then
	closeButton.MouseButton1Click:Connect(closeScreen)
end

confirmButton.MouseButton1Click:Connect(function()
	if not state then
		network.fireServer(network.RemoteEvents.RequestRebirthState)
		return
	end

	if state.maxed then
		flashMessage(REASON_TEXT.MaxRebirths)
	elseif state.canRebirth then
		network.fireServer(network.RemoteEvents.RequestRebirth)
	else
		flashMessage(REASON_TEXT.NotReady)
	end
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthState, function(newState: any)
	state = newState
	render()
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number)
	if success then
		flashMessage(`Rebirth {rebirths}!`)
	else
		flashMessage(REASON_TEXT[reason or ""] or "Can't rebirth")
	end
end)

-- Shearing started: the screen must not stay up over the mini-game.
network.connectEvent(network.RemoteEvents.ActivateShearing, closeScreen)

network.fireServer(network.RemoteEvents.RequestRebirthState)
