--[[
	Rebirth panel. Opens from the HUD's "Rebirth" button and lists the three things a rebirth needs
	(a sheep in a pen, money, wool) with a tick or cross each. The Rebirth button inside the panel
	is only enabled when everything is met. The server (RebirthHandler) checks it all again.

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

--// Configs
local HUD_BUTTON_NAME = "Rebirth"
local REFRESH_SECONDS = 1
local FIND_BUTTON_SECONDS = 15
local RESULT_SECONDS = 2.5
local FONT = Enum.Font.SourceSansBold
local PANEL_COLOR = Color3.fromRGB(16, 17, 24)
local ROW_COLOR = Color3.fromRGB(30, 32, 44)
local GOLD = Color3.fromRGB(255, 176, 32)
local GREEN = Color3.fromRGB(110, 255, 130)
local RED = Color3.fromRGB(255, 100, 100)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(200, 202, 212)
local POP_IN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local FAILURE_TEXT = {
	NoSheep = "You need a good enough sheep in a pen",
	NoMoney = "Not enough money",
	NoWool = "Not enough wool",
	Shearing = "Finish shearing first",
	Busy = "Please wait...",
	Maxed = "You are at the maximum rebirth",
}

type Row = { icon: TextLabel, detail: TextLabel }

--// State
local isOpen = false
local resultToken = 0
local latest: any = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RebirthGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local function formatNumber(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return grouped
end

local function addCorner(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function newLabel(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.Text = text
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

--// Panel ---------------------------------------------------------------------------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(380, 330)
panel.BackgroundColor3 = PANEL_COLOR
panel.Visible = false
panel.Parent = screenGui
addCorner(panel, 14)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = GOLD
panelStroke.Thickness = 3
panelStroke.Parent = panel

local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = newLabel(panel, "Rebirth", 34, GOLD)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -60, 0, 40)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -10, 0, 10)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = RED
closeButton.Font = FONT
closeButton.Text = "X"
closeButton.TextSize = 22
closeButton.TextColor3 = WHITE
closeButton.Parent = panel
addCorner(closeButton, 8)

local subtitle = newLabel(panel, "", 20, MUTED)
subtitle.Position = UDim2.fromOffset(16, 48)
subtitle.Size = UDim2.new(1, -32, 0, 24)

local function buildRow(name: string, order: number): Row
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(16, 82 + (order - 1) * 62)
	frame.Size = UDim2.new(1, -32, 0, 54)
	frame.BackgroundColor3 = ROW_COLOR
	frame.Parent = panel
	addCorner(frame, 10)

	local icon = newLabel(frame, "", 30, RED)
	icon.TextXAlignment = Enum.TextXAlignment.Center
	icon.Position = UDim2.fromOffset(6, 0)
	icon.Size = UDim2.fromOffset(40, 54)

	local heading = newLabel(frame, name, 22, WHITE)
	heading.Position = UDim2.fromOffset(52, 4)
	heading.Size = UDim2.new(1, -60, 0, 24)

	local detail = newLabel(frame, "", 18, MUTED)
	detail.Position = UDim2.fromOffset(52, 28)
	detail.Size = UDim2.new(1, -60, 0, 22)

	return { icon = icon, detail = detail }
end

local sheepRow = buildRow("Sheep", 1)
local moneyRow = buildRow("Money", 2)
local woolRow = buildRow("Wool", 3)

local rebirthButton = Instance.new("TextButton")
rebirthButton.Name = "Confirm"
rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
rebirthButton.Position = UDim2.new(0.5, 0, 1, -34)
rebirthButton.Size = UDim2.new(1, -32, 0, 44)
rebirthButton.Font = FONT
rebirthButton.Text = "Rebirth"
rebirthButton.TextSize = 26
rebirthButton.TextColor3 = WHITE
rebirthButton.Parent = panel
addCorner(rebirthButton, 10)

local message = newLabel(panel, "", 18, RED)
message.AnchorPoint = Vector2.new(0.5, 1)
message.Position = UDim2.new(0.5, 0, 1, -8)
message.Size = UDim2.new(1, -32, 0, 22)
message.TextXAlignment = Enum.TextXAlignment.Center

--// Behaviour -----------------------------------------------------------------------

local function setRow(row: Row, met: boolean, detail: string)
	row.icon.Text = if met then "✓" else "✗"
	row.icon.TextColor3 = if met then GREEN else RED
	row.detail.Text = detail
end

local function showMessage(text: string, color: Color3)
	resultToken += 1
	local token = resultToken
	message.Text = text
	message.TextColor3 = color

	task.delay(RESULT_SECONDS, function()
		if token == resultToken then
			message.Text = ""
		end
	end)
end

local function render(status: any)
	latest = status

	if status.maxed then
		subtitle.Text = `Rebirths: {status.rebirths} (maximum)`
	else
		subtitle.Text = `Rebirths: {status.rebirths}  ·  Next: #{status.nextRebirth}`
	end

	local sheepDetail = if status.sheep.met
		then `{status.sheep.name or "A sheep"} is ready in a pen`
		else `Get a {status.minRarity} or better sheep into a pen`
	setRow(sheepRow, status.sheep.met, sheepDetail)
	setRow(moneyRow, status.money.met, `${formatNumber(status.money.have)} / ${formatNumber(status.money.need)}`)
	setRow(woolRow, status.wool.met, `{formatNumber(status.wool.have)} / {formatNumber(status.wool.need)} (don't sell it)`)

	rebirthButton.Active = status.canRebirth
	rebirthButton.AutoButtonColor = status.canRebirth
	rebirthButton.BackgroundColor3 = if status.canRebirth then Color3.fromRGB(46, 160, 67) else Color3.fromRGB(70, 72, 84)
end

local function requestStatus()
	network.fireServer(network.RemoteEvents.RebirthRequest, "Status")
end

local function setOpen(open: boolean)
	if open == isOpen then
		return
	end
	isOpen = open

	if not open then
		panel.Visible = false
		return
	end

	message.Text = ""
	panelScale.Scale = 0.7
	panel.Visible = true
	tweenService:Create(panelScale, POP_IN, { Scale = 1 }):Play()
	requestStatus()

	-- Keep the ticks live (money and wool change as sheep are sheared) while the panel is open.
	task.spawn(function()
		while isOpen do
			task.wait(REFRESH_SECONDS)
			if isOpen then
				requestStatus()
			end
		end
	end)
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)

rebirthButton.Activated:Connect(function()
	if not latest or not latest.canRebirth then
		return
	end
	network.fireServer(network.RemoteEvents.RebirthRequest, "Confirm")
end)

-- The HUD's Rebirth button already exists in Studio; find it by name and wire it up.
local function connectHudButton(button: GuiButton)
	button.Activated:Connect(function()
		setOpen(not isOpen)
	end)
end

task.spawn(function()
	local deadline = os.clock() + FIND_BUTTON_SECONDS
	while os.clock() < deadline do
		for _, descendant in playerGui:GetDescendants() do
			if descendant.Name == HUD_BUTTON_NAME and descendant:IsA("GuiButton") and not screenGui:IsAncestorOf(descendant) then
				connectHudButton(descendant)
				return
			end
		end
		task.wait(0.5)
	end
	warn(`RebirthClient: no button named '{HUD_BUTTON_NAME}' found in PlayerGui.`)
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthUpdate, function(status: any, result: any)
	render(status)

	if result == "Success" then
		showMessage(`Reborn! Rebirth #{status.rebirths}`, GREEN)
	elseif type(result) == "string" then
		showMessage(FAILURE_TEXT[result] or "Can't rebirth right now", RED)
	end
end)
