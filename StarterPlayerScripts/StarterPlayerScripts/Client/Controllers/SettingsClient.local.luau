--[[
	The Settings window (StarterGui.Settings): one row per SettingsData entry, cloned from List.Template, each with an ON / OFF switch.
	The Settings module applies and saves every change; this only draws the switches.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.SettingsClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local SettingsData = require(replicatedStorage.Shared.Constants.SettingsData)
local settings = require(script.Parent.Parent.Modules.Settings)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local settingsGui = playerGui:WaitForChild("Settings") :: ScreenGui
local mainFrame = settingsGui:WaitForChild("Main") :: GuiObject
local list = mainFrame:WaitForChild("List") :: ScrollingFrame
local template = list:WaitForChild("Template") :: GuiObject
local hudButtons = playerGui:WaitForChild("Main"):FindFirstChild("Buttons")
local hudButton = hudButtons and hudButtons:FindFirstChild("Settings")

--// Configs
local KNOB_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local KNOB_ON_POSITION = UDim2.fromScale(0.5, 0.5)
local KNOB_OFF_POSITION = UDim2.fromScale(0, 0.5)
local ON_GRADIENT = ColorSequence.new(Color3.fromRGB(150, 230, 135), Color3.fromRGB(95, 195, 90))
local OFF_GRADIENT = ColorSequence.new(Color3.fromRGB(255, 120, 120), Color3.fromRGB(215, 55, 55))

type Row = {
	knob: GuiObject,
	gradient: UIGradient?,
	label: TextLabel?,
}

--// State
local rows: { [string]: Row } = {}

--// Helpers -------------------------------------------------------------------------

local function setText(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = text
	end
end

-- Slides the knob to its side and recolours it; `instant` skips the slide (building the rows, or opening the window).
local function renderSwitch(row: Row, on: boolean, instant: boolean?)
	local position = if on then KNOB_ON_POSITION else KNOB_OFF_POSITION
	if instant then
		row.knob.Position = position
	else
		tweenService:Create(row.knob, KNOB_TWEEN, { Position = position }):Play()
	end
	if row.gradient then
		row.gradient.Color = if on then ON_GRADIENT else OFF_GRADIENT
	end
	if row.label then
		row.label.Text = if on then "ON" else "OFF"
	end
end

-- ButtonClient already plays UISounds.Click on every GuiButton press, the switch included.
local function buildRow(setting: SettingsData.Setting, order: number)
	local frame = template:Clone()
	frame.Name = setting.id
	frame.LayoutOrder = order
	setText(frame, "Title", setting.title)
	setText(frame, "Description", setting.description)

	local toggle = frame:WaitForChild("Toggle") :: GuiButton
	local knob = toggle:WaitForChild("Knob") :: GuiObject
	local row: Row = {
		knob = knob,
		gradient = knob:FindFirstChildOfClass("UIGradient"),
		label = knob:FindFirstChild("Label") :: TextLabel?,
	}
	rows[setting.id] = row
	renderSwitch(row, settings.get(setting.id), true)

	local function flip()
		settings.set(setting.id, not settings.get(setting.id))
	end
	toggle.Activated:Connect(flip)
	-- The Knob sits on top of the switch, so it would swallow clicks if it's a button too.
	if knob:IsA("GuiButton") then
		knob.Activated:Connect(flip)
	end

	frame.Visible = true
	frame.Parent = list
end

--// Setup -------------------------------------------------------------------------------

template.Visible = false
for order, setting in SettingsData.List do
	buildRow(setting, order)
end

-- TopbarClient's Settings button finds the window by this name.
local window = windowsManager.register("Settings", {
	gui = settingsGui,
	frame = mainFrame,
	openButton = if hudButton and hudButton:IsA("GuiButton") then hudButton else nil,
	onOpen = function()
		list.CanvasPosition = Vector2.zero
	end,
})

settings.changed:Connect(function(id: string, value: boolean)
	local row = rows[id]
	if row then
		renderSwitch(row, value, not window.isOpen())
	end
end)
