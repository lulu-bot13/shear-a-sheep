--!strict

--[[
	Sweeps a diagonal shine across every "ShineButton"-tagged button every few seconds, only while it's on screen and idle.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShineButton
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local TAG = "ShineButton"
local INTERVAL_ATTRIBUTE = "ShineInterval" -- optional number attribute on the button, overrides INTERVAL
local INTERVAL = 4 -- seconds between shines
local JITTER = 0.3 -- each wait is the interval +/- up to this fraction of it
local MIN_WAIT = 1
local CHECK_INTERVAL = 0.2
local SWEEP_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SWEEP_START = Vector2.new(-1, 0)
local SWEEP_END = Vector2.new(1, 0)
local SHINE_NAME = "ShineSweep"
local SHINE_ROTATION = 25
local SHINE_WIDTH = 0.15 -- fraction of the gradient the band covers
local SHINE_TRANSPARENCY = 0.5 -- at the centre of the band
local SHINE_SEQUENCE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5 - SHINE_WIDTH / 2, 1),
	NumberSequenceKeypoint.new(0.5, SHINE_TRANSPARENCY),
	NumberSequenceKeypoint.new(0.5 + SHINE_WIDTH / 2, 1),
	NumberSequenceKeypoint.new(1, 1),
})

--// State
type Shine = {
	frame: Frame,
	corner: UICorner,
	tween: Tween,
	gradient: UIGradient,
	destroying: RBXScriptConnection,
	nextPlay: number,
}

local shines: { [GuiButton]: Shine } = {}
local random = Random.new()

--// Helpers -------------------------------------------------------------------------

-- Visible all the way up, inside an Enabled ScreenGui in PlayerGui (not StarterGui).
local function isShown(button: GuiObject): boolean
	local current: Instance? = button
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return current == playerGui
end

local function isBusy(button: GuiButton): boolean
	local state = button.GuiState
	return state == Enum.GuiState.Hover or state == Enum.GuiState.Press
end

local function getWait(button: GuiButton): number
	local override = button:GetAttribute(INTERVAL_ATTRIBUTE)
	local interval = if type(override) == "number" and override > 0 then override else INTERVAL
	return math.max(interval * (1 + random:NextNumber(-JITTER, JITTER)), MIN_WAIT)
end

-- Covers the whole button (undoing any UIPadding), copies its corner and sits under its text children where it can.
local function fitToButton(button: GuiButton, shine: Shine)
	local frame = shine.frame
	local padding = button:FindFirstChildWhichIsA("UIPadding")
	if padding then
		local left, right, top, bottom = padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom
		local scaleX = 1 / math.max(1 - left.Scale - right.Scale, 0.01)
		local scaleY = 1 / math.max(1 - top.Scale - bottom.Scale, 0.01)
		local offsetX = scaleX * (left.Offset + right.Offset)
		local offsetY = scaleY * (top.Offset + bottom.Offset)
		frame.Size = UDim2.new(scaleX, offsetX, scaleY, offsetY)
		frame.Position = UDim2.new(-left.Scale * scaleX, -left.Offset - left.Scale * offsetX, -top.Scale * scaleY, -top.Offset - top.Scale * offsetY)
	else
		frame.Size = UDim2.fromScale(1, 1)
		frame.Position = UDim2.new()
	end

	local buttonCorner = button:FindFirstChildWhichIsA("UICorner")
	shine.corner.CornerRadius = if buttonCorner then buttonCorner.CornerRadius else UDim.new(0, 0)

	local gui = button:FindFirstAncestorWhichIsA("LayerCollector")
	if gui and gui.ZIndexBehavior == Enum.ZIndexBehavior.Global then
		frame.ZIndex = button.ZIndex
		return
	end
	local textZIndex: number? = nil
	for _, child in button:GetChildren() do
		if child ~= frame and child:IsA("GuiObject") and (child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox")) then
			textZIndex = math.min(textZIndex or child.ZIndex, child.ZIndex)
		end
	end
	frame.ZIndex = if textZIndex then textZIndex - 1 else 1
end

local function play(button: GuiButton, shine: Shine)
	fitToButton(button, shine)
	shine.gradient.Offset = SWEEP_START
	shine.frame.Visible = true
	shine.tween:Play()
end

--// Shines ---------------------------------------------------------------------------

local function onShineRemoved(instance: Instance)
	if not instance:IsA("GuiButton") then
		return
	end
	local shine = shines[instance]
	if not shine then
		return
	end
	shines[instance] = nil
	shine.destroying:Disconnect()
	shine.tween:Cancel()
	shine.tween:Destroy()
	shine.frame:Destroy()
end

-- The shine is the frame's own white background, cut down to a diagonal band by the gradient and rounded by the corner.
local function onShineAdded(instance: Instance)
	if not instance:IsA("GuiButton") or shines[instance] or not instance:IsDescendantOf(playerGui) then
		return
	end
	local button = instance

	local frame = Instance.new("Frame")
	frame.Name = SHINE_NAME
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Active = false
	frame.Visible = false

	local corner = Instance.new("UICorner")
	corner.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = SHINE_ROTATION
	gradient.Transparency = SHINE_SEQUENCE
	gradient.Offset = SWEEP_START
	gradient.Parent = frame

	local tween = tweenService:Create(gradient, SWEEP_TWEEN, { Offset = SWEEP_END })
	tween.Completed:Connect(function()
		frame.Visible = false
	end)

	local shine: Shine = {
		frame = frame,
		corner = corner,
		tween = tween,
		gradient = gradient,
		destroying = button.Destroying:Connect(function()
			onShineRemoved(button)
		end),
		nextPlay = os.clock() + random:NextNumber(0, getWait(button)),
	}
	shines[button] = shine
	fitToButton(button, shine)
	frame.Parent = button
end

--// Setup -------------------------------------------------------------------------------

collectionService:GetInstanceAddedSignal(TAG):Connect(onShineAdded)
collectionService:GetInstanceRemovedSignal(TAG):Connect(onShineRemoved)

for _, instance in collectionService:GetTagged(TAG) do
	onShineAdded(instance)
end

-- One loop for every button; a due button that's hidden, hovered or held just waits for its next turn.
task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		local now = os.clock()
		for button, shine in shines do
			if now >= shine.nextPlay then
				shine.nextPlay = now + getWait(button)
				if isShown(button) and not isBusy(button) then
					play(button, shine)
				end
			end
		end
	end
end)
