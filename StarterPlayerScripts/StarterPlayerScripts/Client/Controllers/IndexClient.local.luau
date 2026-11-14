--[[
	The sheep Index (StarterGui.Index.IndexFrame): a Mutations tab per page the server lists (Normal + MutationData) and a SheepTemplate card per sheep type.
	Selecting a card spins its sheep and fills SheepInfo and RewardFrame; found entries are claimed there or all at once with Claim All; IndexHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.IndexClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
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
local sheepModels = require(script.Parent.Parent.Modules.SheepModels)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Index") :: GuiButton

local indexGui = playerGui:WaitForChild("Index") :: ScreenGui
local indexFrame = indexGui:WaitForChild("IndexFrame") :: GuiObject -- the whole window, opened and closed by WindowsManager
local exitButton = indexFrame:WaitForChild("ExitButton") :: GuiButton
local mainFrame = indexFrame:WaitForChild("Main") :: GuiObject -- the window body holding everything below
local cardContainer = mainFrame:WaitForChild("ScrollingFrame") :: GuiObject
local cardTemplate = cardContainer:WaitForChild("SheepTemplate") :: GuiObject
local tabsFrame = mainFrame:WaitForChild("Mutations") :: GuiObject -- a tab Frame per page, each with an invisible ImageButton over it

-- The selected sheep's details.
local infoFrame = mainFrame:WaitForChild("SheepInfo")
local infoName = infoFrame:WaitForChild("SheepName") :: TextLabel
local infoRarity = infoFrame:WaitForChild("Rarity") :: TextLabel
local infoChances = infoFrame:WaitForChild("Chance") :: TextLabel
local infoViewport = infoFrame:WaitForChild("ViewportFrame") :: ViewportFrame

local rewardsFrame = mainFrame:WaitForChild("RewardFrame") :: GuiObject
local rewardAmount = rewardsFrame:WaitForChild("ClaimAmount") :: TextLabel
local claimButton = rewardsFrame:WaitForChild("BuyButton") :: ImageButton

-- Claim All: shown with 2+ found sheep; ClaimAmount is their combined Luck, the button's Amount is how many.
local claimAllFrame = mainFrame:WaitForChild("ClaimAll") :: GuiObject -- popped/shaken instead of its button, which ButtonClient tweens
local claimAllButton = claimAllFrame:WaitForChild("ClaimAllButton") :: ImageButton
local claimAllCountLabel = claimAllButton:WaitForChild("Amount") :: TextLabel
local claimAllLuckLabel = claimAllFrame:WaitForChild("ClaimAmount") :: TextLabel

-- How many sheep types have been unlocked out of all of them.
local unlockBar = mainFrame:WaitForChild("ProgressFrame") :: GuiObject
local unlockTrack = unlockBar:WaitForChild("Background") :: GuiObject
local unlockProgress = unlockBar:WaitForChild("ProgressBar") :: GuiObject
local unlockText = unlockBar:WaitForChild("IndexAmount") :: TextLabel

--// Sounds
local luckClaimedSound = soundService:WaitForChild("UISounds"):FindFirstChild("LuckClaimed")

--// Configs
local CLAIM_COLOR = Color3.fromRGB(255, 200, 40)
local CLAIMED_COLOR = Color3.fromRGB(90, 90, 90) -- "Claimed" text and the tint on the unusable BuyButton
local LOCKED_TINT = Color3.new(0, 0, 0) -- undiscovered sheep show as a silhouette
local LOCKED_TEXT = "???"
local ALERT_COLOR = Color3.fromRGB(235, 50, 50)
local MODEL_FRONT_YAW = 0 -- turn this if a sheep model's face isn't on its front (-Z) side
local CAMERA_PITCH = math.rad(15)
local CAMERA_FOV = 40
local PREVIEW_FILL = { Baby = 0.55, Giant = 1 } -- how much of the frame each variant fills, so Giants look biggest
local ADULT_PREVIEW_FILL = 0.75
local SPIN_SPEED = math.rad(60) -- per second, for the selected sheep
local UNLOCK_BAR_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local NORMAL_PAGE = "Normal" -- mirrors IndexHandler; the page shown on open
local RAINBOW_TAG = "RainbowName" -- mirrors MutationData.RainbowGradientTag (MutationClient animates it)
local MUTATION_TINT = 0.6 -- how far a mutated sheep's preview is tinted toward its mutation's colour
local TAB_SELECTED_SCALE = 1.08
local TAB_IDLE_SCALE = 1
local TAB_PRESSED_SCALE = 0.9
local TAB_DIM = 0.45 -- how far an unselected tab's background darkens
local TAB_SCALE_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TAB_COLOR_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAB_PRESS_TWEEN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TAB_DOT_NAME = "ClaimDot"
local TAB_DOT_SIZE = 0.3 -- of the tab's height

type Card = {
	id: string, -- sheep type: one card per type, refilled with the current page's entry
	frame: GuiObject,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	viewport: ViewportFrame?,
	nameRainbow: UIGradient,
	previewRainbow: UIGradient,
	entry: any,
}

type Preview = {
	model: Model,
	center: Vector3, -- spun around (the model's pivot sits at the origin)
}

type Page = { -- IndexHandler.PageInfo
	id: string,
	color: Color3,
	rainbow: boolean,
}

type Tab = {
	frame: GuiObject,
	scale: UIScale, -- on the frame, so it never fights ButtonClient's UIScale on the ImageButton
	dot: GuiObject, -- shown while the page has something to claim
	baseColor: Color3,
}

--// State
local cards: { [string]: Card } = {}
local pages: { Page } = {} -- from the last IndexState, in tab order
local pagesById: { [string]: Page } = {}
local pageEntries: { [string]: { any } } = {} -- page id -> its entries in index order
local entriesByKey: { [string]: any } = {} -- SheepIndex key -> entry
local tabs: { [string]: Tab } = {}
local currentPage = NORMAL_PAGE
local selectedId: string? = nil -- sheep type of the selected card on the current page
local previews: { [ViewportFrame]: Preview } = {}
local spinConnection: RBXScriptConnection? = nil
local spinAngle = 0

local rewardAmountColor = rewardAmount.TextColor3
local claimButtonImageColor = claimButton.ImageColor3


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

local function playLuckClaimedSound()
	if luckClaimedSound and luckClaimedSound:IsA("Sound") then
		luckClaimedSound:Play()
	end
end

--// Mutation looks ----------------------------------------------------------------

local function newRainbowGradient(): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "MutationRainbow"
	collectionService:AddTag(gradient, RAINBOW_TAG)
	return gradient
end

-- Parents the rainbow only while it's wanted (MutationClient only animates parented ones), never over a Studio gradient.
local function setRainbow(gui: GuiObject, gradient: UIGradient, enabled: boolean)
	local designed = false
	for _, child in gui:GetChildren() do
		if child:IsA("UIGradient") and child ~= gradient then
			designed = true
			break
		end
	end
	gradient.Parent = if enabled and not designed then gui else nil
end

local infoNameRainbow = newRainbowGradient()
local infoPreviewRainbow = newRainbowGradient()

-- A found entry on a rainbow page gets the scrolling rainbow on its name and preview.
local function isRainbow(entry: any): boolean
	local page = pagesById[entry.mutation]
	return entry.status ~= "Locked" and page ~= nil and page.rainbow
end

-- "Galaxy Basic Sheep" with the mutation in its colour (RichText); a rainbow page's stays plain so its gradient colours it.
local function getDisplayName(entry: any): string
	local page = pagesById[entry.mutation]
	if not page or page.id == NORMAL_PAGE then
		return entry.name
	elseif page.rainbow then
		return `{page.id} {entry.name}`
	end
	return `<font color="#{page.color:ToHex()}">{page.id}</font> {entry.name}`
end

-- Locked sheep are silhouettes; mutated ones are tinted toward their mutation's colour (ViewportFrames can't show its VFX).
local function getPreviewTint(entry: any): Color3
	if entry.status == "Locked" then
		return LOCKED_TINT
	end
	local page = pagesById[entry.mutation]
	if not page or page.id == NORMAL_PAGE or page.rainbow then
		return WHITE
	end
	return WHITE:Lerp(page.color, MUTATION_TINT)
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

-- Puts a scriptless copy of the sheep model in a ViewportFrame, facing the camera and filling as much of it as its variant does.
local function buildPreview(viewport: ViewportFrame, entry: any)
	clearPreview(viewport)

	local template = sheepModels.find(entry.id)
	if not template then
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
	local fill = PREVIEW_FILL[entry.variant] or ADULT_PREVIEW_FILL
	local distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(CAMERA_FOV / 2)) / fill
	local direction = (CFrame.Angles(0, math.pi + MODEL_FRONT_YAW, 0) * CFrame.Angles(-CAMERA_PITCH, 0, 0)).LookVector
	camera.CFrame = CFrame.lookAt(center - direction * distance, center)

	previews[viewport] = { model = model, center = center }

	-- SheepInfo's Studio background is only a placeholder until a sheep is in it.
	if viewport == infoViewport then
		viewport.BackgroundTransparency = 1
	end
end

--[[
	Card previews are built lazily, a few per frame while the Index is open, so joining never clones every sheep model at once
	(that was a big hitch on load). After joining they also trickle in slowly in the background, so a first open is quick too.
]]
local PREVIEWS_PER_FRAME = 3
local BACKGROUND_DELAY = 20 -- seconds after the first IndexState before background building starts
local BACKGROUND_INTERVAL = 0.3

local previewQueue: { Card } = {}
local queuedPreviews: { [Card]: boolean } = {}
local previewConnection: RBXScriptConnection? = nil
local backgroundStarted = false
local isIndexOpen: () -> boolean = function()
	return false
end -- replaced once the window is registered

-- Builds the next still-wanted preview in the queue; false once it's empty.
local function buildNextPreview(): boolean
	while #previewQueue > 0 do
		local card = table.remove(previewQueue, 1) :: Card
		if queuedPreviews[card] and card.viewport and cards[card.id] == card then
			queuedPreviews[card] = nil
			buildPreview(card.viewport, card.entry)
			return true
		end
		queuedPreviews[card] = nil
	end
	return false
end

local function stepPreviews()
	if isIndexOpen() then
		for _ = 1, PREVIEWS_PER_FRAME do
			if not buildNextPreview() then
				break
			end
		end
	end
	if #previewQueue == 0 and previewConnection then
		previewConnection:Disconnect()
		previewConnection = nil
	end
end

local function queuePreview(card: Card)
	if not card.viewport or queuedPreviews[card] then
		return
	end
	queuedPreviews[card] = true
	table.insert(previewQueue, card)
	if not previewConnection then
		previewConnection = runService.Heartbeat:Connect(stepPreviews)
	end
	if not backgroundStarted then
		backgroundStarted = true
		task.delay(BACKGROUND_DELAY, function()
			while buildNextPreview() do
				task.wait(BACKGROUND_INTERVAL)
			end
		end)
	end
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

-- Fills SheepInfo and RewardFrame for the selected sheep (hidden while nothing is selected).
local function renderInfo()
	local card = if selectedId then cards[selectedId] else nil
	if not card then
		setInfoVisible(false)
		setRainbow(infoName, infoNameRainbow, false)
		setRainbow(infoViewport, infoPreviewRainbow, false)
		return
	end

	local entry = card.entry
	local status = entry.status
	setInfoVisible(true)

	local locked = status == "Locked"
	local rainbow = isRainbow(entry)
	infoName.Text = if locked then LOCKED_TEXT else getDisplayName(entry)
	setRainbow(infoName, infoNameRainbow, rainbow)
	infoRarity.Text = if locked then LOCKED_TEXT else entry.rarity
	infoRarity.TextColor3 = if locked then CLAIMED_COLOR else entry.color
	infoChances.Text = if entry.halloween
		then `1 in {formatWithCommas(entry.odds)} (Halloween only)`
		else `1 in {formatWithCommas(entry.odds)}`
	infoViewport.ImageColor3 = getPreviewTint(entry)
	setRainbow(infoViewport, infoPreviewRainbow, rainbow)

	-- BuyButton's "CLAIM" is baked into its image, so ClaimAmount carries the state.
	if status == "Claimed" or locked then
		rewardAmount.Text = if locked then "Locked" else "Claimed"
		rewardAmount.TextColor3 = CLAIMED_COLOR
	else
		rewardAmount.Text = `+{formatWithCommas(entry.indexLuck)}`
		rewardAmount.TextColor3 = rewardAmountColor
	end

	local canClaim = status == "Found"
	claimButton.AutoButtonColor = canClaim
	claimButton.Active = canClaim
	claimButton.ImageColor3 = if canClaim then claimButtonImageColor else CLAIMED_COLOR
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
		buildPreview(infoViewport, card.entry)
	end
	renderInfo()
	startSpin()
end

-- Nothing selected: the spinning sheep turns back to face the camera and SheepInfo's preview is dropped.
local function clearSelection()
	local previous = if selectedId then cards[selectedId] else nil
	if previous and previous.viewport then
		setPreviewAngle(previous.viewport, 0)
	end
	selectedId = nil
	spinAngle = 0
	stopSpin()
	clearPreview(infoViewport)
end

local function findFound(list: { any }?): any?
	for _, entry in list or {} do
		if entry.status == "Found" then
			return entry
		end
	end
	return nil
end

-- The given entry if it's waiting to be claimed, else the first that is: on the current page first, then the other tabs in order.
local function findUnclaimed(key: string?): any?
	local entry = if key then entriesByKey[key] else nil
	if entry and entry.status == "Found" then
		return entry
	end
	local found = findFound(pageEntries[currentPage])
	if found then
		return found
	end
	for _, page in pages do
		found = if page.id ~= currentPage then findFound(pageEntries[page.id]) else nil
		if found then
			return found
		end
	end
	return nil
end

-- Shows the HUD button's Alert badge while any page has an entry waiting to be claimed.
local function renderAlertBadge()
	alertBadge.Visible = findUnclaimed() ~= nil
end

-- How many entries (on every page) are waiting to be claimed, and their combined Luck.
local function countClaimable(): (number, number)
	local count, luck = 0, 0
	for _, entry in entriesByKey do
		if entry.status == "Found" then
			count += 1
			luck += entry.indexLuck or 0
		end
	end
	return count, luck
end

-- Claim All only shows with more than one sheep to claim; a single one is claimed from RewardFrame.
local function renderClaimAll()
	local count, luck = countClaimable()
	claimAllFrame.Visible = count > 1
	claimAllCountLabel.Text = tostring(count)
	claimAllLuckLabel.Text = `+{formatWithCommas(luck)}`
end

-- Fills ProgressFrame's ProgressBar with the share of the current page's entries that aren't Locked any more.
local function renderUnlockBar()
	local list = pageEntries[currentPage] or {}
	local unlocked = 0
	for _, entry in list do
		if entry.status ~= "Locked" then
			unlocked += 1
		end
	end

	local total = #list
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
	local rainbow = isRainbow(entry)
	card.nameLabel.Text = if locked then LOCKED_TEXT else getDisplayName(entry)
	setRainbow(card.nameLabel, card.nameRainbow, rainbow)
	if card.viewport then
		card.viewport.ImageColor3 = getPreviewTint(entry)
		setRainbow(card.viewport, card.previewRainbow, rainbow)
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

	local viewport = frame:FindFirstChildOfClass("ViewportFrame")
	local card: Card = {
		id = entry.id,
		frame = frame,
		nameLabel = frame:WaitForChild("SheepName") :: TextLabel,
		rarityLabel = frame:WaitForChild("Rarity") :: TextLabel,
		viewport = viewport,
		nameRainbow = newRainbowGradient(),
		previewRainbow = newRainbowGradient(),
		entry = entry,
	}
	card.nameLabel.RichText = true -- the mutation prefix is coloured

	queuePreview(card)

	-- SheepTemplate isn't a button, so an invisible one covering the card takes the clicks.
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

-- Its preview model goes with it, so nothing is left in `previews`.
local function removeCard(card: Card)
	if card.viewport then
		clearPreview(card.viewport)
	end
	queuedPreviews[card] = nil
	card.nameRainbow:Destroy()
	card.previewRainbow:Destroy()
	card.frame:Destroy()
end

--// Tabs --------------------------------------------------------------------------

-- Selected tab larger and bright, the rest dimmed; each shows a dot while its page has something to claim.
local function renderTabs()
	for id, tab in tabs do
		local selected = id == currentPage
		tweenService:Create(tab.scale, TAB_SCALE_TWEEN, { Scale = if selected then TAB_SELECTED_SCALE else TAB_IDLE_SCALE }):Play()
		tweenService:Create(tab.frame, TAB_COLOR_TWEEN, {
			BackgroundColor3 = if selected then tab.baseColor else tab.baseColor:Lerp(BLACK, TAB_DIM),
		}):Play()
		tab.dot.Visible = findFound(pageEntries[id]) ~= nil
	end
end

-- Cards are one per sheep type and refilled with the current page's entries, so switching tabs never rebuilds previews.
local function render()
	local list = pageEntries[currentPage] or {}
	local shown: { [string]: boolean } = {}
	for order, entry in list do
		shown[entry.id] = true
		local card = cards[entry.id]
		if card then
			card.entry = entry
			card.frame.LayoutOrder = order
		else
			card = createCard(entry, order)
			cards[entry.id] = card
		end
		refreshCard(card)
	end

	for id, card in cards do
		if not shown[id] then
			if selectedId == id then
				clearSelection()
			end
			removeCard(card)
			cards[id] = nil
		end
	end

	renderInfo()
	renderAlertBadge()
	renderClaimAll()
	renderTabs()
	renderUnlockBar()
end

-- With nothing selected, the page's first card is, so SheepInfo and RewardFrame never sit empty.
local function selectFirstCard()
	if selectedId and cards[selectedId] then
		return
	end
	local first = (pageEntries[currentPage] or {})[1]
	local card = first and cards[first.id]
	if card then
		selectCard(card)
	end
end

-- Switching pages clears the selection (and its spinning preview), scrolls back to the top and selects the first card.
local function setPage(pageId: string)
	if pageId == currentPage or not pagesById[pageId] then
		return
	end
	clearSelection()
	currentPage = pageId
	if cardContainer:IsA("ScrollingFrame") then
		cardContainer.CanvasPosition = Vector2.zero
	end
	render()
	selectFirstCard()
end

-- Opens an entry waiting to be claimed in SheepInfo, switching to its page; with none waiting the selection stays as it is.
local function focusUnclaimed(key: string?)
	local entry = findUnclaimed(key)
	if not entry then
		return
	end
	setPage(entry.mutation)
	local card = cards[entry.id]
	if card then
		selectCard(card)
	end
end

local function findEntry(pageId: string, sheepType: string): any?
	for _, entry in pageEntries[pageId] or {} do
		if entry.id == sheepType then
			return entry
		end
	end
	return nil
end

-- A gradient for a cloned tab: lighter to darker shades of its page's colour, or a fixed rainbow.
local function getTabColors(page: Page, darken: number): ColorSequence
	if page.rainbow then
		local keypoints = table.create(7)
		for i = 0, 6 do
			keypoints[i + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.65, 1 - darken))
		end
		return ColorSequence.new(keypoints)
	end
	local base = page.color:Lerp(BLACK, darken)
	return ColorSequence.new(base:Lerp(WHITE, 0.25), base:Lerp(BLACK, 0.35))
