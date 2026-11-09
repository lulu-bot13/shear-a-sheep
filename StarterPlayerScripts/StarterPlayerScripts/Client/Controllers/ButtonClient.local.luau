--[[
	Hover and press animations and sounds for every UI button: "Rotate" buttons tilt, the rest grow.
	Claim / Buy / Unlock / Purchase buttons grow more and pop with a ring burst when clicked.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ButtonClient
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local collectionService = game:GetService("CollectionService")
local soundService = game:GetService("SoundService")
local runService = game:GetService("RunService")

--// Modules
local settings = require(script.Parent.Parent.Modules.Settings)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sound Effects
local uiSounds = soundService:WaitForChild("UISounds")
local hoverSound = uiSounds:WaitForChild("Hover") :: Sound
local clickSound = uiSounds:WaitForChild("Click") :: Sound

--// Configs
local ROTATE_TAG = "Rotate" -- works as a tag or an attribute, in any letter case and with stray spaces (" rotate")
local HOVER_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_SCALE = 1.01
local PRESS_SCALE = 0.94
local HOVER_ROTATION = 8
local HOVER_SCALE_ATTRIBUTE = "HoverScale" -- optional number attributes on a button, overriding its hover and press scales
local PRESS_SCALE_ATTRIBUTE = "PressScale"
local DEBUG = false

--// Action buttons: any button whose name holds one of these words (any case), or with an "ActionButton" attribute
local ACTION_WORDS = { "claim", "buy", "unlock", "purchase" }
local ACTION_ATTRIBUTE = "ActionButton" -- set false to opt a matching button out
local ACTION_HOVER_SCALE = 1.08
local ACTION_PRESS_SCALE = 0.9
local ACTION_POP_SCALE = 1.18 -- the bounce on click, before settling back
local ACTION_POP_TWEEN = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ACTION_SETTLE_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local RING_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RING_GROW = UDim2.fromScale(1.35, 1.6)
local RING_THICKNESS = 4
local RING_COLOR = Color3.new(1, 1, 1)

local function debugLog(message: string)
	if DEBUG then
		print(`[ButtonClient] {message}`)
	end
end

--// State
-- button -> { hover, leave, press, release }, each a list of tweens played together
local tweens: { [GuiObject]: { [string]: { Tween } } } = {}
local hovered: { [GuiObject]: boolean } = {}
local baseRotations: { [GuiObject]: number } = {} -- the rest angle, read before any tween moves it

--// Helpers -------------------------------------------------------------------------

-- The three buttons in Main.Buttons always rotate, even after Main is recreated on respawn.
local function isMainHudButton(button: GuiObject): boolean
	local parent = button.Parent
	local gui = parent and parent.Parent
	return parent ~= nil and parent.Name == "Buttons" and gui ~= nil and gui:IsA("ScreenGui") and gui.Name == "Main"
end

local function isRotateName(name: string): boolean
	return name:lower():match("^%s*(.-)%s*$") == ROTATE_TAG:lower()
end

local function isRotateButton(button: GuiObject): boolean
	for _, tag in button:GetTags() do
		if isRotateName(tag) then
			return true
		end
	end
	for name, value in button:GetAttributes() do
		if isRotateName(name) and value ~= false and value ~= "false" then
			return true
		end
	end
	return false
end

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

local function isActionButton(button: GuiObject): boolean
	local flag = button:GetAttribute(ACTION_ATTRIBUTE)
	if flag ~= nil then
		return flag == true
	end
	local name = button.Name:lower()
	for _, word in ACTION_WORDS do
		if name:find(word, 1, true) then
			return true
		end
	end
	return false
end

local function getScale(button: GuiObject): UIScale
	local scale = button:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	return scale :: UIScale
end

local function getScaleAttribute(button: GuiObject, name: string, default: number): number
	local value = button:GetAttribute(name)
	return if type(value) == "number" and value > 0 then value else default
end

local function buildTweens(button: GuiObject): { [string]: { Tween } }
	local scale = getScale(button)
	local function scaleTo(info: TweenInfo, value: number): Tween
		return tweenService:Create(scale, info, { Scale = value })
	end

	if isRotateButton(button) then
		local baseRotation = baseRotations[button] or button.Rotation
		return {
			hover = { tweenService:Create(button, HOVER_TWEEN, { Rotation = baseRotation + HOVER_ROTATION }) },
			leave = { tweenService:Create(button, HOVER_TWEEN, { Rotation = baseRotation }), scaleTo(HOVER_TWEEN, 1) },
			press = { scaleTo(PRESS_TWEEN, PRESS_SCALE) },
			release = { scaleTo(HOVER_TWEEN, 1) },
		}
	end

	if isActionButton(button) then
		local hoverScale = getScaleAttribute(button, HOVER_SCALE_ATTRIBUTE, ACTION_HOVER_SCALE)
		local pop = scaleTo(ACTION_POP_TWEEN, ACTION_POP_SCALE)
		local settle = scaleTo(ACTION_SETTLE_TWEEN, hoverScale)
		pop.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				settle:Play()
			end
		end)
		return {
			hover = { scaleTo(HOVER_TWEEN, hoverScale) },
			leave = { scaleTo(HOVER_TWEEN, 1) },
			press = { scaleTo(PRESS_TWEEN, getScaleAttribute(button, PRESS_SCALE_ATTRIBUTE, ACTION_PRESS_SCALE)) },
			release = { scaleTo(HOVER_TWEEN, hoverScale) },
			pop = { pop },
		}
	end

	local hoverScale = getScaleAttribute(button, HOVER_SCALE_ATTRIBUTE, HOVER_SCALE)
	return {
		hover = { scaleTo(HOVER_TWEEN, hoverScale) },
		leave = { scaleTo(HOVER_TWEEN, 1) },
		press = { scaleTo(PRESS_TWEEN, getScaleAttribute(button, PRESS_SCALE_ATTRIBUTE, PRESS_SCALE)) },
		release = { scaleTo(HOVER_TWEEN, hoverScale) },
	}
end

-- A white ring shaped like the button bursts out from it and fades.
local function playRing(button: GuiObject)
	local ring = Instance.new("Frame")
	ring.Name = "ClickRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1

	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = ring
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = RING_COLOR
	stroke.Thickness = RING_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	ring.Parent = button

	tweenService:Create(ring, RING_TWEEN, { Size = RING_GROW }):Play()
	local fade = tweenService:Create(stroke, RING_TWEEN, { Transparency = 1, Thickness = 0 })
	fade.Completed:Once(function()
		ring:Destroy()
	end)
	fade:Play()
end

-- PlayLocalSound's copy may not go through the UISounds group's volume, so the UI Sounds setting is checked here too.
local function playUISound(sound: Sound)
	if settings.get("UISounds") then
		soundService:PlayLocalSound(sound)
	end
end

local function play(button: GuiObject, name: string)
	local buttonTweens = tweens[button]
	if not buttonTweens or not buttonTweens[name] then
		return
	end
	for _, tween in buttonTweens[name] do
		tween:Play()
	end
end

--// Setup -------------------------------------------------------------------------------

-- Buttons, plus any other GuiObject tagged Rotate (e.g. an ImageLabel used as a button).
local function setupButton(button: GuiObject)
	if tweens[button] then
		return
	end

	if isMainHudButton(button) then
		collectionService:AddTag(button, ROTATE_TAG)
	end
	baseRotations[button] = button.Rotation
	tweens[button] = buildTweens(button)

	-- A Rotate attribute set later switches it between tilting and growing (tags: see the end of the script).
	button.AttributeChanged:Connect(function(name)
		if isRotateName(name) or name == ACTION_ATTRIBUTE or name == HOVER_SCALE_ATTRIBUTE or name == PRESS_SCALE_ATTRIBUTE then
			tweens[button] = buildTweens(button)
		end
	end)

	if isRotateButton(button) then
		debugLog(`rotate button set up: {button:GetFullName()} ({button.ClassName})`)
	end

	button.MouseEnter:Connect(function()
		hovered[button] = true
		play(button, "hover")
		playUISound(hoverSound)

		-- Ends at the base angle + HOVER_ROTATION unless another script is also setting Rotation.
		if DEBUG and isRotateButton(button) then
			debugLog(`hovering {button.Name}: Rotation {button.Rotation}`)
			task.delay(HOVER_TWEEN.Time + 0.1, function()
				debugLog(`{button.Name} after the tilt: Rotation {button.Rotation} (should be {(baseRotations[button] or 0) + HOVER_ROTATION})`)
			end)
		end
	end)

	button.MouseLeave:Connect(function()
		hovered[button] = nil
		play(button, "leave")
	end)

	if button:IsA("GuiButton") then
		button.Activated:Connect(function()
			playUISound(clickSound)
			-- Inactive buttons (e.g. the Index's Claim with nothing to claim) don't celebrate.
			if button.Active and isActionButton(button) then
				task.defer(play, button, "pop") -- after InputEnded's release, which would otherwise cut it short
				playRing(button)
			end
		end)
	end

	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			play(button, "press")
		end
	end)

	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			-- Touch never fires MouseLeave reliably, so a tap always settles back to rest.
			hovered[button] = nil
			play(button, "leave")
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and hovered[button] then
			play(button, "release")
		end
	end)

	button.Destroying:Connect(function()
		tweens[button] = nil
		hovered[button] = nil
		baseRotations[button] = nil
	end)
