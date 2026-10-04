--[[
	The rebirth screen (StarterGui.RebirthScreen). Only DISPLAYS what the server sends
	(RebirthHandler decides everything).

	Hierarchy this script expects:
		RebirthScreen (ScreenGui)
		└─ Main
		   ├─ MoneyBar          Progress (width = money / cost), MoneyText ("$1,200/$50,000")
		   ├─ RequirementTip    RequirementText (a tip, or the result of the last rebirth try)
		   ├─ Requirements      UIListLayout + Template (hidden, cloned once per requirement)
		   │  ├─ Template       generic row: Completed (+ TextLabel), ImageLabel, TextLabel ("Wool: 1,200/20,000")
	   │  └─ WoolTemplate / PensTemplate / WorkersTemplate   optional, same layout, used for that requirement
		   ├─ Exit              closes the screen
		   └─ Rebirth           sends the rebirth request
		The HUD button that opens the screen is PlayerGui.Main.Buttons.Rebirth.

	Flow:
		HUD Rebirth button        -> the screen toggles open and asks the server for fresh state
		RebirthState (server)     -> money bar, requirement rows and the Rebirth button are redrawn
		Rebirth button            -> RequestRebirth is sent (only when the state says canRebirth)
		RebirthResult (server)    -> success / failure message in RequirementText

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
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Rebirth") :: GuiButton

local rebirthGui = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local mainFrame = rebirthGui:WaitForChild("Main") :: Frame
local exitButton = mainFrame:WaitForChild("Exit") :: GuiButton
local rebirthButton = mainFrame:WaitForChild("Rebirth") :: TextButton

local moneyBar = mainFrame:WaitForChild("MoneyBar") :: Frame
local moneyProgress = moneyBar:WaitForChild("Progress") :: Frame
local moneyText = moneyBar:WaitForChild("MoneyText") :: TextLabel

local tipText = mainFrame:WaitForChild("RequirementTip"):WaitForChild("RequirementText") :: TextLabel

local requirementsFrame = mainFrame:WaitForChild("Requirements") :: Frame
local rowTemplate = requirementsFrame:WaitForChild("Template") :: Frame

-- Optional templates for one specific requirement (WoolTemplate, PensTemplate, WorkersTemplate).
-- A requirement without its own template uses the generic Template.
local specificTemplates: { [string]: Frame } = {}
for _, id in { "Pens", "Workers" } do
	local template = requirementsFrame:FindFirstChild(id .. "Template")
	if template and template:IsA("Frame") then
		specificTemplates[id] = template
	end
end

--// Configs
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MESSAGE_SECONDS = 2
local COLOR_MET = Color3.fromRGB(90, 220, 110)
local COLOR_UNMET = Color3.fromRGB(235, 90, 90)
local BUTTON_COLORS = {
	Ready = Color3.fromRGB(70, 200, 100),
	NotReady = Color3.fromRGB(120, 120, 120),
	Maxed = Color3.fromRGB(230, 190, 60),
}

-- What each requirement is called on its row (anything not listed uses the server's label).
local REQUIREMENT_LABELS = {
	Pens = "Pens owned",
	Workers = "Hire workers",
}

local REASON_TEXT = {
	Busy = "Please wait...",
	Shearing = "Finish shearing first",
	MaxRebirths = "You've reached the max rebirths",
	NotReady = "You don't meet every requirement yet",
}

--// State
local state: any = nil -- the last RebirthState from the server
local rows: { [string]: Frame } = {}
local messageToken = 0

local openScale = Instance.new("UIScale")
openScale.Parent = mainFrame

--// Helpers -------------------------------------------------------------------------

-- 1234567 -> "1,234,567"
local function formatNumber(value: number): string
	local text = tostring(math.floor(value))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
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

-- The line under the money bar when no message is showing.
local function getTip(): string
	if not state then
		return "Loading..."
	elseif state.maxed then
		return "You've reached the max rebirths!"
	elseif state.canRebirth then
		return `Ready! Rebirth to sell wool for {formatMultiplier(state.nextMultiplier)}.`
	end
	return `Meet every requirement to sell wool for {formatMultiplier(state.nextMultiplier)}. Your farm starts over.`
end

--// Rendering --------------------------------------------------------------------------

-- One row per requirement, cloned from the template the first time its id shows up.
local function getRow(id: string, order: number): Frame
	local row = rows[id]
	if not row then
		row = (specificTemplates[id] or rowTemplate):Clone()
		row.Name = id
		row.Parent = requirementsFrame
		rows[id] = row
	end

	row.LayoutOrder = order
	row.Visible = true
	return row
end

local function renderMoney()
	local cost = state.moneyCost
	local ratio = if state.maxed or cost <= 0 then 1 else math.clamp(state.money / cost, 0, 1)

	local size = moneyProgress.Size
	tweenService:Create(moneyProgress, BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()

	moneyText.Text = if state.maxed then "MAX" else `${formatNumber(state.money)}/${formatNumber(cost)}`
end

local function renderRequirements()
	local seen: { [string]: boolean } = {}

	for order, requirement in state.requirements do
		seen[requirement.id] = true
		local row = getRow(requirement.id, order)

		local label = row:FindFirstChild("TextLabel") :: TextLabel?
		if label then
			label.Text = `{REQUIREMENT_LABELS[requirement.id] or requirement.label}: {formatNumber(requirement.current)}/{formatNumber(requirement.required)}`
			label.TextColor3 = if requirement.met then COLOR_MET else COLOR_UNMET
		end

		local completed = row:FindFirstChild("Completed") :: GuiObject?
		if completed then
			completed.Visible = requirement.met
		end
	end

	-- Maxed out: no requirements are sent, so any row from before is hidden.
	for id, row in rows do
		if not seen[id] then
			row.Visible = false
		end
	end
end

local function renderButton()
	if state and state.maxed then
		rebirthButton.Text = "Max Rebirths"
		rebirthButton.BackgroundColor3 = BUTTON_COLORS.Maxed
	elseif state and state.canRebirth then
		rebirthButton.Text = "Rebirth!"
		rebirthButton.BackgroundColor3 = BUTTON_COLORS.Ready
	else
		rebirthButton.Text = "Rebirth"
		rebirthButton.BackgroundColor3 = BUTTON_COLORS.NotReady
	end

	rebirthButton:SetAttribute("CanRebirth", state ~= nil and state.canRebirth)
end

local function render()
	if state then
		renderMoney()
		renderRequirements()
	end

	messageToken += 1 -- a pending message must not overwrite the fresh text
	tipText.Text = getTip()
	renderButton()
end

-- Shows a short message in the tip line, then goes back to the normal tip.
local function flashMessage(text: string)
	messageToken += 1
	local token = messageToken
	tipText.Text = text
	shake(rebirthButton)

	task.delay(MESSAGE_SECONDS, function()
		if token == messageToken then
			tipText.Text = getTip()
		end
	end)
end

--// Open / close -----------------------------------------------------------------------

local function closeScreen()
	rebirthGui.Enabled = false
end

local function openScreen()
	if rebirthGui.Enabled then
		return
	end

	render()
	network.fireServer(network.RemoteEvents.RequestRebirthState)

	openScale.Scale = 0.85
	rebirthGui.Enabled = true
	tweenService:Create(openScale, OPEN_TWEEN, { Scale = 1 }):Play()
end

--// Setup -------------------------------------------------------------------------------

rowTemplate.Visible = false
for _, template in specificTemplates do
	template.Visible = false
end
rebirthGui.Enabled = false

openButton.MouseButton1Click:Connect(function()
	if rebirthGui.Enabled then
		closeScreen()
	else
		openScreen()
	end
end)

exitButton.MouseButton1Click:Connect(closeScreen)

rebirthButton.MouseButton1Click:Connect(function()
	if not state then
		network.fireServer(network.RemoteEvents.RequestRebirthState)
	elseif state.maxed then
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
	if rebirthGui.Enabled then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number)
	if success then
		-- The result arrives just before the fresh state, so the old state's next multiplier is the one just earned.
		if state then
			flashMessage(`Rebirth {rebirths}! Wool now sells for {formatMultiplier(state.nextMultiplier)}.`)
		else
			flashMessage(`Rebirth {rebirths}!`)
		end
	else
		flashMessage(REASON_TEXT[reason or ""] or "Can't rebirth right now")
	end
end)

-- Shearing started: the screen must not stay up over the mini-game.
network.connectEvent(network.RemoteEvents.ActivateShearing, closeScreen)

network.fireServer(network.RemoteEvents.RequestRebirthState)
