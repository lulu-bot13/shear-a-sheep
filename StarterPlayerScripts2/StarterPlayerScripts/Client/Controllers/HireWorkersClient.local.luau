--[[
	The hire workers UI (StarterGui.HireWorkers).

	Pressing any ProximityPrompt tagged "HireWorkers" opens it. The server (HireWorkersServer) decides how
	many workers the player may have, what the next one costs and whether the hire goes through; this
	script only draws what it is sent. The names it looks for:

		HireWorkers [ScreenGui]
		└─ Main [Frame]
		   ├─ Hire [TextButton]         its TextLabel shows "HIRE $750" / "WORKERS FULL" / "NO FREE PEN"
		   ├─ Exit [TextButton]
		   ├─ PlayerImage [ImageLabel]  the player's avatar headshot
		   └─ CurrentAmount [TextLabel] "Workers: 2/3"

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.HireWorkersClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hireGui = playerGui:WaitForChild("HireWorkers") :: ScreenGui
local main = hireGui:WaitForChild("Main") :: Frame
local hireButton = main:WaitForChild("Hire") :: TextButton
local hireLabel = hireButton:WaitForChild("TextLabel") :: TextLabel
local exitButton = main:WaitForChild("Exit") :: TextButton
local playerImage = main:WaitForChild("PlayerImage") :: ImageLabel
local amountLabel = main:WaitForChild("CurrentAmount") :: TextLabel
local money = player:WaitForChild("leaderstats"):WaitForChild("Money") :: IntValue

--// Configs
local PROMPT_TAG = "HireWorkers"
local CLOSE_DISTANCE_EXTRA = 6 -- studs past the prompt's activation range before the screen closes itself
local CLOSE_DISTANCE_FROM_MENU = 14 -- studs from where the pen menu opened it before the screen closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local DISABLED_FILL = Color3.fromRGB(96, 99, 110)
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--// State
local openToken = 0
local currentState: any = nil
local pendingPenId: number? = nil -- the pen whose Hire button opened the screen
local closeScreen: () -> ()
local readyFill = hireButton.BackgroundColor3

local openScale = Instance.new("UIScale")
openScale.Parent = main

-- Fired by the pen menu when a pen has no worker to give; this script tells it when the screen closes.
local function getBindable(name: string): BindableEvent
	local existing = player:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end

	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = player
	return event
end

local openRequest = getBindable("OpenHireWorkers")
local hireWorkersClosed = getBindable("HireWorkersClosed")

--// Helpers -------------------------------------------------------------------

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function getPromptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function loadHeadshot()
	local success, image = pcall(function()
		return players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if success then
		playerImage.Image = image
	end
end

-- Draws the worker numbers; `reason` is why the last hire was refused, if it was.
local function render(state: any, reason: string?)
	currentState = state
	amountLabel.Text = `Workers: {state.owned}/{state.max}`

	if state.owned >= state.max then
		hireLabel.Text = "WORKERS FULL"
		hireButton.BackgroundColor3 = DISABLED_FILL
	else
		hireLabel.Text = `HIRE ${numberFormatter:Format(state.cost, 1)}`
		hireButton.BackgroundColor3 = if state.canAfford then readyFill else readyFill:Lerp(DISABLED_FILL, 0.6)
	end

	if reason then
		shake(hireButton)
	end

	-- Opened from a pen's menu: the worker just bought goes onto that pen and the screen closes.
	if pendingPenId and state.available > 0 and not reason then
		local penId = pendingPenId
		closeScreen()
		network.fireServer(network.RemoteEvents.HireWorker, penId)
	end
end

--// Open / close ---------------------------------------------------------------

closeScreen = function()
	pendingPenId = nil
	local wasOpen = hireGui.Enabled
	openToken += 1
	hireGui.Enabled = false
	if wasOpen then
		hireWorkersClosed:Fire()
	end
end

-- `prompt` is the prompt that opened the screen; without one (opened from a pen's menu) walking
-- CLOSE_DISTANCE_FROM_MENU studs away from where it opened closes it.
local function openScreen(prompt: ProximityPrompt?)
	openToken += 1
	local token = openToken

	openScale.Scale = 0.8
	hireGui.Enabled = true
	tweenService:Create(openScale, OPEN_TWEEN, { Scale = 1 }):Play()
	network.fireServer(network.RemoteEvents.RequestHireWorkersState)

	local startRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local startPosition = if startRoot then startRoot.Position else nil

	-- Walking away closes the screen.
	task.spawn(function()
		while openToken == token do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local tooFar = true
			if root and prompt then
				local position = getPromptPosition(prompt)
				tooFar = position == nil or (root.Position - position).Magnitude > prompt.MaxActivationDistance + CLOSE_DISTANCE_EXTRA
			elseif root and startPosition then
				tooFar = (root.Position - startPosition).Magnitude > CLOSE_DISTANCE_FROM_MENU
			end
			if tooFar then
				closeScreen()
				return
			end
			task.wait(DISTANCE_CHECK_SECONDS)
		end
	end)
end

local function connectPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		warn(`HireWorkersClient: {instance:GetFullName()} is tagged {PROMPT_TAG} but is not a ProximityPrompt.`)
		return
	end

	instance.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer ~= player then
			return
		end
		if hireGui.Enabled then
			closeScreen()
		else
			openScreen(instance)
		end
	end)
end

--// Setup ---------------------------------------------------------------------------

hireGui.ResetOnSpawn = false
hireGui.Enabled = false
loadHeadshot()

exitButton.MouseButton1Click:Connect(closeScreen)

openRequest.Event:Connect(function(penId: number?)
	if not hireGui.Enabled then
		pendingPenId = penId
		openScreen(nil)
	end
end)

hireButton.MouseButton1Click:Connect(function()
	local state = currentState
	if not state or state.owned >= state.max or not state.canAfford then
		shake(hireButton)
		return
	end
	network.fireServer(network.RemoteEvents.HireWorkersHire)
end)

-- A balance change can make the button affordable (or not), so ask for fresh numbers.
money.Changed:Connect(function()
	if hireGui.Enabled then
		network.fireServer(network.RemoteEvents.RequestHireWorkersState)
	end
end)

for _, instance in collectionService:GetTagged(PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(connectPrompt)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.HireWorkersState, render)
network.connectEvent(network.RemoteEvents.ActivateShearing, closeScreen)