end

local function trySetup(descendant: Instance)
	if descendant:IsA("GuiButton") or (descendant:IsA("GuiObject") and isRotateButton(descendant)) then
		setupButton(descendant)
	end
end

for _, descendant in playerGui:GetDescendants() do
	trySetup(descendant)
end

playerGui.DescendantAdded:Connect(trySetup)

-- A window closed under the cursor (e.g. by a Prestige) never fires MouseLeave, so the button would stay tilted.
runService.Heartbeat:Connect(function()
	for button in hovered do
		if not isShown(button) then
			hovered[button] = nil
			play(button, "leave")
		end
	end
end)

-- Tagged or untagged after setup: rebuilt so it switches between tilting and growing.
local function onTagChanged(instance: Instance)
	if not instance:IsA("GuiObject") or not instance:IsDescendantOf(playerGui) then
		return
	end
	if tweens[instance] then
		tweens[instance] = buildTweens(instance)
	else
		trySetup(instance)
	end
end

for _, tag in { ROTATE_TAG, ROTATE_TAG:lower() } do
	collectionService:GetInstanceAddedSignal(tag):Connect(onTagChanged)
	collectionService:GetInstanceRemovedSignal(tag):Connect(onTagChanged)
end

-- Tags that look like Rotate but aren't spelled "Rotate" (e.g. "Rotation") are ignored, so they're listed here.
if DEBUG then
	local rotateCount = 0
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiObject") and tweens[descendant] and isRotateButton(descendant) then
			rotateCount += 1
		end
		for _, tag in descendant:GetTags() do
			if tag:lower():find("rotat") and not isRotateName(tag) then
				debugLog(`ignored tag "{tag}" on {descendant:GetFullName()}: rename it to "{ROTATE_TAG}"`)
			end
		end
	end
	debugLog(`{rotateCount} rotate buttons found in PlayerGui`)
end
