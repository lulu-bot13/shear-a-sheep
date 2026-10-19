--[[
	The rebirth screen (StarterGui.RebirthScreen): shows wool towards the next rebirth and the multiplier it gives.
	Only displays what the server sends; RebirthHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local alertBadge = openButton:FindFirstChild("Alert", true) :: GuiObject? -- optional badge on the HUD button

local rebirthGui = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local mainFrame = rebirthGui:WaitForChild("Main") :: Frame
local exitButton = mainFrame:WaitForChild("Exit") :: GuiButton
local rebirthButton = mainFrame:WaitForChild("Rebirth") :: TextButton

-- The progress bar is still named MoneyBar in Studio; it now tracks wool.
local woolBar = mainFrame:WaitForChild("MoneyBar") :: Frame
local woolProgress = woolBar:WaitForChild("Progress") :: Frame
local woolText = woolBar:WaitForChild("MoneyText") :: TextLabel

local tipText = mainFrame:WaitForChild("RequirementTip"):WaitForChild("RequirementText") :: TextLabel
local requirementsFrame = mainFrame:FindFirstChild("Requirements")

-- Before -> after reward rows; Template is cloned for each row.
local rewardsFrame = rebirthGui:FindFirstChild("RewardsFrame", true) :: Frame
local rewardTemplate = rewardsFrame:WaitForChild("Template") :: Frame

local luckRow = rewardTemplate:Clone()
luckRow.Name = "Luck"
local luckBefore = luckRow:WaitForChild("Before"):WaitForChild("Amount") :: TextLabel
local luckAfter = luckRow:WaitForChild("After"):WaitForChild("Amount") :: TextLabel

--// Configs
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MESSAGE_SECONDS = 2
local BUTTON_COLORS = {
	Ready = Color3.fromRGB(70, 200, 100),
	NotReady = Color3.fromRGB(120, 120, 120),
	Maxed = Color3.fromRGB(230, 190, 60),
}

local REASON_TEXT = {
	Busy = "Please wait...",
	MaxRebirths = "You've reached the max rebirths",
	NotReady = "You don't have enough wool yet",
}

-- The bar and text as built in Studio, and their darker look once the wool target is reached.
local barColor = woolProgress.BackgroundColor3
local barReachedColor = barColor:Lerp(Color3.new(0, 0, 0), 0.4)
local textColor = woolText.TextColor3
local textReachedColor = textColor:Lerp(Color3.new(0, 0, 0), 0.4)

--// State
local state: any = nil -- the last RebirthState from the server
local messageToken = 0

local openScale = Instance.new("UIScale")
openScale.Parent = mainFrame

--// Helpers -------------------------------------------------------------------------

local function formatWool(value: number): string
	return numberFormatter:Format(math.floor(value), 1)
end

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

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

-- "+442 Luck", with a milestone tag when the next rebirth pays bonus Luck.
local function formatLuckReward(): string
	local text = `+{numberFormatter:Format(state.luckReward, 1)} Luck`
	return if state.luckMilestone then `{text} (Milestone bonus!)` else text
end

-- The line under the wool bar when no message is showing.
local function getTip(): string
	if not state then
		return "Loading..."
	elseif state.maxed then
		return "You've reached the max rebirths!"
	elseif state.canRebirth then
		return `Ready! Rebirth for {formatMultiplier(state.nextMultiplier)} wool and {formatLuckReward()}.`
	end
	return `Collect the wool to rebirth for {formatMultiplier(state.nextMultiplier)} wool and {formatLuckReward()}. Your farm starts over.`
end

--// Rendering --------------------------------------------------------------------------

local function renderWool()
	local cost = state.woolCost
	local ratio = if state.maxed or cost <= 0 then 1 else math.clamp(state.wool / cost, 0, 1)

	local size = woolProgress.Size
	tweenService:Create(woolProgress, BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()

	local reached = not state.maxed and state.wool >= cost
	tweenService:Create(woolProgress, BAR_TWEEN, { BackgroundColor3 = if reached then barReachedColor else barColor }):Play()
	tweenService:Create(woolText, BAR_TWEEN, { TextColor3 = if reached then textReachedColor else textColor }):Play()

	woolText.Text = if state.maxed then "MAX" else `{formatWool(math.min(state.wool, cost))}/{formatWool(cost)} Wool`
end

local function renderRewards()
	luckBefore.Text = formatLuck(state.luck, state.luckFactor)
	luckAfter.Text = formatLuck(state.nextLuck, state.nextLuckFactor)
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
end

local function render()
	if state then
		renderWool()
		renderRewards()
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

-- The HUD button's "Alert" badge shows an exclamation mark while a rebirth is ready.
local function updateAlert()
	if not alertBadge then
		return
	end

	local ready = state ~= nil and state.canRebirth == true
	alertBadge.Visible = ready
	if ready and (alertBadge:IsA("TextLabel") or alertBadge:IsA("TextButton")) then
		alertBadge.Text = "!"
	end
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

-- Rebirths only need wool now, so the old requirement rows stay hidden.
if requirementsFrame then
	requirementsFrame.Visible = false
end

local luckText = luckRow:FindFirstChild("Text")
if luckText and luckText:IsA("TextLabel") then
	luckText.Text = "Luck"
end
luckRow.Parent = rewardsFrame
rewardTemplate.Visible = false

rebirthGui.Enabled = false
updateAlert()

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
	updateAlert()
	if rebirthGui.Enabled then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number)
	if success then
		-- The result arrives just before the fresh state, so the old state's next rewards are the ones just earned.
		if state then
			flashMessage(`Rebirth {rebirths}! Wool is now {formatMultiplier(state.nextMultiplier)} and you got {formatLuckReward()}.`)
		else
			flashMessage(`Rebirth {rebirths}!`)
		end
	else
		flashMessage(REASON_TEXT[reason or ""] or "Can't rebirth right now")
	end
end)

network.fireServer(network.RemoteEvents.RequestRebirthState)