end

-- Colours a tab cloned for a page that has none in Studio: its background gradient and a darker outline.
local function paintTab(frame: GuiObject, page: Page)
	local gradient = frame:FindFirstChildOfClass("UIGradient")
	if gradient then
		frame.BackgroundColor3 = WHITE
		gradient.Color = getTabColors(page, 0)
	else
		frame.BackgroundColor3 = page.color
	end

	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local strokeGradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
	if stroke and strokeGradient then
		stroke.Color = WHITE
		strokeGradient.Color = getTabColors(page, 0.5)
	elseif stroke then
		stroke.Color = page.color:Lerp(BLACK, 0.5)
	end
end

-- UI text rule: the tab's label is always white with a black outline.
local function styleTabLabel(frame: GuiObject)
	local label = frame:FindFirstChildWhichIsA("TextLabel")
	if not label then
		return
	end
	label.TextColor3 = WHITE
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Parent = label
end

local function getTabDot(frame: GuiObject): GuiObject
	local existing = frame:FindFirstChild(TAB_DOT_NAME) -- a cloned tab brings its template's
	if existing and existing:IsA("GuiObject") then
		return existing
	end

	local dot = Instance.new("Frame")
	dot.Name = TAB_DOT_NAME
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.06, 0.2) -- the outer corner, since the tabs hang off the window's left edge
	dot.Size = UDim2.fromScale(TAB_DOT_SIZE, TAB_DOT_SIZE)
	dot.SizeConstraint = Enum.SizeConstraint.RelativeYY
	dot.BackgroundColor3 = ALERT_COLOR
	dot.ZIndex = frame.ZIndex + 20
	dot.Visible = false
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	local outline = Instance.new("UIStroke")
	outline.Color = BLACK
	outline.Thickness = 1.5
	outline.Parent = dot
	dot.Parent = frame
	return dot
