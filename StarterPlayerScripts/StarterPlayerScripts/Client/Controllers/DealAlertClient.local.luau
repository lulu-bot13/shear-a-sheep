--!strict

--[[
	Rocks Main.Shop.NewDealAlert side to side and cycles its text through the rainbow, so players notice the shop.
	Both come from the clock in one PreRender connection, and nothing runs while the label or Main is hidden.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.DealAlertClient
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local MAIN_GUI_NAME = "Main"
local ROCK_AMPLITUDE = 12 -- degrees either side of the label's Studio rotation
local ROCK_SECONDS = 1.2 -- one full swing there and back
local RAINBOW_SECONDS = 2 -- one full trip round the rainbow
local SATURATION = 0.85
local BRIGHTNESS = 1
local GRAYSCALE_TOLERANCE = 0.05 -- a UIGradient this close to grey only shades the text, so it is kept

--// State
local mainGui: ScreenGui? = nil
local alertLabel: TextLabel? = nil
local baseRotation = 0

local rockFrequency = 2 * math.pi / ROCK_SECONDS

--// Helpers -------------------------------------------------------------------------

local function isGrayscale(sequence: ColorSequence): boolean
	for _, keypoint in sequence.Keypoints do
		local color = keypoint.Value
		local high = math.max(color.R, color.G, color.B)
		local low = math.min(color.R, color.G, color.B)
		if high - low > GRAYSCALE_TOLERANCE then
			return false
		end
	end
	return true
end

-- A grey UIGradient multiplies with TextColor3 and keeps its shading; a coloured one would muddy the rainbow, so it's turned off.
local function prepareGradient(label: TextLabel)
	local gradient = label:FindFirstChildOfClass("UIGradient")
	if gradient and not isGrayscale(gradient.Color) then
		gradient.Enabled = false
	end
end

-- Shown only if the label and every GuiObject above it up to Main are visible and Main is enabled.
local function isShown(label: TextLabel, gui: ScreenGui): boolean
	if not gui.Enabled then
		return false
	end
	local current: Instance? = label
	while current and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == gui
end

--// Setup -------------------------------------------------------------------------------

-- Points the animation at this copy of Main; a fresh copy (e.g. after a respawn reset) replaces the old one.
local function attach(gui: Instance)
	if gui.Name ~= MAIN_GUI_NAME or not gui:IsA("ScreenGui") or gui == mainGui then
		return
	end
	mainGui = gui :: ScreenGui
	alertLabel = nil

	local label = gui:WaitForChild("Shop"):WaitForChild("NewDealAlert")
	if mainGui ~= gui or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return
	end
	local textLabel = label :: TextLabel
	baseRotation = textLabel.Rotation
	prepareGradient(textLabel)
	alertLabel = textLabel
end

playerGui.ChildAdded:Connect(attach)
task.spawn(attach, playerGui:WaitForChild(MAIN_GUI_NAME))

runService.PreRender:Connect(function()
	local gui, label = mainGui, alertLabel
	if not gui or not label or not isShown(label, gui) then
		return
	end

	local t = os.clock()
	label.Rotation = baseRotation + math.sin(t * rockFrequency) * ROCK_AMPLITUDE
	label.TextColor3 = Color3.fromHSV((t / RAINBOW_SECONDS) % 1, SATURATION, BRIGHTNESS)
end)
