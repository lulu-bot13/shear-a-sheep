--[[
	The rebirth screen (StarterGui.RebirthScreen): uses the UI as built in Studio and only fills in the before -> after Luck.
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

local DEBUG = true -- TODO: set to false once the rebirth button works

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

local rebirthGui = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local mainFrame = rebirthGui:WaitForChild("Main") :: Frame
local exitButton = mainFrame:WaitForChild("Exit") :: GuiButton
local rebirthButton = mainFrame:WaitForChild("Rebirth") :: GuiButton

local requirementBar = mainFrame:WaitForChild("RequirementBar") :: Frame
local requirementProgress = requirementBar:WaitForChild("Progress") :: Frame
local woolCount = requirementBar:WaitForChild("WoolCount") :: TextLabel

-- The before -> after row built in Studio.
local rewardsFrame = mainFrame:WaitForChild("RewardsFrame") :: Frame
local rewardRow = rewardsFrame:WaitForChild("Template") :: Frame
local luckBefore = rewardRow:WaitForChild("Before"):WaitForChild("Amount") :: TextLabel
local luckAfter = rewardRow:WaitForChild("After"):WaitForChild("Amount") :: TextLabel

debugLog(`found the UI (Rebirth button is a {rebirthButton.ClassName}, open button is a {openButton.ClassName})`)

--// Configs
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LUCK_BEFORE_COLOR = Color3.fromRGB(170, 170, 170)
local LUCK_AFTER_COLOR = Color3.fromRGB(170, 235, 170)

-- Luck icons falling down the screen after a rebirth. Spawning + the slowest fall add up to EFFECT_SECONDS.
local LUCK_ICON_IMAGE = "rbxassetid://86611651520562" -- "rbxassetid://..."; empty uses the icon in the rebirth screen's Luck row
local EFFECT_SECONDS = 3.5
local FALL_ICON_COUNT = 40
local FALL_SPAWN_SECONDS = 1.5
local FALL_MIN_SECONDS = 1.4
local FALL_MAX_SECONDS = EFFECT_SECONDS - FALL_SPAWN_SECONDS
local FALL_MIN_SIZE = 36
local FALL_MAX_SIZE = 72

--// State
local state: any = nil -- the last RebirthState from the server

local openScale = Instance.new("UIScale")
openScale.Parent = mainFrame

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

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

--// Rebirth effect ---------------------------------------------------------------------

local function getLuckIconImage(): string
	if LUCK_ICON_IMAGE ~= "" then
		return LUCK_ICON_IMAGE
	end
	local rowIcon = rewardRow:FindFirstChildWhichIsA("ImageLabel", true)
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

local function render()
	if not state then
		return
	end

	luckBefore.Text = formatLuck(state.luck, state.luckFactor)
	luckAfter.Text = formatLuck(state.nextLuck, state.nextLuckFactor)

	-- Requirement bar: fills with wool towards the next rebirth's cost.
	local ratio = if state.maxed or state.woolCost <= 0 then 1 else math.clamp(state.wool / state.woolCost, 0, 1)
	local size = requirementProgress.Size
	tweenService:Create(requirementProgress, BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()
	woolCount.Text = if state.maxed
		then "MAX"
		else `{numberFormatter:Format(math.floor(state.wool), 1)}/{numberFormatter:Format(state.woolCost, 1)} Wool`

	-- The button shows the server's real wool cost, so it never disagrees with what Studio's text says.
	if rebirthButton:IsA("TextButton") then
		rebirthButton.Text = if state.maxed
			then "Max Rebirths"
			elseif state.canRebirth then "Rebirth!"
			else `Need {numberFormatter:Format(state.woolCost, 1)} Wool`
	end
end

-- The HUD button's "Alert" badge shows while a rebirth is ready.
local function updateAlert()
	if alertBadge then
		alertBadge.Visible = state ~= nil and state.canRebirth == true
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

luckBefore.TextColor3 = LUCK_BEFORE_COLOR
luckAfter.TextColor3 = LUCK_AFTER_COLOR

-- Without this, respawning swaps in a fresh RebirthScreen that this script isn't connected to.
rebirthGui.ResetOnSpawn = false
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
		debugLog("clicked Rebirth, but no state from the server yet; asking for it")
		network.fireServer(network.RemoteEvents.RequestRebirthState)
	elseif state.canRebirth and not state.maxed then
		debugLog("clicked Rebirth, sending RequestRebirth")
		network.fireServer(network.RemoteEvents.RequestRebirth)
	else
		debugLog(`clicked Rebirth, not ready: wool {state.wool}/{state.woolCost}, canRebirth {state.canRebirth}, maxed {state.maxed}`)
		shake(rebirthButton)
	end
end)

debugLog("button clicks connected, waiting for the network")
network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthState, function(newState: any)
	debugLog(`got state: rebirths {newState.rebirths}, wool {newState.wool}/{newState.woolCost}, canRebirth {newState.canRebirth}`)
	state = newState
	updateAlert()
	if rebirthGui.Enabled then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?)
	debugLog(`rebirth result: success {success}, reason {reason}`)
	if success then
		playLuckRain()
	else
		shake(rebirthButton)
	end
end)

network.fireServer(network.RemoteEvents.RequestRebirthState)
