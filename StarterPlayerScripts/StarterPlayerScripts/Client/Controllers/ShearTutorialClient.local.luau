--[[
	First-shear tutorial for players who skipped it in the main tutorial: ToShop button, then the shear's UNLOCK button in the shop.
	Only the first shear unlocked gets it; later unlocks (once any shear past the default is owned) don't.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearTutorialClient
]]--

--// Services
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

--// Modules
local screenScale = require(script.Parent.Parent.Modules.ScreenScale)
local spotlightUI = require(script.Parent.Parent.Modules.SpotlightUI)
local UIData = require(script.Parent.Parent.Modules.ShearShopUIData)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local tutorialFrame = tutorialGui:WaitForChild("TutorialFrame") :: GuiObject
local tutorialText = tutorialFrame:WaitForChild("TutorialText") :: TextLabel
local tutorialProgression = tutorialFrame:WaitForChild("TutorialProgression") :: TextLabel
local spotlightFrame = tutorialGui:WaitForChild("Spotlight") :: GuiObject
local shopGui = playerGui:WaitForChild("Shop") :: ScreenGui
local scrollFrame = shopGui:WaitForChild("Main"):WaitForChild("ScrollingFrame") :: ScrollingFrame

--// Configs
local UNLOCKED_ATTRIBUTE = "UnlockedShear" -- set on the Shop gui by ShearShopClient to the highest shear just unlocked
local ACTIVE_ATTRIBUTE = "ShearTutorialActive" -- on the Tutorial gui while this runs, so DailyRewardClient and CrookTutorialClient wait
local MAIN_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local CROOK_ACTIVE_ATTRIBUTE = "CrookTutorialActive" -- set on the Tutorial gui by CrookTutorialClient while it runs
local TO_SHOP_BUTTON_NAME = "ToShop" -- in Main; NavigationClient teleports to the plaza from it
local SHOP_WINDOW = "ShearShop"
local DEFAULT_SHEAR_ID = "DefaultShear"
local DISPLAY_ORDER = 90 -- matches TutorialClient
local TICK_SECONDS = 0.1
local BLOCKED_RETRY_SECONDS = 1 -- how often a waiting unlock checks whether the other tutorials are out of the way
local SCROLL_DELAY = 0.25 -- after the shop opens, so its pop-in has finished before the card is measured
local SCROLL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STEP_COUNT = 3

--// Click hint: the same tapping hand, ripple and CLICK / TAP word as TutorialClient's
local HINT_Z_INDEX = 50
local HAND_SIZE = 72
local HAND_GAP = -6 -- below 0 the emoji's padding overlaps the target, so the fingertip lands on it
local HAND_TRAVEL = 12
local BUTTON_TAP_DEPTH = 0.3 -- how far down the button the fingertip lands, of its height
local HINT_LABEL_SIZE = Vector2.new(170, 40)
local TAP_IN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAP_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAP_PAUSE = 0.55
local LABEL_PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RIPPLE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RIPPLE_SIZE = 90
local RIPPLE_COLOR = Color3.fromRGB(255, 255, 255)

--// State
local hint: Frame? = nil
local hintLabel: TextLabel? = nil
local hintTarget: GuiObject? = nil
local hintRipplePoint = Vector2.zero
local focused: GuiObject? = nil -- what the spotlight was last tweened over, and where it was
local focusedPosition, focusedSize = Vector2.zero, Vector2.zero

--// Helpers -------------------------------------------------------------------------

-- The "OwnedShears" attribute is "DefaultShear,SteelShears" (set by ShearShopHandler).
local function isOwned(id: string): boolean
	local owned = player:GetAttribute("OwnedShears")
	if type(owned) ~= "string" then
		return id == DEFAULT_SHEAR_ID
	end
	for ownedId in string.gmatch(owned, "[^,]+") do
		if ownedId == id then
			return true
		end
	end
	return false
end

-- True once any shear besides the default is owned: the player has already been through a shear unlock.
local function ownsBetterShear(): boolean
	local owned = player:GetAttribute("OwnedShears")
	if type(owned) ~= "string" then
		return false
	end
	for ownedId in string.gmatch(owned, "[^,]+") do
		if ownedId ~= DEFAULT_SHEAR_ID then
			return true
		end
	end
	return false
end

local function getShearInfo(id: string): UIData.ShearUI?
	for _, info in UIData.Shears do
		if info.id == id then
			return info
		end
	end
	return nil
end

-- False while the object, one of its parents or its ScreenGui is hidden.
local function isShown(guiObject: GuiObject): boolean
	local gui = guiObject:FindFirstAncestorOfClass("ScreenGui")
	if not gui or not gui.Enabled then
		return false
	end

	local current: Instance? = guiObject
	while current and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- Looked up each time, since Main is rebuilt on respawn.
local function getHudButton(): GuiButton?
	local main = playerGui:FindFirstChild("Main")
	local button = main and main:FindFirstChild(TO_SHOP_BUTTON_NAME)
	return if button and button:IsA("GuiButton") then button else nil
