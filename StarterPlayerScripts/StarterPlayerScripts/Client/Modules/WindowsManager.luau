--[[
	Opens and closes every UI window (a ScreenGui's Main frame) with a pop in / shrink out, one window at a time.
	Each window's "Exit" button closes it and its open button toggles it.

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.WindowsManager
]]--

--// Services
local tweenService = game:GetService("TweenService")
local lighting = game:GetService("Lighting")

--// Configs
local EXIT_BUTTON_NAME = "Exit"
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local BLUR_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local OPEN_FROM_SCALE = 0.85 -- of the frame's own scale

--// Blur
-- Its Studio Size is the blur shown while any window is open.
local blur = lighting:WaitForChild("Blur") :: BlurEffect
local blurSize = blur.Size
local blurTween: Tween? = nil
blur.Enabled = false
blur.Size = 0

export type WindowOptions = {
	gui: ScreenGui,
	frame: GuiObject,
	openButton: GuiButton?, -- toggles the window
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

export type Window = {
	name: string,
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	isOpen: () -> boolean,
}

--// State
local windows: { [string]: Window } = {}
local openChanged = Instance.new("BindableEvent") -- fires with anyOpen() whenever a window opens or closes

local WindowsManager = {}
WindowsManager.openChanged = openChanged.Event

local function anyWindowOpen(): boolean
	for _, window in windows do
		if window.isOpen() then
			return true
		end
	end
	return false
end

local function updateBlur()
	local shown = anyWindowOpen()
	openChanged:Fire(shown)
	if blurTween then
		blurTween:Cancel()
	end
	if shown then
		blur.Enabled = true
	end

	local newTween = tweenService:Create(blur, BLUR_TWEEN, { Size = if shown then blurSize else 0 })
	blurTween = newTween
	newTween:Play()
	if not shown then
		newTween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				blur.Enabled = false
			end
		end)
	end
end

function WindowsManager.closeAll(except: Window?)
	for _, window in windows do
		if window ~= except then
			window.close()
		end
	end
end

function WindowsManager.anyOpen(): boolean
	return anyWindowOpen()
end

function WindowsManager.get(name: string): Window?
	return windows[name]
end

-- How much the UIScales on and above a GuiObject (the open/close tween's included) shrink it.
-- Its Absolute sizes divided by this are in Offset pixels, so sizes built from them don't follow the tween.
function WindowsManager.getScaleFactor(guiObject: Instance): number
	local factor = 1
	local current: Instance? = guiObject
	while current and not current:IsA("LayerCollector") do
		local scale = current:FindFirstChildOfClass("UIScale")
		if scale then
			factor *= scale.Scale
		end
		current = current.Parent
	end
	return factor
end

function WindowsManager.register(name: string, options: WindowOptions): Window
	local gui, frame = options.gui, options.frame

	-- A Studio-built UIScale keeps its value as the open size; otherwise one is added at 1.
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end
	local uiScale = scale :: UIScale
	local baseScale = uiScale.Scale

	local isOpen = false
	local token = 0
	local tween: Tween? = nil

	local function playTween(info: TweenInfo, target: number): Tween
		if tween then
			tween:Cancel()
		end
		local newTween = tweenService:Create(uiScale, info, { Scale = target })
		tween = newTween
		newTween:Play()
		return newTween
	end

	local window: Window

	local function open()
		if isOpen then
			return
		end
		WindowsManager.closeAll(window)

		isOpen = true
		token += 1
		if not gui.Enabled or not frame.Visible then
			uiScale.Scale = baseScale * OPEN_FROM_SCALE
		end
		gui.Enabled = true
		frame.Visible = true
		playTween(OPEN_TWEEN, baseScale)
		updateBlur()

		if options.onOpen then
			options.onOpen()
		end
	end

	local function close()
		if not isOpen then
			return
		end

		isOpen = false
		token += 1
		local closeToken = token
		playTween(CLOSE_TWEEN, 0).Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and closeToken == token then
				frame.Visible = false
				gui.Enabled = false
				uiScale.Scale = baseScale
			end
		end)
		updateBlur()

		if options.onClose then
			options.onClose()
		end
	end

	window = {
		name = name,
		open = open,
		close = close,
		toggle = function()
			if isOpen then
				close()
			else
				open()
			end
		end,
		isOpen = function()
			return isOpen
		end,
	}
	windows[name] = window

	-- Kept across respawns: a reset would swap in a fresh copy and leave the window driving the destroyed one.
	gui.ResetOnSpawn = false
	gui.Enabled = false
	frame.Visible = false

	local exitButton = frame:FindFirstChild(EXIT_BUTTON_NAME, true)
	if exitButton and exitButton:IsA("GuiButton") then
		exitButton.Activated:Connect(close)
	else
		warn(`[WindowsManager] {name} has no "{EXIT_BUTTON_NAME}" button in {frame:GetFullName()}`)
	end

	if options.openButton then
		options.openButton.Activated:Connect(window.toggle)
	end

	return window
end

return WindowsManager
