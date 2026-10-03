--[[
	Drives the RebirthScreen UI (StarterGui.RebirthScreen): the money bar, one row per required item
	(cloned from Main.Requirements.Template), the requirement tip, and the Rebirth and Exit buttons.
	The HUD's "Rebirth" button opens it. The server (RebirthHandler) decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")
local screen = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local main = screen:WaitForChild("Main") :: Frame
local moneyBar = main:WaitForChild("MoneyBar") :: Frame
local progress = moneyBar:WaitForChild("Progress") :: Frame
local moneyText = moneyBar:WaitForChild("MoneyText") :: TextLabel
local tipText = main:WaitForChild("RequirementTip"):WaitForChild("RequirementText") :: TextLabel
local requirementsFrame = main:WaitForChild("Requirements") :: Frame
local template = requirementsFrame:WaitForChild("Template") :: Frame
local exitButton = main:WaitForChild("Exit") :: GuiButton
local rebirthButton = main:WaitForChild("Rebirth") :: GuiButton

--// Configs
local HUD_BUTTON_NAME = "Rebirth"
local REFRESH_SECONDS = 1
local FIND_BUTTON_SECONDS = 15
local TIP_SECONDS = 3
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local RESULT_TEXT = {
	Success = "Reborn!",
	NoSheep = "You need a better sheep in a pen",
	NoMoney = "Not enough money",
	NoWool = "Not enough wool",
	Shearing = "Finish shearing first",
	Maxed = "You are at the maximum rebirth",
}

--// State
local rows: { [string]: Frame } = {}
local isOpen = false
local canRebirth = false
local latestStatus: any = nil
local tipLocked = false
local tipToken = 0

--[[
	Formats a number with thousands separators.

	@param amount The number to format

	@return The formatted text, e.g. "32,000"
]]--
local function formatNumber(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return grouped
end

--[[
	Gets the row for a requirement, cloning it from the template the first time.

	@param id The requirement's id, e.g. "Sheep"
	@param order Where the row sits in the list

	@return The row Frame
]]--
local function getRow(id: string, order: number): Frame
	local row = rows[id]
	if row then
		return row
	end

	row = template:Clone()
	row.Name = id
	row.LayoutOrder = order
	row.Visible = true
	row.Parent = requirementsFrame
	rows[id] = row
	return row
end

--[[
	Fills a requirement row with its text and shows its Completed marker once it is met.

	@param requirement The requirement from the server status
	@param order Where the row sits in the list
]]--
local function updateRow(requirement: any, order: number)
	local row = getRow(requirement.id, order)
	local label = row:FindFirstChild("TextLabel") :: TextLabel
	local completed = row:FindFirstChild("Completed") :: GuiObject

	label.Text = if requirement.required > 1
		then `{requirement.label}: {formatNumber(requirement.current)}/{formatNumber(requirement.required)}`
		else requirement.label
	completed.Visible = requirement.met
end

--[[
	Works out what the requirement tip should say for a status.

	@param status The status from the server

	@return The tip text
]]--
local function getTip(status: any): string
	if status.maxed then
		return "Maximum rebirths reached"
	end
	if status.canRebirth then
		return "Ready to rebirth!"
	end

	for _, requirement in status.requirements do
		if not requirement.met then
			return `Still needed: {requirement.label}`
		end
	end
	return "Still needed: more money"
end

--[[
	Shows a message in the requirement tip for a few seconds, then returns to the normal tip.

	@param text The message to show
]]--
local function flashTip(text: string)
	tipToken += 1
	local token = tipToken
	tipLocked = true
	tipText.Text = text

	task.delay(TIP_SECONDS, function()
		if token == tipToken then
			tipLocked = false
			tipText.Text = if latestStatus then getTip(latestStatus) else ""
		end
	end)
end

--[[
	Redraws the whole screen from a server status.

	@param status The status from the server
]]--
local function render(status: any)
	latestStatus = status
	canRebirth = status.canRebirth

	local ratio = math.clamp(status.money.current / status.money.required, 0, 1)
	local size = progress.Size
	tweenService:Create(progress, BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()
	moneyText.Text = `${formatNumber(status.money.current)}/${formatNumber(status.money.required)}`

	for order, requirement in status.requirements do
		updateRow(requirement, order)
	end

	rebirthButton.Interactable = canRebirth
	if not tipLocked then
		tipText.Text = getTip(status)
	end
end

--[[
	Asks the server for the latest status.
]]--
local function requestStatus()
	network.fireServer(network.RemoteEvents.RebirthRequest, "Status")
end

--[[
	Opens or closes the screen; while open it keeps refreshing the status.

	@param open True to open, false to close
]]--
local function setOpen(open: boolean)
	if open == isOpen then
		return
	end

	isOpen = open
	screen.Enabled = open
	if not open then
		return
	end

	requestStatus()
	task.spawn(function()
		while isOpen do
			task.wait(REFRESH_SECONDS)
			if isOpen then
				requestStatus()
			end
		end
	end)
end

--[[
	Opens or closes the screen whenever the HUD's Rebirth button is pressed.

	@param button The HUD button
]]--
local function connectHudButton(button: GuiButton)
	button.Activated:Connect(function()
		setOpen(not isOpen)
	end)
end

--[[
	Finds the HUD's Rebirth button (outside RebirthScreen) and connects it.
]]--
local function findHudButton()
	local deadline = os.clock() + FIND_BUTTON_SECONDS
	while os.clock() < deadline do
		for _, descendant in playerGui:GetDescendants() do
			if descendant.Name == HUD_BUTTON_NAME and descendant:IsA("GuiButton") and not screen:IsAncestorOf(descendant) then
				connectHudButton(descendant)
				return
			end
		end
		task.wait(0.5)
	end
	warn(`RebirthClient: no HUD button named '{HUD_BUTTON_NAME}' found.`)
end

template.Visible = false
screen.Enabled = false

exitButton.Activated:Connect(function()
	setOpen(false)
end)

rebirthButton.Activated:Connect(function()
	if canRebirth then
		network.fireServer(network.RemoteEvents.RebirthRequest, "Confirm")
	end
end)

task.spawn(findHudButton)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthUpdate, function(status: any, result: any)
	render(status)
	if type(result) == "string" then
		flashTip(RESULT_TEXT[result] or "Can't rebirth right now")
	end
end)
