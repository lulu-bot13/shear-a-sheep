--[[
	First-play tutorial: shear the Huge Fluffy and 2 more, buy the Steel Shears, buy upgrades, shear for the rebirth, rebirth, then claim in the Index.
	Steps are worked out from progress so they resume after a rejoin; a tapping hand, beams and highlights point the way.
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
local tutorialFrame = tutorialGui:WaitForChild("TutorialFrame") :: GuiObject
local tutorialText = tutorialFrame:WaitForChild("TutorialText") :: TextLabel
local tutorialProgression = tutorialFrame:WaitForChild("TutorialProgression") :: TextLabel
local spotlightFrame = tutorialGui:WaitForChild("Spotlight") :: GuiObject
local darkOverlay = tutorialGui:WaitForChild("DarkOverlay") :: GuiObject
local completedLabel = tutorialGui:WaitForChild("TutorialCompletedLabel") :: GuiObject
local tip = tutorialGui:WaitForChild("Tip") :: GuiObject
playerGui:WaitForChild("Main"):WaitForChild("Buttons"):WaitForChild("Index") -- the HUD buttons are looked up each time (Main is rebuilt on respawn)
local indexFrame = playerGui:WaitForChild("Index"):WaitForChild("IndexFrame")
local indexMain = indexFrame:WaitForChild("Main")
local indexRewardFrame = indexMain:WaitForChild("RewardFrame")
local indexClaimButton = indexRewardFrame:WaitForChild("BuyButton") :: GuiButton
local indexClaimAllButton = indexRewardFrame:WaitForChild("ClaimAll"):WaitForChild("ClaimAllButton") :: GuiButton
local indexExit = indexFrame:WaitForChild("ExitButton") :: GuiObject
local upgradeShopMain = playerGui:WaitForChild("UpgradeShop"):WaitForChild("Main")
local upgradeCards = upgradeShopMain:WaitForChild("ScrollingFrame")
local upgradeShopExit = upgradeShopMain:FindFirstChild("Exit", true) :: GuiObject? -- found the same way WindowsManager wires it
local rebirthButton = playerGui:WaitForChild("RebirthScreen"):WaitForChild("Main"):WaitForChild("RebirthButton") :: GuiButton
local shopScroll = playerGui:WaitForChild("Shop"):WaitForChild("Main"):WaitForChild("ScrollingFrame") :: ScrollingFrame
local shopHitbox = workspace:WaitForChild("Base"):WaitForChild("CenterPlaza"):WaitForChild("ShearShop")
	:WaitForChild("Shack"):WaitForChild("ShearShopHitbox") :: BasePart
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
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
local TUTORIAL_SHEEP_WAIT_SECONDS = 10 -- if the Fluffy hasn't landed by then (e.g. the server skipped it), any sheep will do
local SHEARS_ID = "SteelShears" -- the shear bought in the tutorial (unlocks at 3 sheep, ShearData)
local SHEARS_NAME = "Steel Shears"
local SHOP_WINDOW = "ShearShop"
local SHOP_NEAR_DISTANCE = 60 -- studs from the shop hitbox; further away, the ToShop button is pointed at too
local FARM_FAR_DISTANCE = 120 -- studs from the plot's Center; further away, shearing steps point at the ToPlot button
local SHOP_SCROLL_DELAY = 0.25 -- after the shop opens, so its pop-in has finished before the card is measured
local SHOP_SCROLL_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The upgrades bought in order in one shop visit, each with why it helps; 45 + 76 + 40 wool, which the starter wool and the first 3 sheep cover.
local TUTORIAL_UPGRADES = {
	{ id = "MoreWool", text = "Upgrade your wool multiplier. Every Sheep gives you more Wool!" },
	{ id = "MoreWool", text = "Upgrade your wool multiplier. Every Sheep gives you more Wool!" },
	{ id = "Capacity", text = "Now upgrade Sheep Capacity. More Sheep enter your pen!" },
}
local KEEP_HUD_BUTTONS = { Upgrades = true, Rebirth = true } -- the only HUD buttons shown until the Index stage
local HIDE_UI_STAGES = { GoToSheep = true, FirstShear = true, Shear = true } -- every ScreenGui but the tutorial's is off during these
local KEEP_GUIS = { TouchGui = true } -- the PlayerModule's thumbstick and jump button, so mobile players can still move
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- Every stage in order; TutorialProgression shows the current one as "3/10". The cheer plays on reaching a stage.
local STAGES = { "GoToSheep", "FirstShear", "Shear", "GoToShop", "BuyShears", "Upgrades", "CloseUpgrades", "Rebirth", "Index", "CloseIndex" }
local STAGE_ORDER: { [string]: number } = {}
for index, name in STAGES do
	STAGE_ORDER[name] = index
end
local STAGE_CHEERS = {
	Shear = "Fluffy Sheep sheared!",
	GoToShop = "Wool collected!",
	Upgrades = `{SHEARS_NAME} bought!`,
	CloseUpgrades = "Upgrades bought!",
	Index = "Rebirthed!",
	CloseIndex = "Luck claimed!",
}
local TUTORIAL_SHEEP_ATTRIBUTE = "TutorialSheep" -- set by TutorialHandler on the Huge sheep it drops for the first shear

--// Rebirth progress bar, under the instruction box while the player shears for the rebirth
local BAR_HEIGHT = 26
local BAR_GAP = 72 -- pixels between the bottom of the instruction box / drawn text and the bar's outline
local BAR_MIN_GAP = 8 -- the overlap check pushes the bar down until at least this much space shows above it
local BAR_SCREEN_MARGIN = 4 -- pixels the bar's outline keeps from the bottom of the screen
local BAR_STROKE_THICKNESS = 2
local BAR_WIDTH_SCALE = 0.85 -- of the instruction box's width
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_BACK_COLOR = Color3.fromRGB(40, 35, 30)
local BAR_FILL_COLOR = Color3.fromRGB(255, 215, 80)
local BAR_MILESTONES = { { ratio = 0.5, text = "Halfway there!" }, { ratio = 0.8, text = "Almost there!" } }

local SPOTLIGHT_Z_INDEX = 20 -- a spotlit button and its text label are lifted to this while the spotlight is on them
local SPOTLIGHT_TEXT_NAMES = { Rebirth = "Title" } -- spotlit button name -> its text label that is lifted with it

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
-- Both beam ends face along the beam's flat heading, then get this extra roll so the ribbon lies face-up.
local BEAM_ATTACHMENT_ROTATION = CFrame.fromOrientation(0, 0, math.rad(90))

--// Click hint: a hand that taps the target button, a ripple on each tap and a pulsing CLICK / TAP word
local HINT_Z_INDEX = 50
local HAND_SIZE = 72
local HAND_GAP = -6 -- pixels between the target point and the hand's edge; below 0 the emoji's padding overlaps it, so the fingertip lands on it
local HAND_TRAVEL = 12 -- how far the hand moves in on each tap
local BUTTON_TAP_DEPTH = 0.3 -- how far down a button the fingertip lands, of its height (the ripple is at its centre)
local HINT_LABEL_SIZE = Vector2.new(170, 40)
local HINT_FALLBACK = Vector2.new(0.5, 0.62) -- of the screen, where an R2 press ripples when no button is hinted

--// Side click cue: while shearing, a pointing hand and "CLICK!" pulse at the right edge instead of over the sheep
local SIDE_CLICK_SIZE = Vector2.new(190, 150)
local SIDE_CLICK_EDGE_GAP = 24 -- pixels from the right edge of the screen
local SIDE_CLICK_NUDGE = 14 -- how far the hand jabs left on each pulse
local SIDE_CLICK_PULSE = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

--// Confetti on finishing
local CONFETTI_COUNT = 90
local CONFETTI_SIZE = NumberRange.new(10, 18) -- pixels along the long side
local CONFETTI_FALL_SECONDS = NumberRange.new(1.8, 3)
local CONFETTI_DRIFT = 140 -- pixels each piece can drift sideways as it falls
local CONFETTI_SPIN = 720 -- degrees each piece can turn as it falls
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(110, 220, 110),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(200, 110, 255),
	Color3.fromRGB(255, 140, 200),
}
local MAIN_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui once this script is finished with it, for CrookTutorialClient
local TAP_IN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAP_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAP_PAUSE = 0.55
local LABEL_PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RIPPLE_TWEEN = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HINT_RIPPLE_SIZE = 90
local CLICK_RIPPLE_SIZE = 120
local RIPPLE_COLOR = Color3.fromRGB(255, 255, 255)
local CHEER_SIZE = Vector2.new(320, 44)
local CHEER_MIN_HEIGHT = 16 -- below this, there's no room for a cheer above the rebirth bar and it's skipped
local CHEER_DRIFT = 60 -- pixels it drifts down as it fades
local CHEER_STROKE_THICKNESS = 3
local CHEER_POP_OVERSHOOT = 1.12 -- the Back-eased pop in grows it to about 1.1x for a moment
local CHEER_TWEEN = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CHEER_COLOR = Color3.fromRGB(120, 255, 120)

type Stage = "GoToSheep" | "FirstShear" | "Shear" | "GoToShop" | "BuyShears" | "Upgrades" | "CloseUpgrades" | "Rebirth" | "Index" | "CloseIndex" | "Done"
type InputMode = "Mouse" | "Touch" | "Gamepad"

--// State
local stage: Stage = "GoToSheep"
local shearedBaseline = 0 -- SheepShearedCount the "Shear 3 Sheep" progress counts up from
local hiddenHudButtons: { GuiObject } = {}
local hiddenGuis: { ScreenGui } = {}
local popFullScales: { [UIScale]: number } = setmetatable({}, { __mode = "k" }) :: any -- each popped object's full size, read before its first pop (cheer labels come and go)
local upgradeStates: { [string]: any }? = nil -- UpgradeState cards by id
local rebirthCost: number? = nil
local nextStateRequest = 0
local highlights: { [Model]: Highlight } = {}
local beamSheep: Model? = nil -- the sheep the beam leads to
local beamPart: BasePart? = nil -- or the part it leads to (the shear shop's hitbox) when there's no sheep
local stageStartedAt = 0
local shopOpenedAt: number? = nil
local shopScrollTween: Tween? = nil
local firstSheep: Model? = nil -- the sheep "Click To Shear" shows the health of
local beamConnection: RBXScriptConnection? = nil
local inputConnection: RBXScriptConnection? = nil
local focused: GuiObject? = nil -- what the spotlight was last tweened over, and where it was
local focusedPosition, focusedSize = Vector2.zero, Vector2.zero
local raisedZIndex: { [GuiObject]: number } = {} -- original ZIndex of what raiseWhileSpotlit lifted
local hintTarget: GuiObject? = nil -- what the tapping hand points at
local hintRipplePoint = Vector2.zero -- where the hand's taps ripple (the target's centre), in tutorialGui pixels
local lastClickAt = 0
local barMilestone = 0 -- BAR_MILESTONES already cheered this Rebirth stage
local barPush = 0 -- pixels the overlap check moved the bar down past where it was laid out
local barNoRoomWarned = false
local barFloor = 0 -- the highest pixel the bar's outline may sit at while a cheer above it is showing
local barFloorUntil = 0
local barLayoutConnections: { RBXScriptConnection } = {}
local viewportConnection: RBXScriptConnection? = nil
local indexUnclaimed: number? = nil -- Index entries waiting to be claimed, from IndexState; nil until it arrives

-- One beam cloned once and reused. Its ends stay in Terrain and are moved each frame,
-- so a respawned character or a replaced sheep can't destroy them.
local beamStart = Instance.new("Attachment")
beamStart.Name = "TutorialBeamStart"
beamStart.Parent = workspace.Terrain
local beamEnd = Instance.new("Attachment")
beamEnd.Name = "TutorialBeamEnd"
beamEnd.Parent = workspace.Terrain
local beamHeading = Vector3.zAxis -- last flat direction from player to sheep, kept when they're directly above each other

local beam = beamTemplate:Clone()
beam.Attachment0 = beamStart
beam.Attachment1 = beamEnd
beam.FaceCamera = false -- the ends' rotation sets which way the beam lies
beam.Enabled = false
beam.Parent = workspace.Terrain

--// Click hint instances: a zero-size frame placed on the target button, holding the hand above it and the word above that.
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
hand.AnchorPoint = Vector2.new(0.5, 1)
hand.Size = UDim2.fromOffset(HAND_SIZE, HAND_SIZE)
hand.Font = Enum.Font.GothamBold
hand.TextScaled = true
hand.Text = "👇"
hand.ZIndex = HINT_Z_INDEX + 2
hand.Parent = hint

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Action"
hintLabel.BackgroundTransparency = 1
hintLabel.AnchorPoint = Vector2.new(0.5, 0.5)
hintLabel.Position = UDim2.fromOffset(0, -(HAND_GAP + HAND_SIZE + HINT_LABEL_SIZE.Y / 2))
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

--// Side click cue instances: a hand pointing in from the right edge over a pulsing "CLICK!".
local sideClick = Instance.new("Frame")
sideClick.Name = "TutorialSideClick"
sideClick.BackgroundTransparency = 1
sideClick.AnchorPoint = Vector2.new(1, 0.5)
sideClick.Position = UDim2.new(1, -SIDE_CLICK_EDGE_GAP, 0.5, 0)
sideClick.Size = UDim2.fromOffset(SIDE_CLICK_SIZE.X, SIDE_CLICK_SIZE.Y)
sideClick.ZIndex = HINT_Z_INDEX
sideClick.Visible = false
sideClick.Parent = tutorialGui

local sideHand = Instance.new("TextLabel")
sideHand.Name = "Hand"
sideHand.BackgroundTransparency = 1
sideHand.Size = UDim2.fromScale(1, 0.6)
sideHand.Font = Enum.Font.GothamBold
sideHand.TextScaled = true
sideHand.Text = "👈"
sideHand.ZIndex = HINT_Z_INDEX + 2
sideHand.Parent = sideClick
tweenService:Create(sideHand, SIDE_CLICK_PULSE, { Position = UDim2.fromOffset(-SIDE_CLICK_NUDGE, 0) }):Play()

local sideLabel = Instance.new("TextLabel")
sideLabel.Name = "Action"
sideLabel.BackgroundTransparency = 1
sideLabel.Position = UDim2.fromScale(0, 0.6)
sideLabel.Size = UDim2.fromScale(1, 0.4)
sideLabel.Font = Enum.Font.FredokaOne
sideLabel.TextScaled = true
sideLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
sideLabel.ZIndex = HINT_Z_INDEX + 2
sideLabel.Parent = sideClick

local sideLabelStroke = Instance.new("UIStroke")
sideLabelStroke.Color = Color3.fromRGB(0, 0, 0)
sideLabelStroke.Thickness = 3
sideLabelStroke.Parent = sideLabel

local sideClickScale = Instance.new("UIScale")
sideClickScale.Parent = sideClick
tweenService:Create(sideClickScale, SIDE_CLICK_PULSE, { Scale = 1.12 }):Play()

--// Rebirth progress bar: a square-cornered back with an outline, a fill that grows to the wool owned, and "120 / 200 Wool" over both.
local progressBar = Instance.new("Frame")
progressBar.Name = "TutorialRebirthBar"
progressBar.AnchorPoint = Vector2.new(0.5, 0)
progressBar.BackgroundColor3 = BAR_BACK_COLOR
progressBar.BorderSizePixel = 0
progressBar.ZIndex = HINT_Z_INDEX
progressBar.Visible = false
progressBar.Parent = tutorialGui

local progressStroke = Instance.new("UIStroke")
progressStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
progressStroke.Color = Color3.fromRGB(20, 15, 10)
progressStroke.Thickness = BAR_STROKE_THICKNESS
progressStroke.Parent = progressBar

local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.BackgroundColor3 = BAR_FILL_COLOR
progressFill.BorderSizePixel = 0
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.ZIndex = HINT_Z_INDEX + 1
progressFill.Parent = progressBar

local progressText = Instance.new("TextLabel")
progressText.Name = "Amount"
progressText.BackgroundTransparency = 1
progressText.Size = UDim2.fromScale(1, 1)
progressText.Font = Enum.Font.FredokaOne
progressText.TextScaled = true
progressText.TextColor3 = Color3.fromRGB(255, 255, 255)
progressText.ZIndex = HINT_Z_INDEX + 2
progressText.Parent = progressBar

local progressTextStroke = progressStroke:Clone()
progressTextStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual -- outlines the letters, not the label's box
progressTextStroke.Parent = progressText

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

-- The "OwnedShears" attribute is "DefaultShear,SteelShears" (set by ShearShopHandler).
local function ownsShears(): boolean
	local owned = player:GetAttribute("OwnedShears")
	return type(owned) == "string" and table.find(string.split(owned, ","), SHEARS_ID) ~= nil
end

-- Main.ToShop / Main.ToPlot, looked up each time since Main is rebuilt on respawn.
local function getMainButton(name: string): GuiObject?
	local main = playerGui:FindFirstChild("Main")
	local button = main and main:FindFirstChild(name)
	return if button and button:IsA("GuiObject") then button else nil
end

-- The middle of the player's plot, for telling whether they've wandered off it (e.g. to the shear shop).
local function getFarmCenter(): Vector3?
	local plotName = player:GetAttribute("PlotName")
	local plot = if type(plotName) == "string" then plotsFolder:FindFirstChild(plotName) else nil
	local center = plot and plot:FindFirstChild("Center")
	if center and center:IsA("BasePart") then
		return center.Position
	end
	return if plot and plot:IsA("Model") then plot:GetPivot().Position else nil
end

-- Holds the shears out for the player (the tutorial needs them in hand), once they've landed in the Backpack.
local function equipShears()
	if isHoldingShear() then
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not humanoid or not backpack then
		return
	end
	for _, tool in backpack:GetChildren() do
		if tool:IsA("Tool") and tool:GetAttribute(SHEAR_RANGE_ATTRIBUTE) ~= nil then
			humanoid:EquipTool(tool)
			return
		end
	end
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

-- Main.Buttons, or one of its buttons, in the current Main (a respawn swaps in a fresh copy).
local function getHudButtons(): Instance?
	local main = playerGui:FindFirstChild("Main")
	return main and main:FindFirstChild("Buttons")
end

local function getHudButton(name: string): GuiObject?
	local buttons = getHudButtons()
	local button = buttons and buttons:FindFirstChild(name)
	return if button and button:IsA("GuiObject") then button else nil
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

local function getHintWord(): string
	local mode = getInputMode()
	return if mode == "Touch" then "TAP!" elseif mode == "Gamepad" then "R2!" else "CLICK!"
end

-- Offset between a ScreenGui's pixels and input positions, which differ by the top bar.
local function getGuiInset(): Vector2
	return (guiService:GetGuiInset())
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

-- Shows the instruction straight away, with no animation.
local function setText(text: string)
	tutorialText.Text = text
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

-- Points the tapping hand down at a GuiObject; nil hides it.
local function setHint(target: GuiObject?)
	hintTarget = target
end

-- Shows or hides the "CLICK!" cue at the right edge, used instead of the hand while the player shears a sheep.
local function setSideClick(visible: boolean)
	sideClick.Visible = visible
	if visible then
		sideLabel.Text = getHintWord()
	end
end

--[[
	Where the hand's fingertip goes and where its taps ripple; nil when the target isn't shown.
	A button is tapped a little way down from its top edge and ripples from its centre, so both land on the button itself.
]]
local function getHintPoint(): (Vector2?, Vector2)
	local target = hintTarget
	if not target or not isShown(target) then
		return nil, Vector2.zero
	end
	local position, size = target.AbsolutePosition, target.AbsoluteSize
	return position + Vector2.new(size.X / 2, size.Y * BUTTON_TAP_DEPTH), position + size / 2
end

-- Runs every frame: keeps the hand on its target.
local function updateHint()
	local point, ripplePoint = getHintPoint()
	if not point then
		hint.Visible = false
		return
	end

	hintRipplePoint = ripplePoint
	hint.Position = UDim2.fromOffset(point.X, point.Y)
	hintLabel.Text = getHintWord()
	hint.Visible = true
end

-- The hand's resting offset from the fingertip point, and the offset it taps in to (it sits above, so both go up).
local function getHandOffsets(): (UDim2, UDim2)
	return UDim2.fromOffset(0, -(HAND_GAP + HAND_TRAVEL)), UDim2.fromOffset(0, -HAND_GAP)
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

--// Layout rects ------------------------------------------------------------------------

-- True when two rects (top-left corner and size, in pixels) are closer than `gap` on both axes; exactly `gap` apart doesn't count.
local function rectsIntersect(aPosition: Vector2, aSize: Vector2, bPosition: Vector2, bSize: Vector2, gap: number): boolean
	return aPosition.X < bPosition.X + bSize.X + gap and bPosition.X < aPosition.X + aSize.X + gap
		and aPosition.Y < bPosition.Y + bSize.Y + gap and bPosition.Y < aPosition.Y + aSize.Y + gap
end

local function unionRects(aPosition: Vector2, aSize: Vector2, bPosition: Vector2, bSize: Vector2): (Vector2, Vector2)
	local topLeft = aPosition:Min(bPosition)
	return topLeft, (aPosition + aSize):Max(bPosition + bSize) - topLeft
end

-- The pixels a label covers: its box grown to the drawn text (TextBounds can spill past a wrapped label) and the text's outline.
local function getLabelRect(label: TextLabel): (Vector2, Vector2)
	local position, size, bounds = label.AbsolutePosition, label.AbsoluteSize, label.TextBounds
	local textX = if label.TextXAlignment == Enum.TextXAlignment.Left then position.X
		elseif label.TextXAlignment == Enum.TextXAlignment.Right then position.X + size.X - bounds.X
		else position.X + (size.X - bounds.X) / 2
	local textY = if label.TextYAlignment == Enum.TextYAlignment.Top then position.Y
		elseif label.TextYAlignment == Enum.TextYAlignment.Bottom then position.Y + size.Y - bounds.Y
		else position.Y + (size.Y - bounds.Y) / 2
	local rectPosition, rectSize = unionRects(position, size, Vector2.new(textX, textY), bounds)

	local stroke = label:FindFirstChildOfClass("UIStroke")
	local outline = if stroke and stroke.Enabled then stroke.Thickness else 0
	return rectPosition - Vector2.new(outline, outline), rectSize + Vector2.new(outline, outline) * 2
end

-- What the bar and cheers must stay clear of: the instruction box, its text and its "3/8" counter.
local function getBlockedRect(): (Vector2, Vector2)
	local position, size = unionRects(tutorialFrame.AbsolutePosition, tutorialFrame.AbsoluteSize, getLabelRect(tutorialText))
	if isShown(tutorialProgression) then
		position, size = unionRects(position, size, getLabelRect(tutorialProgression))
	end
	return position, size
end

-- A UIScale on the tutorial gui multiplies every offset, so pixel distances are divided by it before they become offsets.
local function getGuiScale(): number
	local uiScale = tutorialGui:FindFirstChildOfClass("UIScale")
	return if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
end

-- How far an outline can reach past its object: whether or not the UIScale scales strokes, no further than this.
local function getOutline(thickness: number, scale: number): number
	return thickness * math.max(scale, 1)
end

local function getBarOutline(scale: number): number
	return getOutline(BAR_STROKE_THICKNESS, scale)
end

--[[
	A green "Wool collected!" that pops in under the instruction text, drifts down and fades.
	While the rebirth bar shows it only gets the room above the bar (shorter and drifting less if it must), and barFloor holds the bar
	below everything it can reach until it's gone, so the two never come within BAR_MIN_GAP. With too little room it's skipped.
]]
local function cheer(text: string)
	if stepSound then
		stepSound:Play()
	end

	local scale = getGuiScale()
	local guiPosition = tutorialGui.AbsolutePosition
	local framePosition, frameSize = tutorialFrame.AbsolutePosition, tutorialFrame.AbsoluteSize
	local blockedPosition, blockedSize = getBlockedRect()
	local outline = getOutline(CHEER_STROKE_THICKNESS, scale)
	local top = blockedPosition.Y + blockedSize.Y + BAR_MIN_GAP + outline -- the label's top edge; its outline stays BAR_MIN_GAP below the text
	local height = CHEER_SIZE.Y * scale
	local drift = CHEER_DRIFT * scale
	if progressBar.Visible and progressBar.Parent then
		-- The bar's top as layoutRebirthBar set it (AbsolutePosition can lag a frame); both are placed the same way, so they compare exactly.
		local barTop = guiPosition.Y + progressBar.Position.Y.Offset * scale - getBarOutline(scale)
		local room = barTop - BAR_MIN_GAP - top -- for the popped label, its lower outline and the drift
		height = math.min(height, room / CHEER_POP_OVERSHOOT - outline)
		if height < CHEER_MIN_HEIGHT * scale then
			return
		end
		local reach = (height + outline) * CHEER_POP_OVERSHOOT
		drift = math.clamp(room - reach, 0, drift)
		barFloor = top + reach + drift + BAR_MIN_GAP
		barFloorUntil = os.clock() + CHEER_TWEEN.Time + 0.1
	end

	local label = Instance.new("TextLabel")
	label.Name = "TutorialCheer"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Size = UDim2.fromOffset(CHEER_SIZE.X, height / scale)
	label.Position = UDim2.fromOffset((framePosition.X + frameSize.X / 2 - guiPosition.X) / scale, (top - guiPosition.Y) / scale)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = `✔ {text}`
	label.TextColor3 = CHEER_COLOR
	label.ZIndex = HINT_Z_INDEX + 3

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 60, 20)
	stroke.Thickness = CHEER_STROKE_THICKNESS
	stroke.Parent = label

	label.Parent = tutorialGui
	popIn(label)
	tweenService:Create(label, CHEER_TWEEN, { Position = label.Position + UDim2.fromOffset(0, drift / scale), TextTransparency = 1 }):Play()
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