end

-- The tab's own invisible ImageButton, else an invisible overlay like the cards'.
local function getTabButton(frame: GuiObject): GuiButton
	local existing = frame:FindFirstChildWhichIsA("GuiButton")
	if existing then
		return existing
	end
	local overlay = Instance.new("TextButton")
	overlay.Name = "TabButton"
	overlay.Text = ""
	overlay.BackgroundTransparency = 1
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = frame.ZIndex + 10
	overlay.Parent = frame
	return overlay
end

-- A quick squash on the frame's UIScale, then back to the tab's selected/idle size.
local function pressTab(tab: Tab)
	local press = tweenService:Create(tab.scale, TAB_PRESS_TWEEN, { Scale = TAB_PRESSED_SCALE })
	press.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			renderTabs()
		end
	end)
	press:Play()
end

local function setupTab(frame: GuiObject, page: Page)
	local tab: Tab = {
		frame = frame,
		scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale"),
		dot = getTabDot(frame),
		baseColor = frame.BackgroundColor3,
	}
	tab.scale.Parent = frame
	alertPulse.attach(tab.dot)
	styleTabLabel(frame)
	tabs[page.id] = tab

	getTabButton(frame).Activated:Connect(function()
		setPage(page.id)
		pressTab(tab)
	end)
