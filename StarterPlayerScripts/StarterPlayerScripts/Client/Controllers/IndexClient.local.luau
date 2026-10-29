--[[
	The sheep Index (StarterGui.Index): the HUD's Index button opens it and every sheep type gets a card cloned from the Template.
	Selecting a card spins its sheep and fills the InfoFrame and RewardsFrame; found sheep are claimed there; IndexHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.IndexClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local alertPulse = require(script.Parent.Parent.Modules.AlertPulse)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local luckRain = require(script.Parent.Parent.Modules.LuckRain)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local sheepModels = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Sheeps")
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Index") :: GuiButton

local indexGui = playerGui:WaitForChild("Index") :: ScreenGui
local mainFrame = indexGui:WaitForChild("Main") :: GuiObject
local cardTemplate = mainFrame:FindFirstChild("Template", true) :: GuiObject
local cardContainer = cardTemplate.Parent :: GuiObject

-- The selected sheep's details.
local infoFrame = mainFrame:WaitForChild("InfoFrame")
local infoName = infoFrame:WaitForChild("SheepName") :: TextLabel
local infoRarity = infoFrame:WaitForChild("Rarity") :: TextLabel
local infoChances = infoFrame:WaitForChild("Chances") :: TextLabel
local infoViewport = infoFrame:WaitForChild("ViewportFrame") :: ViewportFrame

local rewardsFrame = mainFrame:FindFirstChild("RewardsFrame", true) :: GuiObject
local rewardAmount = rewardsFrame:WaitForChild("RewardAmount") :: TextLabel
local claimButton = rewardsFrame:WaitForChild("Claim") :: TextButton

local claimAllFrame = mainFrame:WaitForChild("ClaimAllFrame") :: GuiObject
local claimAllButton = claimAllFrame:WaitForChild("Claim") :: TextButton
local claimAllAmount = claimAllFrame:WaitForChild("RewardAmount") :: TextLabel
local claimAllMultiplier = claimAllFrame:WaitForChild("Multiplier") :: TextLabel

-- How many sheep types have been unlocked out of all of them.
local unlockBar = mainFrame:FindFirstChild("UnlockBar", true) :: GuiObject
local unlockProgress = unlockBar:WaitForChild("Progress") :: GuiObject
local unlockText = unlockBar:WaitForChild("ProgressText") :: TextLabel

-- Tier tabs under the Index: every button in TierTabs with a "Tier" attribute is a page showing only that tier's sheep.
local tierTabs = mainFrame:FindFirstChild("TierTabs")
local emptyTierLabel = mainFrame:FindFirstChild("EmptyTierLabel") :: TextLabel?

--// Sounds
local luckClaimedSound = soundService:WaitForChild("UISounds"):FindFirstChild("LuckClaimed")

--// Configs
local CLAIM_COLOR = Color3.fromRGB(255, 200, 40)
local CLAIMED_COLOR = Color3.fromRGB(90, 90, 90) -- "Claimed" text and the unusable Claim button
local LOCKED_TINT = Color3.new(0, 0, 0) -- undiscovered sheep show as a silhouette
local LOCKED_TEXT = "???"
local ALERT_COLOR = Color3.fromRGB(235, 50, 50)
local MODEL_FRONT_YAW = 0 -- turn this if a sheep model's face isn't on its front (-Z) side
local CAMERA_PITCH = math.rad(15)
local CAMERA_FOV = 40
local SPIN_SPEED = math.rad(60) -- per second, for the selected sheep
local MIN_SCALE_FACTOR = 0.05 -- below this the window is closing, so card sizes aren't measured
local CELLS_PER_ROW: number? = nil -- nil = however many fit the Studio CellSize/CellPadding X scale
local CELL_ASPECT_RATIO = 1.25 -- grid cell height / width
local DEFAULT_TIER = "Normal" -- the page the Index opens on
local INACTIVE_TAB_DARKEN = 0.4 -- how much darker the tabs that aren't open are
local UNLOCK_BAR_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Card = {
	id: string,
	frame: GuiObject,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	viewport: ViewportFrame?,
	entry: any,
}

type Preview = {
	model: Model,
	center: Vector3, -- spun around (the model's pivot sits at the origin)
}

--// State
local cards: { [string]: Card } = {}
local entries: { any } = {} -- the last IndexState from the server
local selectedId: string? = nil
local previews: { [ViewportFrame]: Preview } = {}
local spinConnection: RBXScriptConnection? = nil
local spinAngle = 0
local tierButtons: { [string]: GuiButton } = {}
local tierButtonColors: { [GuiButton]: Color3 } = {}
local currentTier: string? = nil -- nil = no tabs, so every sheep shows

local rewardAmountColor = rewardAmount.TextColor3
local claimButtonText = claimButton.Text
local claimButtonColor = claimButton.BackgroundColor3

-- Scale on Y inside a ScrollingFrame is relative to the canvas, so these are turned into pixels of the visible window.
local layout = cardContainer:FindFirstChildWhichIsA("UIGridStyleLayout")
local cardSize = cardTemplate.Size
local listPadding = if layout and layout:IsA("UIListLayout") then layout.Padding else nil
local gridCellSize = if layout and layout:IsA("UIGridLayout") then layout.CellSize else nil
local gridCellPadding = if layout and layout:IsA("UIGridLayout") then layout.CellPadding else nil
local gridColumns = CELLS_PER_ROW
if gridCellSize and gridCellPadding and not gridColumns then
	local stride = gridCellSize.X.Scale + gridCellPadding.X.Scale
	gridColumns = if stride > 0 then math.max(1, math.floor((1 + gridCellPadding.X.Scale) / stride + 1e-3)) else 4
end

--// Helpers ---------------------------------------------------------------------

-- The red "Alert" badge on the Index button: the one built in Studio, else a copy of the Rebirth button's, else a red dot.
local function getAlertBadge(): GuiObject
	local existing = openButton:FindFirstChild("Alert", true)
	if existing and existing:IsA("GuiObject") then
		return existing
	end

	local rebirthButton = hudButtons:FindFirstChild("Rebirth")
	local rebirthAlert = rebirthButton and rebirthButton:FindFirstChild("Alert", true)
	if rebirthAlert and rebirthAlert:IsA("GuiObject") then
		local badge = rebirthAlert:Clone()
		badge.Parent = openButton
		return badge
	end

	local badge = Instance.new("Frame")
	badge.Name = "Alert"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.9, 0.1)
	badge.Size = UDim2.fromScale(0.3, 0.3)
	badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
	badge.BackgroundColor3 = ALERT_COLOR
	badge.ZIndex = openButton.ZIndex + 5
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	badge.Parent = openButton
	return badge
end

local alertBadge = getAlertBadge()

-- 230756 -> "230,756"
local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

local function shake(gui: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(gui, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function pop(gui: GuiObject)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = gui
	end
	scale.Scale = 1.1
	tweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The Index tab a sheep is listed under (the server sends it; Baby<Type> ids fall back to "Baby").
local function getTier(entry: any): string
	if type(entry.tier) == "string" then
		return entry.tier
	end
	return if string.match(entry.id, "^Baby") then "Baby" else "Normal"
end

local function playLuckClaimedSound()
	if luckClaimedSound and luckClaimedSound:IsA("Sound") then
		luckClaimedSound:Play()
	end
end

--// Card sizing -------------------------------------------------------------------

local function toWindowPixels(size: UDim, windowHeight: number): UDim
	return UDim.new(0, math.floor(size.Offset + size.Scale * windowHeight))
end

-- The card window's visible height in Offset pixels; nil when it doesn't scroll or is shrunk by the close tween.
local function getWindowHeight(): (number?, number)
	local factor = windowsManager.getScaleFactor(cardContainer)
	if not cardContainer:IsA("ScrollingFrame") or factor <= MIN_SCALE_FACTOR then
		return nil, factor
	end
	return cardContainer.AbsoluteWindowSize.Y / factor, factor
end

-- The card window's usable width in Offset pixels, always leaving room for the scrollbar so showing it can't reflow the grid.
local function getWindowWidth(factor: number): number
	local scrollingFrame = cardContainer :: ScrollingFrame
	local width = scrollingFrame.AbsoluteSize.X / factor
	if scrollingFrame.VerticalScrollBarInset ~= Enum.ScrollBarInset.None then
		width -= scrollingFrame.ScrollBarThickness
	end

	local padding = cardContainer:FindFirstChildOfClass("UIPadding")
	if padding then
		width -= padding.PaddingLeft.Offset + padding.PaddingRight.Offset
		width *= 1 - padding.PaddingLeft.Scale - padding.PaddingRight.Scale
	end
	return width
end

-- Sizes the cards (and the layout's gaps) in pixels; grid rows always hold gridColumns cells whatever the screen.
local function updateCardSizes()
	local windowHeight, factor = getWindowHeight()
	if not windowHeight then
		return
	end

	if gridCellSize and gridCellPadding and gridColumns then
		local width = getWindowWidth(factor)
		local gapX = toWindowPixels(gridCellPadding.X, width).Offset
		local cellWidth = math.max(1, math.floor((width - gapX * (gridColumns - 1)) / gridColumns))
		local grid = layout :: UIGridLayout
		grid.CellSize = UDim2.fromOffset(cellWidth, math.floor(cellWidth * CELL_ASPECT_RATIO))
		grid.CellPadding = UDim2.new(UDim.new(0, gapX), toWindowPixels(gridCellPadding.Y, windowHeight))
		return
	end

	local height = toWindowPixels(cardSize.Y, windowHeight)
	for _, card in cards do
		card.frame.Size = UDim2.new(cardSize.X, height)
	end
	if listPadding then
		(layout :: UIListLayout).Padding = toWindowPixels(listPadding, windowHeight)
	end
end

-- Only when the cards don't fit does the canvas get taller (in pixels) so the player can scroll to the rest.
local function updateCanvasSize()
	local windowHeight, factor = getWindowHeight()
	if not windowHeight or not layout then
		return
	end

	local padding = cardContainer:FindFirstChildOfClass("UIPadding")
	local paddingY = 0
	if padding then
		paddingY = padding.PaddingTop.Offset + padding.PaddingTop.Scale * windowHeight
			+ padding.PaddingBottom.Offset + padding.PaddingBottom.Scale * windowHeight
	end

	local needed = math.ceil(layout.AbsoluteContentSize.Y / factor + paddingY)
	local canvasSize = UDim2.fromOffset(0, if needed > windowHeight then needed else 0)
	local scrollingFrame = cardContainer :: ScrollingFrame
	if scrollingFrame.CanvasSize ~= canvasSize then
		scrollingFrame.CanvasSize = canvasSize
	end
end

--// Previews ----------------------------------------------------------------------

local function clearPreview(viewport: ViewportFrame)
	previews[viewport] = nil
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

-- Turns a preview's sheep round its middle; 0 faces the camera.
local function setPreviewAngle(viewport: ViewportFrame, angle: number)
	local preview = previews[viewport]
	if preview then
		local center = preview.center
		preview.model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(-center))
	end
end

-- Puts a scriptless copy of the sheep model in a ViewportFrame, facing the camera.
local function buildPreview(viewport: ViewportFrame, sheepType: string)
	clearPreview(viewport)

	local babyModels = sheepModels:FindFirstChild("BabySheeps")
	local template = sheepModels:FindFirstChild(sheepType) or (babyModels and babyModels:FindFirstChild(sheepType))
	if not template or not template:IsA("Model") then
		return
	end

	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = viewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = CAMERA_FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- The camera sits off the model's front (-Z), a little above, looking back at it.
	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = boxCFrame.Position
	local distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(CAMERA_FOV / 2))
	local direction = (CFrame.Angles(0, math.pi + MODEL_FRONT_YAW, 0) * CFrame.Angles(-CAMERA_PITCH, 0, 0)).LookVector
	camera.CFrame = CFrame.lookAt(center - direction * distance, center)

	previews[viewport] = { model = model, center = center }
end

--// Spinning the selected sheep -------------------------------------------------------

local function onSpin(deltaTime: number)
	local card = if selectedId then cards[selectedId] else nil
	if not card then
		return
	end

	spinAngle = (spinAngle + deltaTime * SPIN_SPEED) % (math.pi * 2)
	setPreviewAngle(infoViewport, spinAngle)
	if card.viewport then
		setPreviewAngle(card.viewport, spinAngle)
	end
end

-- Only runs while the Index is open with a sheep selected.
local function startSpin()
	if not spinConnection and selectedId then
		spinConnection = runService.RenderStepped:Connect(onSpin)
	end
end

local function stopSpin()
	if spinConnection then
		spinConnection:Disconnect()
		spinConnection = nil
	end
end

--// Info panel --------------------------------------------------------------------

local function setInfoVisible(visible: boolean)
	infoName.Visible = visible
	infoRarity.Visible = visible
	infoChances.Visible = visible
	infoViewport.Visible = visible
	rewardsFrame.Visible = visible
end

-- Fills the InfoFrame and RewardsFrame for the selected sheep (hidden while nothing is selected).
local function renderInfo()
	local card = if selectedId then cards[selectedId] else nil
	if not card then
		setInfoVisible(false)
		return
	end

	local entry = card.entry
	local status = entry.status
	setInfoVisible(true)

	local locked = status == "Locked"
	infoName.Text = if locked then LOCKED_TEXT else entry.name
	infoRarity.Text = if locked then LOCKED_TEXT else entry.rarity
	infoRarity.TextColor3 = if locked then CLAIMED_COLOR else entry.color
	infoChances.Text = `1 in {formatWithCommas(entry.odds)}`
	infoViewport.ImageColor3 = if locked then LOCKED_TINT else Color3.new(1, 1, 1)

	if status == "Claimed" then
		rewardAmount.Text = "Claimed"
		rewardAmount.TextColor3 = CLAIMED_COLOR
	else
		rewardAmount.Text = `+{formatWithCommas(entry.indexLuck)}`
		rewardAmount.TextColor3 = rewardAmountColor
	end

	local canClaim = status == "Found"
	claimButton.AutoButtonColor = canClaim
	claimButton.BackgroundColor3 = if canClaim then claimButtonColor else CLAIMED_COLOR
	claimButton.Text = if status == "Claimed" then "Claimed" elseif status == "Locked" then "Locked" else claimButtonText
end

-- The newly selected sheep starts spinning from facing the camera; the one it replaces turns back to face it.
local function selectCard(card: Card)
	if selectedId ~= card.id then
		local previous = if selectedId then cards[selectedId] else nil
		if previous and previous.viewport then
			setPreviewAngle(previous.viewport, 0)
		end

		selectedId = card.id
		spinAngle = 0
		buildPreview(infoViewport, card.id)
	end
	renderInfo()
	startSpin()
end

-- The given sheep if it's waiting to be claimed, else the first one that is (in index order).
local function findUnclaimed(id: string?): Card?
	local card = if id then cards[id] else nil
	if card and card.entry.status == "Found" then
		return card
	end
	for _, entry in entries do
		if entry.status == "Found" then
			return cards[entry.id]
		end
	end
	return nil
end ---------------------------------------------------------------------

-- Shows only the open tier's cards, lights up its tab and dims the others.
local function renderTier()
	local shown = 0
	for _, card in cards do
		local visible = currentTier == nil or getTier(card.entry) == currentTier
		card.frame.Visible = visible
		if visible then
			shown += 1
		end
	end

	if emptyTierLabel then
		emptyTierLabel.Visible = #entries > 0 and shown == 0
	end

	for tier, button in tierButtons do
		local color = tierButtonColors[button]
		button.BackgroundColor3 = if tier == currentTier then color else color:Lerp(Color3.new(0, 0, 0), INACTIVE_TAB_DARKEN)
	end
end

-- Opens a tier's page; a selected sheep from another tier is let go.
local function setTier(tier: string)
	if tier == currentTier then
		return
	end
	currentTier = tier

	local selected = if selectedId then cards[selectedId] else nil
	if selected and getTier(selected.entry) ~= tier then
		if selected.viewport then
			setPreviewAngle(selected.viewport, 0)
		end
		selectedId = nil
		clearPreview(infoViewport)
		renderInfo()
	end

	if cardContainer:IsA("ScrollingFrame") then
		cardContainer.CanvasPosition = Vector2.zero
	end
	renderTier()
	task.defer(updateCanvasSize)
end

-- Shows ClaimAllFrame while more than one sheep is waiting to be claimed.
local function renderClaimAll()
	local count, luck = 0, 0
	for _, entry in entries do
		if entry.status == "Found" then
			count += 1
			luck += entry.indexLuck
		end
	end

	claimAllFrame.Visible = count > 1
	claimAllMultiplier.Text = `X{count}`
	claimAllAmount.Text = `+{formatWithCommas(luck)}`

	alertBadge.Visible = count > 0
end

-- Opens a sheep waiting to be claimed in the InfoFrame (on its tier's page); with none waiting the selection stays as it is.
local function focusUnclaimed(id: string?)
	local card = findUnclaimed(id)
	if not card then
		return
	end
	if currentTier then
		setTier(getTier(card.entry))
	end
	selectCard(card)
end

-- Fills the UnlockBar with the share of sheep types that aren't Locked any more.
local function renderUnlockBar()
	local unlocked = 0
	for _, entry in entries do
		if entry.status ~= "Locked" then
			unlocked += 1
		end
	end

	local total = #entries
	local ratio = if total > 0 then unlocked / total else 0
	local size = unlockProgress.Size
	tweenService:Create(unlockProgress, UNLOCK_BAR_TWEEN, { Size = UDim2.new(ratio, 0, size.Y.Scale, size.Y.Offset) }):Play()
	unlockText.Text = `{unlocked}/{total}`
end

--// Cards -------------------------------------------------------------------------

local function refreshCard(card: Card)
	local entry = card.entry
	local status = entry.status

	local locked = status == "Locked"
	card.nameLabel.Text = if locked then LOCKED_TEXT else entry.name
	if card.viewport then
		card.viewport.ImageColor3 = if locked then LOCKED_TINT else Color3.new(1, 1, 1)
	end

	if locked then
		card.rarityLabel.Text = LOCKED_TEXT
		card.rarityLabel.TextColor3 = CLAIMED_COLOR
	elseif status == "Found" then
		card.rarityLabel.Text = "Claim"
		card.rarityLabel.TextColor3 = CLAIM_COLOR
	else
		card.rarityLabel.Text = entry.rarity
		card.rarityLabel.TextColor3 = entry.color
	end
end

local function createCard(entry: any, order: number): Card
	local frame = cardTemplate:Clone()
	frame.Name = entry.id
	frame.LayoutOrder = order
	frame.Visible = true

	local windowHeight = getWindowHeight()
	if windowHeight and not gridCellSize then
		frame.Size = UDim2.new(cardSize.X, toWindowPixels(cardSize.Y, windowHeight))
	end

	local viewport = frame:FindFirstChildOfClass("ViewportFrame")
	local card: Card = {
		id = entry.id,
		frame = frame,
		nameLabel = frame:WaitForChild("ItemName") :: TextLabel,
		rarityLabel = frame:WaitForChild("Rarity") :: TextLabel,
		viewport = viewport,
		entry = entry,
	}

	if viewport then
		buildPreview(viewport, entry.id)
	end

	-- The Template isn't a button, so an invisible one covering the card takes the clicks.
	local button: GuiButton
	if frame:IsA("GuiButton") then
		button = frame
	else
		local overlay = Instance.new("TextButton")
		overlay.Name = "SelectButton"
		overlay.Text = ""
		overlay.BackgroundTransparency = 1
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ZIndex = frame.ZIndex + 10
		overlay.Parent = frame
		button = overlay
	end
	button.Activated:Connect(function()
		selectCard(card)
	end)

	frame.Parent = cardContainer
	return card
end

local function render()
	for order, entry in entries do
		local card = cards[entry.id]
		if card then
			card.entry = entry
		else
			card = createCard(entry, order)
			cards[entry.id] = card
		end
		refreshCard(card)
	end

	renderTier()
	renderInfo()
	renderClaimAll()
	renderUnlockBar()
	task.defer(updateCanvasSize)
end

--// Setup -------------------------------------------------------------------------------

local indexWindow = windowsManager.register("Index", {
	gui = indexGui,
	frame = mainFrame,
	openButton = openButton,
	onOpen = function()
		network.fireServer(network.RemoteEvents.RequestIndexState)
		focusUnclaimed(selectedId)
		startSpin()
	end,
	onClose = stopSpin,
})

cardTemplate.Visible = false

if tierTabs then
	for _, button in tierTabs:GetChildren() do
		local tier = button:GetAttribute("Tier")
		if button:IsA("GuiButton") and type(tier) == "string" then
			tierButtons[tier] = button
			tierButtonColors[button] = button.BackgroundColor3
			button.Activated:Connect(function()
				pop(button)
				setTier(tier)
			end)
		end
	end
	currentTier = if tierButtons[DEFAULT_TIER] then DEFAULT_TIER else next(tierButtons)
end
renderTier()
claimAllFrame.Visible = false
alertBadge.Visible = false
alertPulse.attach(alertBadge)
setInfoVisible(false)

if cardContainer:IsA("ScrollingFrame") then
	cardContainer.AutomaticCanvasSize = Enum.AutomaticSize.None -- updateCanvasSize sizes it instead
	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
	end
	cardContainer:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
		updateCardSizes()
		updateCanvasSize()
	end)
	updateCardSizes()
end

claimButton.Activated:Connect(function()
	local card = if selectedId then cards[selectedId] else nil
	if card and card.entry.status == "Found" then
		network.fireServer(network.RemoteEvents.ClaimIndexReward, card.id)
	else
		shake(claimButton)
	end
end)

claimAllButton.Activated:Connect(function()
	network.fireServer(network.RemoteEvents.ClaimAllIndexRewards)
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.IndexState, function(newEntries: any)
	entries = newEntries
	render()
end)

network.connectEvent(network.RemoteEvents.IndexClaimResult, function(id: string, success: boolean, _reason: string?, count: number?)
	if id == "All" then
		if success then
			local claimed = if type(count) == "number" then count else 1
			pop(claimAllFrame)
			playLuckClaimedSound()
			luckRain.play(indexGui)
			announcements.show("ClaimAlert", if claimed > 1 then `Claimed {claimed} sheeps` else "Claimed 1 sheep")
		else
			shake(claimAllButton)
		end
		return
	end

	local card = cards[id]
	if not card then
		return
	end
	if success then
		pop(card.frame)
		playLuckClaimedSound()
		luckRain.play(indexGui)
		announcements.show("ClaimAlert", "Claimed 1 sheep")
		-- The SheepIndex change already pushed IndexState, so the claimed sheep reads "Claimed" by now.
		if indexWindow.isOpen() then
			focusUnclaimed()
		end
	else
		shake(claimButton)
	end
end)

-- IndexState with the new "Found" sheep arrives just before this.
network.connectEvent(network.RemoteEvents.SheepUnlocked, function(sheepType: string)
	if indexWindow.isOpen() then
		focusUnclaimed(sheepType)
	end
end)

network.fireServer(network.RemoteEvents.RequestIndexState)