-- Runs every frame: draws the beam from the character to beamSheep or beamPart (hidden when there's neither) and moves the hand.
local function updateBeam()
	updateHint()

	local playerRoot = getRoot(player.Character)
	local targetPart = getRoot(beamSheep) or (if beamPart and beamPart.Parent then beamPart else nil)
	if not playerRoot or not targetPart then
		beam.Enabled = false
		return
	end

	-- The ends turn with the beam's heading, so it looks the same from every side instead of twisting.
	local startPosition, endPosition = playerRoot.Position, targetPart.Position
	local flat = Vector3.new(endPosition.X - startPosition.X, 0, endPosition.Z - startPosition.Z)
	if flat.Magnitude > 1e-3 then
		beamHeading = flat.Unit
	end
	beamStart.WorldCFrame = CFrame.lookAt(startPosition, startPosition - beamHeading) * BEAM_ATTACHMENT_ROTATION
	beamEnd.WorldCFrame = CFrame.lookAt(endPosition, endPosition - beamHeading) * BEAM_ATTACHMENT_ROTATION
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

-- Puts back the ZIndex of everything raiseWhileSpotlit lifted.
local function restoreRaised()
	for guiObject, zIndex in raisedZIndex do
		guiObject.ZIndex = zIndex
	end
	table.clear(raisedZIndex)
end

-- A spotlit button in SPOTLIGHT_TEXT_NAMES (the HUD's Rebirth) and its text label draw over everything around them.
local function raiseWhileSpotlit(target: GuiObject)
	local textName = SPOTLIGHT_TEXT_NAMES[target.Name]
	local text = textName and target:FindFirstChild(textName)
	if not text or not text:IsA("GuiObject") then
		return
	end
	for _, guiObject in { target, text } do
		raisedZIndex[guiObject] = guiObject.ZIndex
		guiObject.ZIndex = SPOTLIGHT_Z_INDEX
	end
end

-- Spotlights the GuiObject; nil clears it.
-- FocusUI only measures the target once, so it is called again whenever the target moves (e.g. a window popping in).
local function point(target: GuiObject?)
	if target and isShown(target) then
		if target ~= focused then
			restoreRaised()
			raiseWhileSpotlit(target)
		end
		if target ~= focused or target.AbsolutePosition ~= focusedPosition or target.AbsoluteSize ~= focusedSize then
			focused, focusedPosition, focusedSize = target, target.AbsolutePosition, target.AbsoluteSize
			spotlightUI:FocusUI(target)
		end
	elseif focused then
		focused = nil
		restoreRaised()
		spotlightUI:Cleanup()
	end
end

--// Stages ------------------------------------------------------------------------------

-- Turns off every ScreenGui but the tutorial's; run each tick, since respawned or newly opened guis come back on.
local function hideOtherGuis()
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= tutorialGui and gui.Enabled and not KEEP_GUIS[gui.Name] then
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
	if newStage == "Index" then
		indexUnclaimed = nil -- asked again, since sheep found since the last IndexState make it stale
	end
	setHighlights({})
	beamSheep = nil
	beamPart = nil
	firstSheep = nil
	shopOpenedAt, shopScrollTween = nil, nil
	setHint(nil)
	setSideClick(false)
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

--[[
	Shearing for wool after the first sheep: the beam leads to the closest sheep, and once there the side "CLICK!" comes back if the player stops clicking.
	Away from the farm (after the shear shop) the ToPlot button is pointed at; with the pen empty, the player is told why and what fixes it.
]]
local function guideShearing(nearText: string, farText: string)
	equipShears()
	point(nil)
	setHint(nil)

	local playerRoot = getRoot(player.Character)
	local farmCenter = getFarmCenter()
	if playerRoot and farmCenter and getFlatDistance(playerRoot.Position, farmCenter) > FARM_FAR_DISTANCE then
		setHighlights({})
		beamSheep = nil
		local toPlot = getMainButton("ToPlot")
		setText("Press the button to go back to your farm")
		point(toPlot)
		setHint(toPlot)
		return
	end

	local nearest, near = guideToSheep()
	if not nearest then
		setText("Out of Sheep! New ones ride in on the conveyor. Buy Faster Respawn in Upgrades to get them quicker!")
	elseif near then
		setText(nearText)
		setSideClick(os.clock() - lastClickAt >= IDLE_HINT_SECONDS)
	else
		setText(farText)
	end
end

-- "Go to the Fluffy Sheep": the beam leads to the Huge Fluffy the server drops (the only sheep that can be sheared until it's bare).
-- If it never lands, the closest sheep is used instead.
local function updateGoToSheep()
	equipShears()

	local bigSheep = getTutorialSheep()
	local playerRoot = getRoot(player.Character)
	if bigSheep then
		setText("A HUGE Fluffy Sheep appeared! Follow the arrow to it")
		setHighlights({ bigSheep })
		beamSheep = bigSheep
		if playerRoot and getFlatDistance(playerRoot.Position, (getRoot(bigSheep) :: BasePart).Position) <= NEAR_DISTANCE then
			setStage("FirstShear")
			firstSheep = bigSheep
		end
		return
	end
	if os.clock() - stageStartedAt < TUTORIAL_SHEEP_WAIT_SECONDS then
		setText("A Fluffy Sheep is on its way...")
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
	equipShears()

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
	setSideClick(true)
	local action = getShearAction()
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) == "number" and type(maxHealth) == "number" then
		setText(`{action} to shear! Keep going until its Wool is gone (HP {formatHealth(math.max(health, 0))}/{formatHealth(maxHealth)})`)
	else
		setText(`{action} to shear! Keep going until its Wool is gone`)
	end
end

-- "Shear 2 Sheep (0/2)": sheep shorn bare after the first one (TutorialHandler drops them into the pen); the beam still leads to the closest.
local function updateShear()
	local count = getNumberAttribute("SheepShearedCount")
	if count < shearedBaseline then
		shearedBaseline = count -- the data was reset (e.g. /resetdata), so count from the new total
	end
	local sheared = count - shearedBaseline
	if sheared >= SHEEP_TO_SHEAR then
		setStage(if ownsShears() then "Upgrades" else "GoToShop")
		return
	end

	local remaining = SHEEP_TO_SHEAR - 1 -- the first sheep was the "Click to Shear" stage
	local text = `Shear {remaining} Sheep ({math.max(sheared - 1, 0)}/{remaining})`
	guideShearing(text, text)
end

-- Studs from the position to the shop hitbox's surface (0 inside it).
local function getShopDistance(position: Vector3): number
	local offset = shopHitbox.CFrame:PointToObjectSpace(position)
	local half = shopHitbox.Size / 2
	local clamped = Vector3.new(math.clamp(offset.X, -half.X, half.X), math.clamp(offset.Y, -half.Y, half.Y), math.clamp(offset.Z, -half.Z, half.Z))
	return (offset - clamped).Magnitude
end

-- "Go to the Shear Shop": the beam leads to the shop's hitbox (walking in opens the shop); far away, the ToShop button is pointed at too.
local function updateGoToShop()
	if ownsShears() then
		setStage("Upgrades")
		return
	elseif isWindowOpen(SHOP_WINDOW) then
		setStage("BuyShears")
		return
	end

	beamPart = shopHitbox
	local playerRoot = getRoot(player.Character)
	local toShop = getMainButton("ToShop")
	if playerRoot and getShopDistance(playerRoot.Position) > SHOP_NEAR_DISTANCE and toShop and isShown(toShop) then
		setText(`You unlocked the {SHEARS_NAME}! Press the button to go to the Shear Shop`)
		point(toShop)
		setHint(toShop)
	else
		setText(`You unlocked the {SHEARS_NAME}! Follow the arrow into the Shear Shop`)
		point(nil)
		setHint(nil)
	end
end

-- Tweens the shop's list so the card's centre lines up with the visible area's centre (the same way ShearTutorialClient does).
local function scrollShopToCard(card: GuiObject): Tween
	local factor = math.max(windowsManager.getScaleFactor(shopScroll), 0.01)
	local windowSize = shopScroll.AbsoluteWindowSize
	local offset = (card.AbsolutePosition + card.AbsoluteSize / 2 - (shopScroll.AbsolutePosition + windowSize / 2)) / factor
	local target = shopScroll.CanvasPosition + offset
	local maxPosition = (shopScroll.AbsoluteCanvasSize - windowSize) / factor
	local goal = Vector2.new(math.clamp(target.X, 0, math.max(maxPosition.X, 0)), math.clamp(target.Y, 0, math.max(maxPosition.Y, 0)))
	local tween = tweenService:Create(shopScroll, SHOP_SCROLL_TWEEN, { CanvasPosition = goal })
	tween:Play()
	return tween
end

-- "Press UNLOCK": the shop scrolls to the Steel Shears' card and its button is spotlit; walking out goes back a step.
local function updateBuyShears()
	if ownsShears() then
		setStage("Upgrades")
		return
	elseif not isWindowOpen(SHOP_WINDOW) then
		setStage("GoToShop")
		return
	end

	local card = shopScroll:FindFirstChild(SHEARS_ID)
	local purchase = card and card:FindFirstChild("Purchase")
	if not card or not card:IsA("GuiObject") or not purchase or not purchase:IsA("GuiObject") then
		setText(`Unlock the {SHEARS_NAME}!`)
		return
	end

	local now = os.clock()
	shopOpenedAt = shopOpenedAt or now
	if not shopScrollTween then
		if now - (shopOpenedAt :: number) >= SHOP_SCROLL_DELAY then
			shopScrollTween = scrollShopToCard(card)
		end
		setText(`Here are the {SHEARS_NAME}!`)
		return
	end
	if shopScrollTween.PlaybackState ~= Enum.PlaybackState.Completed then
		return
	end

	setText(`Press UNLOCK to get the {SHEARS_NAME}. They shear faster and reach further!`)
	point(purchase)
	setHint(purchase)
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
		point(getHudButton("Upgrades"))
		setHint(getHudButton("Upgrades"))
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
		point(getHudButton("Upgrades"))
		setHint(getHudButton("Upgrades"))
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

--// Rebirth bar layout ------------------------------------------------------------------

--[[
	Centres the bar under the instruction box, BAR_GAP below everything getBlockedRect covers (and below a showing cheer's barFloor).
	Once it has landed (its Position is unchanged since the last call, so AbsolutePosition is current) the drawn bar, outline included,
	is checked against that rect: if it comes within BAR_MIN_GAP, barPush moves it down by the shortfall. It never goes past the bottom of the screen.
]]
local function layoutRebirthBar()
	if not progressBar.Visible or not progressBar.Parent then
		return
	end

	local scale = getGuiScale()
	local outline = getBarOutline(scale)
	local guiPosition, guiSize = tutorialGui.AbsolutePosition, tutorialGui.AbsoluteSize
	local framePosition, frameSize = tutorialFrame.AbsolutePosition, tutorialFrame.AbsoluteSize
	local blockedPosition, blockedSize = getBlockedRect()
	local blockedBottom = blockedPosition.Y + blockedSize.Y

	local lowestTop = guiPosition.Y + guiSize.Y - BAR_SCREEN_MARGIN - outline - BAR_HEIGHT * scale
	local cheerFloor = if os.clock() < barFloorUntil then barFloor + outline else -math.huge
	local top = math.min(math.max(blockedBottom + BAR_GAP + outline + barPush, cheerFloor), lowestTop)
	local position = UDim2.fromOffset((framePosition.X + frameSize.X / 2 - guiPosition.X) / scale, (top - guiPosition.Y) / scale)
	local size = UDim2.fromOffset(frameSize.X * BAR_WIDTH_SCALE / scale, BAR_HEIGHT)
	if progressBar.Position ~= position or progressBar.Size ~= size then
		progressBar.Position = position
		progressBar.Size = size
		return -- checked when its AbsolutePosition / AbsoluteSize changes, or on the next tick
	end
	if math.abs(progressBar.AbsolutePosition.Y - top) > 1 then
		return -- layout hasn't caught up yet, so a check now could push the bar down for nothing
	end

	local barPosition = progressBar.AbsolutePosition - Vector2.new(outline, outline)
	local barSize = progressBar.AbsoluteSize + Vector2.new(outline, outline) * 2
	if not rectsIntersect(barPosition, barSize, blockedPosition, blockedSize, BAR_MIN_GAP) then
		return
	end
	if top < lowestTop then
		barPush += math.max(blockedBottom + BAR_MIN_GAP - barPosition.Y, 1)
		layoutRebirthBar()
	elseif not barNoRoomWarned then
		barNoRoomWarned = true
		warn(`[TutorialClient] no room for the rebirth bar below the tutorial text (screen {guiSize.X}x{guiSize.Y})`)
	end
end

-- A new screen size starts the overlap check over.
local function onScreenResized()
	barPush = 0
	layoutRebirthBar()
end

local function watchCamera()
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(onScreenResized)
	end
end

for _, guiObject in { tutorialFrame, tutorialText, tutorialProgression, progressBar } :: { GuiObject } do
	table.insert(barLayoutConnections, guiObject:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutRebirthBar))
	table.insert(barLayoutConnections, guiObject:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRebirthBar))
end
table.insert(barLayoutConnections, tutorialText:GetPropertyChangedSignal("TextBounds"):Connect(layoutRebirthBar))
table.insert(barLayoutConnections, tutorialText:GetPropertyChangedSignal("Text"):Connect(layoutRebirthBar))
table.insert(barLayoutConnections, tutorialGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(onScreenResized))
table.insert(barLayoutConnections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
watchCamera()

-- Fills the bar under the instruction box with wool / cost, and cheers as it passes each BAR_MILESTONES ratio.
local function showRebirthProgress(cost: number)
	if not progressBar.Visible then
		barPush = 0
		progressBar.Visible = true
	end
	layoutRebirthBar()

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
		point(getHudButton("Rebirth"))
		setHint(getHudButton("Rebirth"))
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

-- After the rebirth: open the Index (the Rebirth window is closed so its button shows) and claim the Luck waiting there.
local function updateIndex()
	local indexHudButton = getHudButton("Index")
	if indexHudButton then
		showHudButton(indexHudButton)
	end
	local unclaimed = indexUnclaimed
	if unclaimed == nil then
		requestState(network.RemoteEvents.RequestIndexState)
	end

	if not isWindowOpen("Index") then
		if unclaimed == 0 then
			stage = "Done" -- nothing to claim (e.g. resumed after claiming)
			return
		end
		if windowsManager.anyOpen() then
			windowsManager.closeAll()
		end
		setText("Open the Index to see every Sheep you've found!")
		point(indexHudButton)
		setHint(indexHudButton)
	elseif unclaimed == 0 then
		setStage("CloseIndex")
	elseif unclaimed and unclaimed > 1 then
		-- Claim only takes the selected Sheep, so with several waiting the player is sent to Claim All.
		setText(`Press CLAIM ALL! You found {unclaimed} new Sheep, and each one gives you Luck`)
		point(indexClaimAllButton)
		setHint(indexClaimAllButton)
	else
		setText("Press Claim! Every new Sheep you find gives you Luck")
		point(indexClaimButton)
		setHint(indexClaimButton)
	end
end

-- The last step: close the Index so the completed label and confetti show over the farm.
local function updateCloseIndex()
	if not isWindowOpen("Index") then
		stage = "Done"
		return
	end
	setText("Close the Index")
	point(indexExit)
	setHint(indexExit)
end

local UPDATERS: { [Stage]: () -> () } = {
	GoToSheep = updateGoToSheep,
	FirstShear = updateFirstShear,
	Shear = updateShear,
	GoToShop = updateGoToShop,
	BuyShears = updateBuyShears,
	Upgrades = updateUpgrades,
	CloseUpgrades = updateCloseUpgrades,
	Rebirth = updateRebirth,
	Index = updateIndex,
	CloseIndex = updateCloseIndex,
}

--// Lifecycle ---------------------------------------------------------------------------

-- Hides every HUD button the tutorial doesn't use; showHudButtons puts them back.
local function hideHudButtons()
	local buttons = getHudButtons()
	if not buttons then
		return
	end
	for _, button in buttons:GetChildren() do
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
	for _, connection in barLayoutConnections do
		connection:Disconnect()
	end
	table.clear(barLayoutConnections)
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end
	beam:Destroy()
	beamStart:Destroy()
	beamEnd:Destroy()
	hint:Destroy()
	sideClick:Destroy()
	progressBar:Destroy()
	tutorialFrame.Visible = false
	spotlightFrame.Visible = false
	tutorialGui.Enabled = false
	showHudButtons()
	showOtherGuis()
end

-- Showers coloured rectangles down from above the screen, spinning and drifting as they fall; the gui removes itself afterwards.
local function playConfetti()
	local random = Random.new()
	local confettiGui = Instance.new("ScreenGui")
	confettiGui.Name = "TutorialConfetti"
	confettiGui.IgnoreGuiInset = true
	confettiGui.ResetOnSpawn = false
	confettiGui.DisplayOrder = DISPLAY_ORDER + 1
	confettiGui.Parent = playerGui

	for _ = 1, CONFETTI_COUNT do
		local length = random:NextNumber(CONFETTI_SIZE.Min, CONFETTI_SIZE.Max)
		local startX = random:NextNumber()
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(length, length * 0.5)
		piece.Position = UDim2.fromScale(startX, random:NextNumber(-0.25, -0.02))
		piece.Rotation = random:NextNumber(0, 360)
		piece.BackgroundColor3 = CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)]
		piece.Parent = confettiGui

		local fall = TweenInfo.new(random:NextNumber(CONFETTI_FALL_SECONDS.Min, CONFETTI_FALL_SECONDS.Max), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tweenService:Create(piece, fall, {
			Position = UDim2.new(startX, random:NextNumber(-CONFETTI_DRIFT, CONFETTI_DRIFT), 1.1, 0),
			Rotation = piece.Rotation + random:NextNumber(-CONFETTI_SPIN, CONFETTI_SPIN),
		}):Play()
	end
	debris:AddItem(confettiGui, CONFETTI_FALL_SECONDS.Max + 0.2)
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
	tutorialGui.DisplayOrder = DISPLAY_ORDER
	tutorialGui.Enabled = true
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
		setSideClick(false) -- the updater turns it back on (in the same frame) while the player should be shearing
		UPDATERS[stage]()
		if HIDE_UI_STAGES[stage] then
			hideOtherGuis()
		end
		task.wait(TICK_SECONDS)
	end

	stop()
	playConfetti()
	showCompleted()
end

tutorialGui.ResetOnSpawn = false -- CrookTutorialClient keeps using it after this script is done
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
	local unclaimed = 0
	for _, entry in entries do
		if entry.status == "Found" then
			unclaimed += 1
		end
	end
	indexUnclaimed = unclaimed
end)

-- The save has loaded once its numbers are mirrored onto the player.
while player:GetAttribute("Rebirths") == nil do
	player:GetAttributeChangedSignal("Rebirths"):Wait()
end

local forced = ALWAYS_IN_STUDIO and runService:IsStudio()
if forced then
	print("[TutorialClient] running from the start (ALWAYS_IN_STUDIO)")
	shearedBaseline = getNumberAttribute("SheepShearedCount")
	start("GoToSheep")
elseif getNumberAttribute("Rebirths") >= 1 or getNumberAttribute("Prestiges") >= 1 then
	stop()
else
	local sheared = getNumberAttribute("SheepShearedCount")
	local afterShearing: Stage = if ownsShears() then "Upgrades" else "GoToShop"
	start(if sheared >= SHEEP_TO_SHEAR then afterShearing elseif sheared >= 1 then "Shear" else "GoToSheep")
end
tutorialGui:SetAttribute(MAIN_DONE_ATTRIBUTE, true)