end

--[[
	The tabs come from the server's page list (Normal + MutationData, rarest first), not from Studio: a page with no tab
	frame gets a clone of an existing one in its colour, and a Studio tab with no page is hidden but kept.
]]
local function buildTabs()
	local frames: { [string]: GuiObject } = {}
	for _, child in tabsFrame:GetChildren() do
		if child:IsA("GuiObject") then
			frames[child.Name] = child
		end
	end

	-- Cloned from a Studio mutation tab (Normal's only if there's none), before any of them is dimmed.
	local template: GuiObject? = nil
	for _, page in pages do
		local frame = frames[page.id]
		if frame and (not template or page.id ~= NORMAL_PAGE) then
			template = frame
		end
	end

	for order, page in pages do
		if tabs[page.id] then
			continue
		end
		local frame = frames[page.id]
		if not frame and template then
			local clone = template:Clone()
			clone.Name = page.id
			local label = clone:FindFirstChildWhichIsA("TextLabel")
			if label then
				label.Text = page.id
			end
			paintTab(clone, page)
			clone.Parent = tabsFrame
			frame = clone
		end
		if frame then
			frame.LayoutOrder = order - 1
			frame.Visible = true
			setupTab(frame, page)
		end
	end

	-- e.g. Thunder: its tab waits (hidden) for a MutationData entry, which gives it a page with no other change.
	for name, frame in frames do
		if not pagesById[name] then
			frame.Visible = false
		end
	end