end

local function getHintWord(): string
	return if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then "TAP!" else "CLICK!"
end

local function setStep(step: number, text: string)
	tutorialProgression.Text = `{step}/{STEP_COUNT}`
	tutorialText.Text = text
end

--// Click hint ----------------------------------------------------------------------

local function spawnRipple(position: Vector2)
	local ring = Instance.new("Frame")
	ring.Name = "ShearTutorialRipple"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	local size = RIPPLE_SIZE * screenScale.get()
	ring.Position = UDim2.fromOffset(position.X, position.Y)
	ring.Size = UDim2.fromOffset(size * 0.15, size * 0.15)
	ring.BackgroundColor3 = RIPPLE_COLOR
	ring.BackgroundTransparency = 0.6
	ring.ZIndex = HINT_Z_INDEX + 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = RIPPLE_COLOR
	stroke.Thickness = 4
	stroke.Parent = ring

	ring.Parent = tutorialGui
	tweenService:Create(ring, RIPPLE_TWEEN, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }):Play()
	tweenService:Create(stroke, RIPPLE_TWEEN, { Transparency = 1, Thickness = 1 }):Play()
	debris:AddItem(ring, RIPPLE_TWEEN.Time + 0.1)
end

-- A zero-size frame placed on the target, holding the hand above it and the word above that; it taps until destroyed.
local function createHint()
	local frame = Instance.new("Frame")
	frame.Name = "ShearTutorialHint"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(0, 0)
	frame.ZIndex = HINT_Z_INDEX
	frame.Visible = false
	frame.Parent = tutorialGui
	screenScale.attach(frame) -- the hand and word are sized in pixels for a ~1000 px tall screen

	local hand = Instance.new("TextLabel")
	hand.Name = "Hand"
	hand.BackgroundTransparency = 1
	hand.AnchorPoint = Vector2.new(0.5, 1)
	hand.Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE)
	hand.Font = Enum.Font.GothamBold
	hand.TextScaled = true
	hand.Text = "👇"
	hand.ZIndex = HINT_Z_INDEX + 2
	hand.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Action"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromOffset(0, -(HAND_GAP + HAND_SIZE + HINT_LABEL_SIZE.Y / 2))
	label.Size = UDim2.fromOffset(HINT_LABEL_SIZE.X, HINT_LABEL_SIZE.Y)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.ZIndex = HINT_Z_INDEX + 2
	label.Parent = frame

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = Color3.fromRGB(40, 30, 10)
	labelStroke.Thickness = 3
	labelStroke.Parent = label

	local labelScale = Instance.new("UIScale")
	labelScale.Parent = label
	tweenService:Create(labelScale, LABEL_PULSE, { Scale = 1.15 }):Play()

	hint, hintLabel = frame, label

	task.spawn(function()
		local rest, pressed = UDim2.fromOffset(0, -(HAND_GAP + HAND_TRAVEL)), UDim2.fromOffset(0, -HAND_GAP)
		while frame.Parent do
			if not frame.Visible then
				task.wait(TICK_SECONDS)
				continue
			end
			hand.Position = rest
			tweenService:Create(hand, TAP_IN, { Position = pressed }):Play()
			task.wait(TAP_IN.Time)
			if frame.Visible then
				spawnRipple(hintRipplePoint)
			end
			tweenService:Create(hand, TAP_OUT, { Position = rest }):Play()
			task.wait(TAP_OUT.Time + TAP_PAUSE)
		end
	end)
end

local function destroyHint()
	if hint then
		hint:Destroy()
	end
	hint, hintLabel, hintTarget = nil, nil, nil
end

local function setHint(target: GuiObject?)
	hintTarget = target
end

-- Runs every frame: keeps the hand on its target, hidden while the target isn't shown.
local function updateHint()
	local frame, label, target = hint, hintLabel, hintTarget
	if not frame or not label then
		return
	end
	if not target or not isShown(target) then
		frame.Visible = false
		return
	end

	local position, size = target.AbsolutePosition, target.AbsoluteSize
	frame.Position = UDim2.fromOffset(position.X + size.X / 2, position.Y + size.Y * BUTTON_TAP_DEPTH)
	hintRipplePoint = position + size / 2
	label.Text = getHintWord()
	frame.Visible = true
end

--// Spotlight and scrolling -----------------------------------------------------------

-- Spotlights the GuiObject; nil clears it. FocusUI measures once, so it's called again whenever the target moves.
local function point(target: GuiObject?)
	if target and isShown(target) then
		if target ~= focused or target.AbsolutePosition ~= focusedPosition or target.AbsoluteSize ~= focusedSize then
			focused, focusedPosition, focusedSize = target, target.AbsolutePosition, target.AbsoluteSize
			spotlightUI:FocusUI(target)
		end
	elseif focused then
		focused = nil
		spotlightUI:Cleanup()
	end
end

