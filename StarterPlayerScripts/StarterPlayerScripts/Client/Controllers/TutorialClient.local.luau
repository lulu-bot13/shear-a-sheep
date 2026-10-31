--[[
	First-play tutorial: shear a Huge sheep and 2 more, buy More Wool twice and Capacity, shear for the rebirth, rebirth, claim in the Index, then a tour of the buttons.
	A tapping hand shows where to click, every click ripples, and the steps up to the rebirth are worked out from the player's progress so they resume after a rejoin.
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local guiService = game:GetService("GuiService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local spotlightUI = require(script.Parent.Parent.Modules.SpotlightUI)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local tutorialMain = tutorialGui:WaitForChild("Main") :: GuiObject
local tutorialFrame = tutorialMain:WaitForChild("TutorialFrame") :: GuiObject
local tutorialText = tutorialFrame:WaitForChild("TutorialText") :: TextLabel
local tutorialProgression = tutorialFrame:WaitForChild("TutorialProgression") :: TextLabel
local spotlightFrame = tutorialGui:WaitForChild("Spotlight") :: GuiObject
local darkOverlay = tutorialGui:WaitForChild("DarkOverlay") :: GuiObject
local completedLabel = tutorialGui:WaitForChild("TutorialCompletedLabel") :: GuiObject
local tip = tutorialGui:WaitForChild("Tip") :: GuiObject
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local upgradesButton = hudButtons:WaitForChild("Upgrades") :: GuiButton
local rebirthHudButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local indexHudButton = hudButtons:WaitForChild("Index") :: GuiButton
local indexMain = playerGui:WaitForChild("Index"):WaitForChild("Main")
local indexClaimButton = indexMain:FindFirstChild("RewardsFrame", true):WaitForChild("Claim") :: GuiButton
local indexClaimAllButton = indexMain:WaitForChild("ClaimAllFrame"):WaitForChild("Claim") :: GuiButton
local indexExit = indexMain:FindFirstChild("Exit", true) :: GuiObject?
local upgradeShopMain = playerGui:WaitForChild("UpgradeShop"):WaitForChild("Main")
local upgradeCards = upgradeShopMain:WaitForChild("ScrollingFrame")
local upgradeShopExit = upgradeShopMain:FindFirstChild("Exit", true) :: GuiObject? -- found the same way WindowsManager wires it
local rebirthButton = playerGui:WaitForChild("RebirthScreen"):WaitForChild("Main"):WaitForChild("Rebirth") :: GuiButton
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue
local beamTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("TutorialBeam") :: Beam
local uiSounds = soundService:FindFirstChild("UISounds")
local stepSound = uiSounds and (uiSounds:FindFirstChild("LuckClaimed") or uiSounds:FindFirstChild("Click")) :: Sound?

--// Configs
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local SHEAR_RANGE_ATTRIBUTE = "ShearRange" -- only shear Tools have it
local NEAR_DISTANCE = 8 -- studs (flat) from a sheep that count as "at" it
local LEAVE_DISTANCE = 12 -- studs (flat) the first sheep is walked away from before the beam leads back to a sheep
local ALWAYS_IN_STUDIO = true -- runs the tutorial in Studio even on a save that has rebirthed
local TICK_SECONDS = 0.1
local DISPLAY_ORDER = 90 -- the text and spotlight draw over every window (Alerts are 100)
local STATE_REQUEST_SECONDS = 2 -- re-asks the server for upgrade / rebirth state until it arrives
local COMPLETED_SECONDS = 3 -- how long the completed label stays up
local SHEEP_TO_SHEAR = 3 -- counting the first sheep
local IDLE_HINT_SECONDS = 2.5 -- after the first sheep, the tapping hand comes back once the player stops clicking this long
-- The upgrades bought in order in one shop visit, each with why it helps; 45 + 76 + 40 wool, which the starter wool and the first 3 sheep cover.
local TUTORIAL_UPGRADES = {
	{ id = "MoreWool", text = "Press +1 on More Wool. Every Sheep gives you more Wool!" },
	{ id = "MoreWool", text = "Press +1 on More Wool again. Upgrades stack up!" },
	{ id = "Capacity", text = "Now buy Sheep Capacity. More Sheep fit on your farm!" },
}
local KEEP_HUD_BUTTONS = { Upgrades = true, Rebirth = true } -- the only HUD buttons shown until the Index stage
local HIDE_UI_STAGES = { EquipShears = true, GoToSheep = true, FirstShear = true, Shear = true } -- every ScreenGui but the tutorial's is off during these
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- Every stage in order; TutorialProgression shows the current one as "3/9". The cheer plays on reaching a stage.
local STAGES = { "EquipShears", "GoToSheep", "FirstShear", "Shear", "Upgrades", "CloseUpgrades", "Rebirth", "Index", "Explain" }
local STAGE_ORDER: { [string]: number } = {}
for index, name in STAGES do
	STAGE_ORDER[name] = index
end
local STAGE_CHEERS = {
	GoToSheep = "Shears ready!",
	Shear = "First Sheep sheared!",
	Upgrades = "Wool collected!",
	CloseUpgrades = "Upgrades bought!",
	Index = "Rebirthed!",
	Explain = "Luck claimed!",
}
-- The closing tour: one button and one sentence each, EXPLAIN_SECONDS apiece.
local EXPLAIN_SECONDS = 4
local EXPLAIN_STEPS = {
	{ button = indexHudButton, text = "Index: every Sheep type you shear is saved here, with Luck to claim." },
	{ button = rebirthHudButton, text = "Rebirth: trade Wool for a Luck boost, so rarer Sheep spawn." },
	{ button = upgradesButton, text = "Upgrades: spend Wool to earn Wool faster and fit more Sheep." },
}
local TUTORIAL_SHEEP_ATTRIBUTE = "TutorialSheep" -- set by TutorialHandler on the Huge sheep it drops for the first shear

--// Rebirth progress bar, under the instruction box while the player shears for the rebirth
local BAR_HEIGHT = 26
local BAR_GAP = 24 -- pixels between the bottom of the instruction box and the bar
local BAR_WIDTH_SCALE = 0.85 -- of the instruction box's width
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_BACK_COLOR = Color3.fromRGB(40, 35, 30)
local BAR_FILL_COLOR = Color3.fromRGB(255, 215, 80)
local BAR_MILESTONES = { { ratio = 0.5, text = "Halfway there!" }, { ratio = 0.8, text = "Almost there!" } }

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_ATTACHMENT_ROTATION = Vector3.new(0, 0, 90) -- degrees, applied to both beam ends
local HOTBAR_SLOT_SIZE = 60 -- pixels, Roblox's default hotbar
local HOTBAR_SLOT_GAP = 5
local HOTBAR_BOTTOM_GAP = 5

--// Click hint: a hand that taps the target, a ripple on each tap and a pulsing CLICK / TAP word
local HINT_Z_INDEX = 50
local HAND_SIZE = 72
local HAND_GAP = -6 -- pixels between the target point and the hand's edge; below 0 the emoji's padding overlaps it, so the fingertip lands on it
local HAND_TRAVEL = 12 -- how far the hand moves in on each tap
local BUTTON_TAP_DEPTH = 0.3 -- how far down a button the fingertip lands, of its height (the ripple is at its centre)
local HINT_LABEL_SIZE = Vector2.new(170, 40)
local HINT_FALLBACK = Vector2.new(0.5, 0.62) -- of the screen, when the target sheep is off-screen
local TAP_IN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAP_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAP_PAUSE = 0.55
local LABEL_PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RIPPLE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HINT_RIPPLE_SIZE = 90
local CLICK_RIPPLE_SIZE = 120
local RIPPLE_COLOR = Color3.fromRGB(255, 255, 255)
local TEXT_BUMP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local TEXT_BUMP_SCALE = 1.08
local CHEER_RISE = 60
local CHEER_TWEEN = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CHEER_COLOR = Color3.fromRGB(120, 255, 120)

type Stage = "EquipShears" | "GoToSheep" | "FirstShear" | "Shear" | "Upgrades" | "CloseUpgrades" | "Rebirth" | "Index" | "Explain" | "Done"
type InputMode = "Mouse" | "Touch" | "Gamepad"

--// State
local stage: Stage = "EquipShears"
local shearedBaseline = 0 -- SheepShearedCount the "Shear 3 Sheep" progress counts up from
local hiddenHudButtons: { GuiObject } = {}
local hiddenGuis: { ScreenGui } = {}
local popFullScales: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any -- each popped object's full size, read before its first pop (cheer labels come and go)
local upgradeStates: { [string]: any }? = nil -- UpgradeState cards by id
local rebirthCost: number? = nil
local nextStateRequest = 0
local highlights: { [Model]: Highlight } = {}
local beamSheep: Model? = nil -- the sheep the beam leads to
local firstSheep: Model? = nil -- the sheep "Click To Shear" shows the health of
local beamConnection: RBXScriptConnection? = nil
local inputConnection: RBXScriptConnection? = nil
local focused: GuiObject? = nil -- what the spotlight was last tweened over, and where it was
local focusedPosition, focusedSize = Vector2.zero, Vector2.zero
local hintTarget: (Model | GuiObject)? = nil -- what the tapping hand points at
local hintRipplePoint = Vector2.zero -- where the hand's taps ripple (the target's centre), in tutorialGui pixels
local lastClickAt = 0
local lastTextKey = ""
local stageStartedAt = 0
local barMilestone = 0 -- BAR_MILESTONES already cheered this Rebirth stage
local indexHasUnclaimed: boolean? = nil -- from IndexState; nil until it arrives

-- One beam cloned once and reused. Its ends stay in Terrain and are moved each frame,
-- so a respawned character or a replaced sheep can't destroy them.
local beamStart = Instance.new("Attachment")
beamStart.Name = "TutorialBeamStart"
beamStart.Orientation = BEAM_ATTACHMENT_ROTATION
beamStart.Parent = workspace.Terrain
local beamEnd = Instance.new("Attachment")
beamEnd.Name = "TutorialBeamEnd"
beamEnd.Orientation = BEAM_ATTACHMENT_ROTATION
beamEnd.Parent = workspace.Terrain

local beam = beamTemplate:Clone()
beam.Attachment0 = beamStart
beam.Attachment1 = beamEnd
beam.FaceCamera = false -- the ends' rotation sets which way the beam lies
beam.Enabled = false
beam.Parent = workspace.Terrain

-- The hotbar is CoreGui, so the spotlight points at this see-through stand-in sized over it.
local hotbarFrame = Instance.new("Frame")
hotbarFrame.Name = "TutorialHotbar"
hotbarFrame.BackgroundTransparency = 1
hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
hotbarFrame.Position = UDim2.new(0.5, 0, 1, -HOTBAR_BOTTOM_GAP)
hotbarFrame.Parent = spotlightFrame.Parent

--// Click hint instances: a zero-size frame placed on the target, holding the hand and the word.
local hint = Instance.new("Frame")
hint.Name = "TutorialClickHint"
hint.BackgroundTransparency = 1
hint.Size = UDim2.fromOffset(0, 0)
hint.ZIndex = HINT_Z_INDEX
hint.Visible = false
hint.Parent = tutorialGui

local hand = Instance.new("TextLabel")
hand.Name = "Hand"
hand.BackgroundTransparency = 1
hand.Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE)
hand.Font = Enum.Font.GothamBold
hand.TextScaled = true
hand.Text = "👆"
hand.ZIndex = HINT_Z_INDEX + 2
hand.Parent = hint

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Action"
hintLabel.BackgroundTransparency = 1
hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hintLabel.Size = UDim2.fromOffset(HINT_LABEL_SIZE.X, HINT_LABEL_SIZE.Y)
hintLabel.Font = Enum.Font.FredokaOne
hintLabel.TextScaled = true
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.ZIndex = HINT_Z_INDEX + 2
hintLabel.Parent = hint

local hintLabelStroke = Instance.new("UIStroke")
hintLabelStroke.Color = Color3.fromRGB(40, 30, 10)
hintLabelStroke.Thickness = 3
hintLabelStroke.Parent = hintLabel

local hintLabelScale = Instance.new("UIScale")
hintLabelScale.Parent = hintLabel
tweenService:Create(hintLabelScale, LABEL_PULSE, { Scale = 1.15 }):Play()

--// Rebirth progress bar: a back, a fill that grows to the wool owned, and "120 / 200 Wool" over both.
local progressBar = Instance.new("Frame")
progressBar.Name = "TutorialRebirthBar"
progressBar.AnchorPoint = Vector2.new(0.5, 0)
progressBar.BackgroundColor3 = BAR_BACK_COLOR
progressBar.ZIndex = HINT_Z_INDEX
progressBar.Visible = false
progressBar.Parent = tutorialGui

local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(0.5, 0)
progressCorner.Parent = progressBar

local progressStroke = Instance.new("UIStroke")
progressStroke.Color = Color3.fromRGB(20, 15, 10)
progressStroke.Thickness = 2
progressStroke.Parent = progressBar

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.BackgroundColor3 = BAR_FILL_COLOR
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.ZIndex = HINT_Z_INDEX + 1
progressFill.Parent = progressBar
progressCorner:Clone().Parent = progressFill

local progressText = Instance.new("TextLabel")
progressText.Name = "Amount"
progressText.BackgroundTransparency = 1
progressText.Size = UDim2.fromScale(1, 1)
progressText.Font = Enum.Font.FredokaOne
progressText.TextScaled = true
progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
progressText.ZIndex = HINT_Z_INDEX + 2
progressText.Parent = progressBar
progressStroke:Clone().Parent = progressText

--// Helpers -------------------------------------------------------------------------

local function getNumberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function getRoot(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function formatWool(value: number): string
	return numberFormatter:Format(math.floor(value), 1)
end

-- The player's sheep currently on their farm.
local function getOwnSheep(): { Model }
	local found: { Model } = {}
	for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
		if sheep:IsA("Model") and sheep:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
			and sheep:IsDescendantOf(workspace) and getRoot(sheep)
		then
			table.insert(found, sheep)
		end
	end
	return found
end

local function getFlatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The Huge sheep TutorialHandler dropped for the first shear, while it's on the farm.
local function getTutorialSheep(): Model?
	for _, sheep in getOwnSheep() do
		if sheep:GetAttribute(TUTORIAL_SHEEP_ATTRIBUTE) then
			return sheep
		end
	end
	return nil
end

local function isHoldingShear(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute(SHEAR_RANGE_ATTRIBUTE) ~= nil
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

local function isWindowOpen(name: string): boolean
	local window = windowsManager.get(name)
	return window ~= nil and window.isOpen()
end

local function formatHealth(value: number): string
	return numberFormatter:Format(math.ceil(value), 1)
end

-- What the player last used, so every instruction names the right button.
local function getInputMode(): InputMode
	local last = userInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(last.Name, "Gamepad") then
		return "Gamepad"
	elseif last == Enum.UserInputType.Keyboard or string.find(last.Name, "Mouse") then
		return "Mouse"
	end
	return if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then "Touch" else "Mouse"
end

-- "Click anywhere on the screen", "Tap anywhere on the screen" or "Press R2".
local function getShearAction(): string
	local mode = getInputMode()
	return if mode == "Touch" then "Tap anywhere on the screen"
		elseif mode == "Gamepad" then "Press R2"
		else "Click anywhere on the screen"
end

local function getEquipText(): string
	local mode = getInputMode()
	return if mode == "Touch" then "Tap your Shears at the bottom to hold them"
		elseif mode == "Gamepad" then "Press L1 or R1 to hold your Shears"
		else "Press 1 or click your Shears at the bottom to hold them"
end

local function getHintWord(): string
	local mode = getInputMode()
	return if mode == "Touch" then "TAP!" elseif mode == "Gamepad" then "R2!" else "CLICK!"
end

-- Offsets between a ScreenGui's pixels and the viewport (WorldToViewportPoint) / input positions, which differ by the top bar.
local function getGuiInset(): Vector2
	return (guiService:GetGuiInset())
end

local function viewportToGui(point: Vector2): Vector2
	return if tutorialGui.IgnoreGuiInset then point else point - getGuiInset()
end

local function inputToGui(point: Vector2): Vector2
	return if tutorialGui.IgnoreGuiInset then point + getGuiInset() else point
end

--// Pops --------------------------------------------------------------------------------

-- The object's UIScale and the size it pops up to; a Studio-built UIScale keeps its value as the full size, otherwise one is added at 1.
local function getPopScale(guiObject: GuiObject): (UIScale, number)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = guiObject
	end
	local uiScale = scale :: UIScale
	local fullScale = popFullScales[uiScale] or uiScale.Scale
	popFullScales[uiScale] = fullScale
	return uiScale, fullScale
end

local function popIn(guiObject: GuiObject)
	local uiScale, fullScale = getPopScale(guiObject)
	uiScale.Scale = 0
	guiObject.Visible = true
	tweenService:Create(uiScale, POP_IN, { Scale = fullScale }):Play()
end

-- Yields until the object has shrunk away, then hides it.
local function popOut(guiObject: GuiObject)
	local uiScale, fullScale = getPopScale(guiObject)
	local tween = tweenService:Create(uiScale, POP_OUT, { Scale = 0 })
	tween:Play()
	tween.Completed:Wait()
	guiObject.Visible = false
	uiScale.Scale = fullScale
end

-- Shows the instruction; the box bumps when the instruction itself changes (not just its numbers).
local function setText(text: string)
	tutorialText.Text = text

	local key = string.gsub(text, "%d", "")
	if key ~= lastTextKey then
		lastTextKey = key
		local uiScale, fullScale = getPopScale(tutorialFrame)
		uiScale.Scale = fullScale
		tweenService:Create(uiScale, TEXT_BUMP, { Scale = fullScale * TEXT_BUMP_SCALE }):Play()
	end
end

--// Ripples and the click hint -------------------------------------------------------

-- An expanding, fading ring at `position` (tutorialGui pixels).
local function spawnRipple(position: Vector2, size: number)
	local ring = Instance.new("Frame")
	ring.Name = "TutorialRipple"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
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

-- Points the tapping hand at a sheep (the hand sits under it) or a GuiObject (the hand sits above it); nil hides it.
local function setHint(target: (Model | GuiObject)?)
	hintTarget = target
end

--[[
	Where the hand's fingertip goes, where its taps ripple and whether it comes from above; nil when the target can't be placed.
	A button is tapped a little way down from its top edge and ripples from its centre, so both land on the button itself.
]]
local function getHintPoint(): (Vector2?, Vector2, boolean)
	local target = hintTarget
	if not target then
		return nil, Vector2.zero, false
	end

	if target:IsA("GuiObject") then
		if not isShown(target) then
			return nil, Vector2.zero, false
		end
		local position, size = target.AbsolutePosition, target.AbsoluteSize
		return position + Vector2.new(size.X / 2, size.Y * BUTTON_TAP_DEPTH), position + size / 2, true
	end

	local root = getRoot(target :: Model)
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return nil, Vector2.zero, false
	end
	local viewportPoint, onScreen = camera:WorldToViewportPoint(root.Position)
	local point = if onScreen
		then viewportToGui(Vector2.new(viewportPoint.X, viewportPoint.Y))
		else tutorialGui.AbsoluteSize * HINT_FALLBACK
	return point, point, false
end

-- Runs every frame: keeps the hand on its target.
local function updateHint()
	local point, ripplePoint, fromAbove = getHintPoint()
	if not point then
		hint.Visible = false
		return
	end

	hintRipplePoint = ripplePoint
	hint.Position = UDim2.fromOffset(point.X, point.Y)
	hintLabel.Text = getHintWord()
	if fromAbove then
		hand.Text = "👇"
		hand.AnchorPoint = Vector2.new(0.5, 1)
		hintLabel.Position = UDim2.fromOffset(0, -(HAND_GAP + HAND_SIZE + HINT_LABEL_SIZE.Y / 2))
	else
		hand.Text = "👆"
		hand.AnchorPoint = Vector2.new(0.5, 0)
		hintLabel.Position = UDim2.fromOffset(0, HAND_GAP + HAND_SIZE + HINT_LABEL_SIZE.Y / 2)
	end
	hint.Visible = true
end

-- The hand's resting offset from the fingertip point, and the offset it taps in to.
local function getHandOffsets(): (UDim2, UDim2)
	local direction = if hand.AnchorPoint.Y > 0.5 then -1 else 1
	return UDim2.fromOffset(0, direction * (HAND_GAP + HAND_TRAVEL)), UDim2.fromOffset(0, direction * HAND_GAP)
end

-- Taps the hand in and out forever, rippling at the fingertip on each tap.
task.spawn(function()
	while hint.Parent do
		if not hint.Visible then
			task.wait(TICK_SECONDS)
			continue
		end

		local rest, pressed = getHandOffsets()
		hand.Position = rest
		tweenService:Create(hand, TAP_IN, { Position = pressed }):Play()
		task.wait(TAP_IN.Time)
		if hint.Visible then
			spawnRipple(hintRipplePoint, HINT_RIPPLE_SIZE)
		end
		tweenService:Create(hand, TAP_OUT, { Position = rest }):Play()
		task.wait(TAP_OUT.Time + TAP_PAUSE)
	end
end)

-- Every click, tap or R2 press while holding the shears ripples where it landed, so the player sees it counted.
local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed or stage == "Done" or not isHoldingShear() then
		return
	end

	local inputType = input.UserInputType
	if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
		lastClickAt = os.clock()
		local position = input.Position
		spawnRipple(inputToGui(Vector2.new(position.X, position.Y)), CLICK_RIPPLE_SIZE)
	elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
		lastClickAt = os.clock()
		spawnRipple(if hint.Visible then hintRipplePoint else tutorialGui.AbsoluteSize * HINT_FALLBACK, CLICK_RIPPLE_SIZE)
	end
end

-- A green "Shears ready!" that floats up from under the instruction box and fades.
local function cheer(text: string)
	if stepSound then
		stepSound:Play()
	end

	local label = Instance.new("TextLabel")
	label.Name = "TutorialCheer"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Size = UDim2.fromOffset(320, 44)
	label.Position = UDim2.fromOffset(
		tutorialFrame.AbsolutePosition.X + tutorialFrame.AbsoluteSize.X / 2,
		tutorialFrame.AbsolutePosition.Y + tutorialFrame.AbsoluteSize.Y + 8
	)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = `✔ {text}`
	label.TextColor3 = CHEER_COLOR
	label.ZIndex = HINT_Z_INDEX + 3

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 60, 20)
	stroke.Thickness = 3
	stroke.Parent = label

	label.Parent = tutorialGui
	popIn(label)
	tweenService:Create(label, CHEER_TWEEN, { Position = label.Position + UDim2.fromOffset(0, CHEER_RISE), TextTransparency = 1 }):Play()
	tweenService:Create(stroke, CHEER_TWEEN, { Transparency = 1 }):Play()
	debris:AddItem(label, CHEER_TWEEN.Time + 0.1)
end

--// Sheep highlights -----------------------------------------------------------------

-- Outlines exactly these sheep.
local function setHighlights(sheepList: { Model })
	local keep: { [Model]: boolean } = {}
	for _, sheep in sheepList do
		keep[sheep] = true
		if not highlights[sheep] then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TutorialHighlight"
			highlight.FillColor = HIGHLIGHT_COLOR
			highlight.OutlineColor = HIGHLIGHT_COLOR
			highlight.FillTransparency = 0.7
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = sheep
			highlight.Parent = workspace
			highlights[sheep] = highlight
		end
	end

	for sheep, highlight in highlights do
		if not keep[sheep] then
			highlight:Destroy()
			highlights[sheep] = nil
		end
	end
end

-- Runs every frame: draws the beam from the character to beamSheep (hidden when either is missing) and moves the hand.
local function updateBeam()
	updateHint()

	local playerRoot = getRoot(player.Character)
	local sheepRoot = getRoot(beamSheep)
	if not playerRoot or not sheepRoot then
		beam.Enabled = false
		return
	end

	beamStart.WorldPosition = playerRoot.Position
	beamEnd.WorldPosition = sheepRoot.Position
	beam.Enabled = true
end

-- Outlines every sheep and returns the closest one and whether the player is at it; when they aren't, the beam leads to it.
local function guideToSheep(): (Model?, boolean)
	local sheepList = getOwnSheep()
	setHighlights(sheepList)

	local playerRoot = getRoot(player.Character)
	if not playerRoot then
		return nil, false
	end
	local nearest, nearestDistance = nil, math.huge
	for _, sheep in sheepList do
		local distance = getFlatDistance(playerRoot.Position, (getRoot(sheep) :: BasePart).Position)
		if distance < nearestDistance then
			nearest, nearestDistance = sheep, distance
		end
	end

	if nearestDistance <= NEAR_DISTANCE then
		beamSheep = nil
		return nearest, true
	end
	-- The beam keeps its sheep while it's still around, so it doesn't flick between two at the same distance.
	if not beamSheep or not table.find(sheepList, beamSheep) then
		beamSheep = nearest
	end
	return nearest, false
end

--// Spotlight ---------------------------------------------------------------------------

-- Spotlights the GuiObject; nil clears it.
-- FocusUI only measures the target once, so it is called again whenever the target moves (e.g. a window popping in).
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

-- Sizes the hotbar stand-in to one slot per Tool the player has, then spotlights it.
local function pointAtHotbar()
	local toolCount = 0
	for _, container in { player:FindFirstChildOfClass("Backpack") or false, player.Character or false } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					toolCount += 1
				end
			end
		end
	end
	local slots = math.max(toolCount, 1)
	hotbarFrame.Size = UDim2.fromOffset(slots * HOTBAR_SLOT_SIZE + (slots - 1) * HOTBAR_SLOT_GAP, HOTBAR_SLOT_SIZE)
	point(hotbarFrame)
	setHint(hotbarFrame)
end

--// Stages ------------------------------------------------------------------------------

-- Turns off every ScreenGui but the tutorial's; run each tick, since respawned or newly opened guis come back on.
local function hideOtherGuis()
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= tutorialGui and gui.Enabled then
			gui.Enabled = false
			table.insert(hiddenGuis, gui)
		end
	end
end

local function showOtherGuis()
	for _, gui in hiddenGuis do
		gui.Enabled = true
	end
	table.clear(hiddenGuis)
end

-- `quiet` skips the cheer (the first stage, picked on join).
local function setStage(newStage: Stage, quiet: boolean?)
	local advanced = (STAGE_ORDER[newStage] or 0) > (STAGE_ORDER[stage] or 0)
	stage = newStage
	stageStartedAt = os.clock()
	barMilestone = 0
	setHighlights({})
	beamSheep = nil
	firstSheep = nil
	setHint(nil)
	point(nil)
	progressBar.Visible = false
	if STAGE_ORDER[newStage] then
		tutorialProgression.Text = `{STAGE_ORDER[newStage]}/{#STAGES}`
	end
	if HIDE_UI_STAGES[newStage] then
		hideOtherGuis()
	else
		showOtherGuis()
	end

	if advanced and not quiet and STAGE_CHEERS[newStage] then
		cheer(STAGE_CHEERS[newStage])
	end
	network.fireServer(network.RemoteEvents.AnalyticsEvent, "Tutorial", newStage)
end

-- Asks the server again for state the tutorial is still missing.
local function requestState(eventName: any)
	local now = os.clock()
	if now >= nextStateRequest then
		nextStateRequest = now + STATE_REQUEST_SECONDS
		network.fireServer(eventName)
	end
end

local function promptEquip()
	setText(getEquipText())
	pointAtHotbar()
end

-- Shearing for wool after the first sheep: the beam leads to the closest sheep, and once there the hand comes back if the player stops clicking.
local function guideShearing(nearText: string, farText: string)
	if not isHoldingShear() then
		promptEquip()
		return
	end
	point(nil)

	local nearest, near = guideToSheep()
	if near then
		setText(nearText)
		setHint(if os.clock() - lastClickAt >= IDLE_HINT_SECONDS then nearest else nil)
	else
		setText(farText)
		setHint(nil)
	end
end

-- "Equip Shears": the spotlight and hand sit on the hotbar until a shear is held out.
local function updateEquipShears()
	if isHoldingShear() then
		setStage("GoToSheep")
		return
	end
	promptEquip()
end

-- "Go to a Sheep": the beam leads to the Huge tutorial sheep, or to the closest sheep before it lands (or once it's gone).
local function updateGoToSheep()
	if not isHoldingShear() then
		setStage("EquipShears")
		return
	end

	local bigSheep = getTutorialSheep()
	local playerRoot = getRoot(player.Character)
	if bigSheep then
		setText("Walk to the HUGE glowing Sheep. Follow the arrow!")
		setHighlights({ bigSheep })
		beamSheep = bigSheep
		if playerRoot and getFlatDistance(playerRoot.Position, (getRoot(bigSheep) :: BasePart).Position) <= NEAR_DISTANCE then
			setStage("FirstShear")
			firstSheep = bigSheep
		end
		return
	end

	setText("Walk to a glowing Sheep. Follow the arrow!")
	local nearest, near = guideToSheep()
	if near then
		setStage("FirstShear")
		firstSheep = nearest
	end
end

-- "Click anywhere to shear ... (HP 60/100)": the hand taps the first sheep until it is shorn bare.
local function updateFirstShear()
	if getNumberAttribute("SheepShearedCount") > shearedBaseline then
		setStage("Shear")
		return
	end
	if not isHoldingShear() then
		setStage("EquipShears")
		return
	end

	local sheep = firstSheep
	local playerRoot = getRoot(player.Character)
	local sheepRoot = getRoot(sheep)
	if not sheep or not sheepRoot or not sheep:IsDescendantOf(workspace)
		or (playerRoot and getFlatDistance(playerRoot.Position, sheepRoot.Position) > LEAVE_DISTANCE)
	then
		setStage("GoToSheep")
		return
	end

	setHighlights({ sheep })
	setHint(sheep)
	local action = getShearAction()
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) == "number" and type(maxHealth) == "number" then
		setText(`{action} to shear! Keep going until its Wool is gone (HP {formatHealth(math.max(health, 0))}/{formatHealth(maxHealth)})`)
	else
		setText(`{action} to shear! Keep going until its Wool is gone`)
	end
end

-- "Shear 2 more Sheep ... 0/2": sheep shorn bare after the first one.
local function updateShear()
	local count = getNumberAttribute("SheepShearedCount")
	if count < shearedBaseline then
		shearedBaseline = count -- the data was reset (e.g. /resetdata), so count from the new total
	end
	local sheared = count - shearedBaseline
	if sheared >= SHEEP_TO_SHEAR then
		setStage("Upgrades")
		return
	end

	local remaining = SHEEP_TO_SHEAR - 1 -- the first sheep was the "Click to Shear" stage
	local progress = `({math.max(sheared - 1, 0)}/{remaining})`
	guideShearing(
		`Nice! {getShearAction()} to shear {remaining} more Sheep {progress}`,
		`Nice! Follow the arrow to the next Sheep {progress}`
	)
end

-- The TUTORIAL_UPGRADES step still to buy and its card, or nil once every step's level is owned (or maxed).
-- Counted from the cards' levels, so it resumes after a rejoin.
local function getUpgradeStep(): (number?, any)
	local needed: { [string]: number } = {}
	for index, step in TUTORIAL_UPGRADES do
		needed[step.id] = (needed[step.id] or 0) + 1
		local card = upgradeStates and upgradeStates[step.id]
		if card and card.cost and (card.level or 0) < needed[step.id] then
			return index, card
		end
	end
	return nil, nil
end

-- "Upgrade 1/3": opens the shop and buys each TUTORIAL_UPGRADES step; short on wool, it sends the player back to shearing.
local function updateUpgrades()
	if not upgradeStates then
		requestState(network.RemoteEvents.RequestUpgradeState)
		setText("Open Upgrades to spend your Wool")
		point(upgradesButton)
		setHint(upgradesButton)
		return
	end
	local index, card = getUpgradeStep()
	if not index then
		setStage("CloseUpgrades")
		return
	end

	local progress = `Upgrade {index}/{#TUTORIAL_UPGRADES}:`
	local shopOpen = isWindowOpen("UpgradeShop")
	if wool.Value < card.cost then
		if shopOpen then
			setHighlights({})
			beamSheep = nil
			setText(`{progress} Need more Wool! Close Upgrades to shear more`)
			point(upgradeShopExit)
			setHint(upgradeShopExit)
		else
			local counter = `({formatWool(wool.Value)}/{formatWool(card.cost)} Wool)`
			guideShearing(`{progress} {getShearAction()} to shear for more Wool {counter}`, `{progress} Follow the arrow to a Sheep for more Wool {counter}`)
		end
		return
	end

	setHighlights({})
	beamSheep = nil
	if not shopOpen then
		setText(`{progress} Open Upgrades. Upgrades make you earn Wool faster!`)
		point(upgradesButton)
		setHint(upgradesButton)
	else
		local cardFrame = upgradeCards:FindFirstChild(card.id)
		local purchase = cardFrame and cardFrame:FindFirstChild("Purchase")
		local target = if purchase and purchase:IsA("GuiObject") then purchase else nil
		setText(`{progress} {TUTORIAL_UPGRADES[index].text}`)
		point(target)
		setHint(target)
	end
end

local function updateCloseUpgrades()
	if not isWindowOpen("UpgradeShop") then
		setStage("Rebirth")
		return
	end
	setText("Great job! Close Upgrades")
	point(upgradeShopExit)
	setHint(upgradeShopExit)
end

-- Fills the bar under the instruction box with wool / cost, and cheers as it passes each BAR_MILESTONES ratio.
local function showRebirthProgress(cost: number)
	local frameSize = tutorialFrame.AbsoluteSize
	local framePosition = tutorialFrame.AbsolutePosition
	-- Below whichever ends lower, the box or its text (which can spill past it), so the bar never covers the instruction.
	local bottom = math.max(framePosition.Y + frameSize.Y, tutorialText.AbsolutePosition.Y + tutorialText.AbsoluteSize.Y)
	progressBar.Size = UDim2.fromOffset(frameSize.X * BAR_WIDTH_SCALE, BAR_HEIGHT)
	progressBar.Position = UDim2.fromOffset(framePosition.X + frameSize.X / 2, bottom + BAR_GAP)
	progressBar.Visible = true

	local ratio = math.clamp(wool.Value / cost, 0, 1)
	if progressFill.Size.X.Scale ~= ratio then
		tweenService:Create(progressFill, BAR_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
	progressText.Text = `{formatWool(wool.Value)} / {formatWool(cost)} Wool`

	local milestone = BAR_MILESTONES[barMilestone + 1]
	if milestone and ratio >= milestone.ratio then
		barMilestone += 1
		cheer(milestone.text)
	end
end

-- Gains wool up to the first rebirth's cost (with a progress bar), then opens the rebirth screen and presses Rebirth.
local function updateRebirth()
	local cost = rebirthCost
	if not cost then
		requestState(network.RemoteEvents.RequestRebirthState)
		setText("Shear Sheep for Wool to Rebirth")
		return
	end

	if wool.Value < cost then
		showRebirthProgress(cost)
		guideShearing(`{getShearAction()} to shear! Fill the bar to Rebirth`, "Follow the arrow to a Sheep. Fill the bar to Rebirth")
		return
	end

	progressBar.Visible = false
	setHighlights({})
	beamSheep = nil
	if not isWindowOpen("Rebirth") then
		setText("You have enough Wool! Open Rebirth")
		point(rebirthHudButton)
		setHint(rebirthHudButton)
	else
		setText("Press Rebirth! Luck brings rarer Sheep")
		point(rebirthButton)
		setHint(rebirthButton)
	end
end

-- Shows one of the HUD buttons the tutorial hid (the Index's, once it's taught).
local function showHudButton(button: GuiObject)
	local index = table.find(hiddenHudButtons, button)
	if index then
		table.remove(hiddenHudButtons, index)
	end
	button.Visible = true
end

-- After the rebirth: open the Index and claim the Luck waiting for the sheep found so far.
local function updateIndex()
	showHudButton(indexHudButton)
	if indexHasUnclaimed == nil then
		requestState(network.RemoteEvents.RequestIndexState)
	end

	if not isWindowOpen("Index") then
		if indexHasUnclaimed == false then
			setStage("Explain")
			return
		end
		setText("Open the Index to see every Sheep you've found!")
		point(indexHudButton)
		setHint(indexHudButton)
	elseif indexHasUnclaimed == false then
		setStage("Explain")
	else
		local target = if isShown(indexClaimAllButton) then indexClaimAllButton else indexClaimButton
		setText("Press Claim! Every new Sheep you find gives you Luck")
		point(target)
		setHint(target)
	end
end

-- The closing tour: closes any window, then spotlights each EXPLAIN_STEPS button with its sentence before the completed label.
local function updateExplain()
	local open = isWindowOpen("Index")
	if open then
		setText("Close the Index")
		point(indexExit)
		setHint(indexExit)
		stageStartedAt = os.clock() -- the tour starts once it's closed
		return
	end

	local step = EXPLAIN_STEPS[math.floor((os.clock() - stageStartedAt) / EXPLAIN_SECONDS) + 1]
	if not step then
		stage = "Done"
		return
	end
	setText(step.text)
	point(step.button)
	setHint(nil)
end

local UPDATERS: { [Stage]: () -> () } = {
	EquipShears = updateEquipShears,
	GoToSheep = updateGoToSheep,
	FirstShear = updateFirstShear,
	Shear = updateShear,
	Upgrades = updateUpgrades,
	CloseUpgrades = updateCloseUpgrades,
	Rebirth = updateRebirth,
	Index = updateIndex,
	Explain = updateExplain,
}

--// Lifecycle ---------------------------------------------------------------------------

-- Hides every HUD button the tutorial doesn't use; showHudButtons puts them back.
local function hideHudButtons()
	for _, button in hudButtons:GetChildren() do
		if button:IsA("GuiObject") and button.Visible and not KEEP_HUD_BUTTONS[button.Name] then
			button.Visible = false
			table.insert(hiddenHudButtons, button)
		end
	end
end

local function showHudButtons()
	for _, button in hiddenHudButtons do
		button.Visible = true
	end
	table.clear(hiddenHudButtons)
end

local function stop()
	stage = "Done"
	setHighlights({})
	point(nil)
	if beamConnection then
		beamConnection:Disconnect()
		beamConnection = nil
	end
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	beam:Destroy()
	beamStart:Destroy()
	beamEnd:Destroy()
	hotbarFrame:Destroy()
	hint:Destroy()
	progressBar:Destroy()
	tutorialMain.Visible = false
	spotlightFrame.Visible = false
	tutorialGui.Enabled = false
	showHudButtons()
	showOtherGuis()
end

-- Pops the completed label and Tip in over the dimmed screen, holds them, then pops them out.
local function showCompleted()
	tutorialGui.Enabled = true
	darkOverlay.Visible = true
	if stepSound then
		stepSound:Play()
	end
	popIn(completedLabel)
	popIn(tip)
	task.wait(COMPLETED_SECONDS)

	task.spawn(popOut, tip)
	popOut(completedLabel)
	darkOverlay.Visible = false
	tutorialGui.Enabled = false
end

local function start(firstStage: Stage)
	local startRebirths = getNumberAttribute("Rebirths")
	tutorialGui.ResetOnSpawn = false
	tutorialGui.DisplayOrder = DISPLAY_ORDER
	tutorialGui.Enabled = true
	tutorialMain.Visible = true
	tutorialFrame.Visible = true
	tutorialText.Visible = true
	tutorialText.RichText = true
	hideHudButtons()

	setStage(firstStage, true)
	beamConnection = runService.RenderStepped:Connect(updateBeam)
	inputConnection = userInputService.InputBegan:Connect(onInputBegan)
	if (STAGE_ORDER[firstStage] or 0) <= STAGE_ORDER.FirstShear then
		network.fireServer(network.RemoteEvents.RequestTutorialSheep)
	end

	while stage ~= "Done" do
		local rebirths = getNumberAttribute("Rebirths")
		if rebirths < startRebirths then
			startRebirths = rebirths -- the data was reset, so the next rebirth still counts
		elseif rebirths > startRebirths then
			startRebirths = rebirths
			if STAGE_ORDER[stage] < STAGE_ORDER.Index then
				setStage("Index")
			end
		end
		UPDATERS[stage]()
		if HIDE_UI_STAGES[stage] then
			hideOtherGuis()
		end
		task.wait(TICK_SECONDS)
	end

	stop()
	showCompleted()
end

tutorialGui.Enabled = false
spotlightFrame.Visible = false -- FocusUI shows it when there's a button to point at
darkOverlay.Visible = false
completedLabel.Visible = false
tip.Visible = false

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradeState, function(states: { any })
	local byId = {}
	for _, state in states do
		byId[state.id] = state
	end
	upgradeStates = byId
end)

network.connectEvent(network.RemoteEvents.RebirthState, function(state: any)
	rebirthCost = state.woolCost
end)

network.connectEvent(network.RemoteEvents.IndexState, function(entries: { any })
	local unclaimed = false
	for _, entry in entries do
		if entry.status == "Found" then
			unclaimed = true
		end
	end
	indexHasUnclaimed = unclaimed
end)

-- The save has loaded once its numbers are mirrored onto the player.
while player:GetAttribute("Rebirths") == nil do
	player:GetAttributeChangedSignal("Rebirths"):Wait()
end

local forced = ALWAYS_IN_STUDIO and runService:IsStudio()
if forced then
	print("[TutorialClient] running from the start (ALWAYS_IN_STUDIO)")
	shearedBaseline = getNumberAttribute("SheepShearedCount")
	start("EquipShears")
elseif getNumberAttribute("Rebirths") >= 1 or getNumberAttribute("Prestiges") >= 1 then
	stop()
else
	local sheared = getNumberAttribute("SheepShearedCount")
	start(if sheared >= SHEEP_TO_SHEAR then "Upgrades" elseif sheared >= 1 then "Shear" else "EquipShears")
end