end

--// Setup -------------------------------------------------------------------------------

local indexWindow = windowsManager.register("Index", {
	gui = indexGui,
	frame = indexFrame,
	openButton = openButton,
	closeButton = exitButton, -- WindowsManager only finds a button named "Exit" on its own
	-- Opens on Normal; only if Normal has nothing to claim does it jump to a page that has (so Claim is always reachable).
	onOpen = function()
		network.fireServer(network.RemoteEvents.RequestIndexState)
		setPage(NORMAL_PAGE)
		local selected = if selectedId and cards[selectedId] then cards[selectedId].entry.key else nil
		focusUnclaimed(selected)
		selectFirstCard()
		startSpin()
	end,
	onClose = stopSpin,
})
isIndexOpen = indexWindow.isOpen

cardTemplate.Visible = false
alertBadge.Visible = false
alertPulse.attach(alertBadge)
setInfoVisible(false)
renderClaimAll()
infoName.RichText = true -- the mutation prefix is coloured

-- The tabs sit in MutationData order (LayoutOrder from buildTabs), whatever their Studio names sort to.
local tabLayout = tabsFrame:FindFirstChildOfClass("UIListLayout")
if tabLayout then
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
end

-- ProgressBar draws over its Background and IndexAmount over both; only raised (with a warning) if the import layered them wrong.
for _, pair in { { unlockTrack, unlockProgress }, { unlockProgress, unlockText } } do
	local lower, upper = pair[1], pair[2]
	if upper.ZIndex <= lower.ZIndex then
		warn(`[IndexClient] {upper:GetFullName()} is not above {lower.Name} (ZIndex {upper.ZIndex} <= {lower.ZIndex}); raised it in code`)
		upper.ZIndex = lower.ZIndex + 1
	end
