--!strict

--[[
	A size factor for UI built in code: 1 on a ~1000 px tall screen, smaller on phones and bigger on large monitors, within limits.
	Code-made labels multiply their pixel sizes by get(), or take a UIScale from attach(), so they look the same on every device.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ScreenScale
]]--

--// Configs
local BASE_HEIGHT = 1000 -- viewport pixels at which code-built UI is drawn at its designed size
local MIN_SCALE = 0.62 -- phones in landscape are ~360-430 px tall; below this text gets hard to read
local MAX_SCALE = 1.5

--// State
local changedEvent = Instance.new("BindableEvent")
local current = 1
local cameraConnection: RBXScriptConnection? = nil
local attached: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any -- each UIScale and the multiplier it was attached with

local ScreenScale = {}
ScreenScale.changed = changedEvent.Event -- (scale) whenever the screen size changes the factor

local function compute(): number
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else BASE_HEIGHT
	return math.clamp(height / BASE_HEIGHT, MIN_SCALE, MAX_SCALE)
end

local function refresh()
	local scale = compute()
	if math.abs(scale - current) < 0.001 then
		return
	end
	current = scale
	for uiScale, multiplier in attached do
		if uiScale.Parent then
			uiScale.Scale = scale * multiplier
		end
	end
	changedEvent:Fire(scale)
end

local function watchCamera()
	if cameraConnection then
		cameraConnection:Disconnect()
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end

function ScreenScale.get(): number
	return current
end

-- Pixel sizes for code-built UI: `pixels` designed for a 1000 px tall screen, on this one.
function ScreenScale.px(pixels: number): number
	return pixels * current
end

-- Adds a UIScale to a code-built object that follows the screen (times `multiplier`); use a holder frame if it already has one.
function ScreenScale.attach(guiObject: GuiObject, multiplier: number?): UIScale
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "ScreenScale"
	uiScale.Scale = current * (multiplier or 1)
	uiScale.Parent = guiObject
	attached[uiScale] = multiplier or 1
	return uiScale
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
current = compute()
watchCamera()

return ScreenScale
