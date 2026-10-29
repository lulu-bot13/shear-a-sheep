--[[
	Hover and press animations and sounds for every UI button: "Rotate" buttons tilt, the rest grow.
	Each button's tweens are kept in the tweens table and rebuilt only when its Rotate tag changes.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ButtonClient
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local collectionService = game:GetService("CollectionService")
local soundService = game:GetService("SoundService")
local runService = game:GetService("RunService")

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
local DEBUG = false

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

local function getScale(button: GuiObject): UIScale
	local scale = button:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	return scale :: UIScale
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

	return {
		hover = { scaleTo(HOVER_TWEEN, HOVER_SCALE) },
		leave = { scaleTo(HOVER_TWEEN, 1) },
		press = { scaleTo(PRESS_TWEEN, PRESS_SCALE) },
		release = { scaleTo(HOVER_TWEEN, HOVER_SCALE) },
	}
end

local function play(button: GuiObject, name: string)
	local buttonTweens = tweens[button]
	if not buttonTweens then
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
		if isRotateName(name) then
			tweens[button] = buildTweens(button)
		end
	end)

	if isRotateButton(button) then
		debugLog(`rotate button set up: {button:GetFullName()} ({button.ClassName})`)
	end

	button.MouseEnter:Connect(function()
		hovered[button] = true
		play(button, "hover")
		soundService:PlayLocalSound(hoverSound)

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
			soundService:PlayLocalSound(clickSound)
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