end

-- ProgressBar's Studio width is a placeholder, so it starts empty until the first IndexState.
local progressSize = unlockProgress.Size
unlockProgress.Size = UDim2.new(0, 0, progressSize.Y.Scale, progressSize.Y.Offset)

claimButton.Activated:Connect(function()
	local card = if selectedId then cards[selectedId] else nil
	if card and card.entry.status == "Found" then
		network.fireServer(network.RemoteEvents.ClaimIndexReward, card.entry.key)
	else
		shake(claimButton)
	end
end)

claimAllButton.Activated:Connect(function()
	if countClaimable() > 0 then
		network.fireServer(network.RemoteEvents.ClaimAllIndexRewards)
	else
		shake(claimAllFrame)
	end
end)

network.waitUntilReadyAsync()

-- Every page's entries at once, plus the tab list (IndexHandler.PageInfo) they're grouped by.
network.connectEvent(network.RemoteEvents.IndexState, function(newEntries: { any }, newPages: { Page }?)
	pages = if type(newPages) == "table" and #newPages > 0 then newPages else { { id = NORMAL_PAGE, color = WHITE, rainbow = false } }
	pagesById = {}
	for _, page in pages do
		pagesById[page.id] = page
	end

	pageEntries = {}
	entriesByKey = {}
	for _, entry in newEntries do
		local pageId = entry.mutation or NORMAL_PAGE
		local list = pageEntries[pageId]
		if not list then
			list = {}
			pageEntries[pageId] = list
		end
		table.insert(list, entry)
		entriesByKey[entry.key or entry.id] = entry
	end

	if not pagesById[currentPage] then
		clearSelection()
		currentPage = NORMAL_PAGE
	end
	buildTabs()
	render()
	if indexWindow.isOpen() then
		selectFirstCard()
	end
end)