--[[
	Tweens the shop's list so the card's centre lines up with the visible area's centre, clamped to the canvas' scroll range.
	Absolute sizes are screen pixels; dividing by the window's UIScale factor turns them into CanvasPosition offsets.
	Works for a UIListLayout or UIGridLayout either way, since it only reads where the card actually is.
]]
local function scrollToCard(card: GuiObject): Tween
	local factor = math.max(windowsManager.getScaleFactor(scrollFrame), 0.01)
	local windowSize = scrollFrame.AbsoluteWindowSize
	local cardCenter = card.AbsolutePosition + card.AbsoluteSize / 2
	local windowCenter = scrollFrame.AbsolutePosition + windowSize / 2
	local maxPosition = (scrollFrame.AbsoluteCanvasSize - windowSize) / factor
	local target = scrollFrame.CanvasPosition + (cardCenter - windowCenter) / factor

	local goal = Vector2.new(
		math.clamp(target.X, 0, math.max(maxPosition.X, 0)),
		math.clamp(target.Y, 0, math.max(maxPosition.Y, 0))
	)
	local tween = tweenService:Create(scrollFrame, SCROLL_TWEEN, { CanvasPosition = goal })
	tween:Play()
	return tween
end

--// Steps -------------------------------------------------------------------------------

-- Step 1: press ToShop. Step 2: walk into the shop, which opens and scrolls to the card. Step 3: press its UNLOCK button.
local function run(info: UIData.ShearUI, card: GuiObject, purchase: GuiButton)
	local window = windowsManager.get(SHOP_WINDOW)
	local pressed = false
	local teleported = false
	local shopSeenAt: number? = nil
	local scrollTween: Tween? = nil
	local hookedButton: GuiButton? = nil
	local teleportConnection: RBXScriptConnection? = nil

	tutorialGui:SetAttribute(ACTIVE_ATTRIBUTE, true)
	tutorialGui.DisplayOrder = DISPLAY_ORDER
	tutorialGui.Enabled = true
	tutorialFrame.Visible = true
	createHint()

	local renderConnection = runService.RenderStepped:Connect(updateHint)
	local pressConnection = purchase.Activated:Connect(function()
		pressed = true
	end)

	while not pressed and not isOwned(info.id) do
		if not window or not window.isOpen() then
			if shopSeenAt then
				break -- closed without pressing UNLOCK
			end
			local button = getHudButton()
			if button ~= hookedButton then
				if teleportConnection then
					teleportConnection:Disconnect()
				end
				hookedButton = button
				teleportConnection = if button then button.Activated:Connect(function()
					teleported = true
				end) else nil
			end
			if teleported then
				setStep(2, `Walk into the Shear Shop to see the {info.displayName}!`)
				point(nil)
				setHint(nil)
			else
				setStep(1, `New shear unlocked: {info.displayName}! Press the button to go to the Shear Shop`)
				point(button)
				setHint(button)
			end
		elseif not shopSeenAt then
			shopSeenAt = os.clock()
			setStep(2, `Here are the {info.displayName}!`)
			point(nil)
			setHint(nil)
		elseif not scrollTween then
			if os.clock() - (shopSeenAt :: number) >= SCROLL_DELAY then
				scrollTween = scrollToCard(card)
			end
		elseif scrollTween.PlaybackState == Enum.PlaybackState.Completed then
			setStep(3, `Press UNLOCK to get the {info.displayName}!`)
			point(purchase)
			setHint(purchase)
		end
		task.wait(TICK_SECONDS)
	end

	pressConnection:Disconnect()
	renderConnection:Disconnect()
	if teleportConnection then
		teleportConnection:Disconnect()
	end
	if scrollTween then
		scrollTween:Cancel()
	end
	point(nil)
	destroyHint()
	spotlightFrame.Visible = false
	tutorialFrame.Visible = false
	tutorialGui.Enabled = false
	tutorialGui:SetAttribute(ACTIVE_ATTRIBUTE, false)
end

-- After the main tutorial, and never over the Crook tutorial.
local function canStart(): boolean
	return tutorialGui:GetAttribute(MAIN_DONE_ATTRIBUTE) == true and tutorialGui:GetAttribute(CROOK_ACTIVE_ATTRIBUTE) ~= true
end

--// Lifecycle ---------------------------------------------------------------------------

-- One unlock waits at a time; a newer (higher) unlock replaces it. It's cleared on starting, so a closed shop doesn't bring it back.
while true do
	local id = shopGui:GetAttribute(UNLOCKED_ATTRIBUTE)
	if type(id) ~= "string" then
		shopGui:GetAttributeChangedSignal(UNLOCKED_ATTRIBUTE):Wait()
	elseif not canStart() then
		task.wait(BLOCKED_RETRY_SECONDS)
	else
		shopGui:SetAttribute(UNLOCKED_ATTRIBUTE, nil)
		local info = getShearInfo(id)
		local card = scrollFrame:FindFirstChild(id)
		local purchase = card and card:FindFirstChild("Purchase")
		if info and not isOwned(id) and not ownsBetterShear() and card and card:IsA("GuiObject") and purchase and purchase:IsA("GuiButton") then
			run(info, card, purchase)
		end
	end
end