-- Claim All answers under the key "All" with how many were claimed and their Luck, shown as one combined effect.
network.connectEvent(network.RemoteEvents.IndexClaimResult, function(key: string, success: boolean, _reason, count: number?, luck: number?)
	if key == "All" then
		if success then
			pop(claimAllFrame)
			playLuckClaimedSound()
			luckRain.play(indexGui)
			announcements.show("ClaimAlert", `Claimed {count or 0} sheep (+{formatWithCommas(luck or 0)} Luck)`)
		else
			shake(claimAllFrame)
		end
		return
	end

	local entry = entriesByKey[key]
	if not entry then
		return
	end
	if success then
		local card = cards[entry.id]
		if card and entry.mutation == currentPage then
			pop(card.frame)
		end
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

-- IndexState with the new "Found" entry arrives just before this; a mutated sheep's is on its mutation's page.
network.connectEvent(network.RemoteEvents.SheepUnlocked, function(sheepType: string, _name, _rarity, _color, _weight, mutation: any)
	if indexWindow.isOpen() then
		local pageId = if type(mutation) == "table" and type(mutation.name) == "string" then mutation.name else NORMAL_PAGE
		local entry = findEntry(pageId, sheepType)
		focusUnclaimed(if entry then entry.key else nil)
	end
end)

network.fireServer(network.RemoteEvents.RequestIndexState)
