--[[
	The sheep Index (StarterGui.Index): the HUD's Index button opens it and every sheep type gets a card cloned from the Template.
	Selecting a card fills the InfoFrame and RewardsFrame; found sheep are claimed there (or all at once); IndexHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.IndexClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

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
local closeButton = (mainFrame:FindFirstChild("Exit", true) or mainFrame:FindFirstChild("Close", true)) :: GuiButton?

-- The selected sheep's details.
local infoFrame = mainFrame:WaitForChild("InfoFrame")
local infoName = infoFrame:WaitForChild("SheepName") :: TextLabel
local infoRarity = infoFrame:WaitForChild("Rarity") :: TextLabel
local infoViewport = infoFrame:WaitForChild("ViewportFrame") :: ViewportFrame

local rewardsFrame = mainFrame:FindFirstChild("RewardsFrame", true) :: GuiObject
local rewardAmount = rewardsFrame:WaitForChild("RewardAmount") :: TextLabel
local claimButton = rewardsFrame:WaitForChild("Claim") :: TextButton

local claimAllFrame = mainFrame:WaitForChild("ClaimAllFrame") :: GuiObject
local claimAllButton = claimAllFrame:WaitForChild("Claim") :: TextButton
local claimAllAmount = claimAllFrame:WaitForChild("RewardAmount") :: TextLabel
local claimAllMultiplier = claimAllFrame:WaitForChild("Multiplier") :: TextLabel

--// Configs
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PULSE_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local CLAIM_COLOR = Color3.fromRGB(255, 200, 40)
local CLAIMED_COLOR = Color3.fromRGB(90, 90, 90) -- "Claimed" text and the unusable Claim button
local LOCKED_TINT = Color3.new(0, 0, 0) -- undiscovered sheep show as a silhouette
local LOCKED_TEXT = "???"
local ALERT_COLOR = Color3.fromRGB(235, 50, 50)
local CAMERA_YAW = math.rad(35)
local CAMERA_PITCH = math.rad(15)
local CAMERA_FOV = 40

type Card = {
	id: string,
	frame: GuiObject,
	nameLabel: TextLabel,
	rarityLabel: TextLabel,
	viewport: ViewportFrame?,
	stroke: UIStroke?,
	strokeColor: Color3,
	strokeThickness: number,
	pulse: Tween?,
	entry: any,
}

--// State
local cards: { [string]: Card } = {}
local entries: { any } = {} -- the last IndexState from the server
local selectedId: string? = nil

local rewardAmountColor = rewardAmount.TextColor3
local claimButtonText = claimButton.Text
local claimButtonColor = claimButton.BackgroundColor3

local openScale = Instance.new("UIScale")
openScale.Parent = mainFrame

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

-- Sizes a scrolling container's canvas to fit its layout plus padding.
local function updateCanvasSize()
	if not cardContainer:IsA("ScrollingFrame") then
		return
	end
	local layout = cardContainer:FindFirstChildWhichIsA("UIGridStyleLayout")
	if not layout then
		return
	end

	local padding = cardContainer:FindFirstChildOfClass("UIPadding")
	local paddingY = 0
	if padding then
		local height = cardContainer.AbsoluteSize.Y
		paddingY = padding.PaddingTop.Offset + padding.PaddingTop.Scale * height
			+ padding.PaddingBottom.Offset + padding.PaddingBottom.Scale * height
	end
	cardContainer.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + paddingY)
end

--// Previews ----------------------------------------------------------------------

local function clearPreview(viewport: ViewportFrame)
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

-- Puts a still, scriptless copy of the sheep model in a ViewportFrame, framed from the front-side.
local function buildPreview(viewport: ViewportFrame, sheepType: string)
	clearPreview(viewport)

	local template = sheepModels:FindFirstChild(sheepType)
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

	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = boxCFrame.Position
	local distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(CAMERA_FOV / 2))
	local direction = (CFrame.Angles(0, CAMERA_YAW, 0) * CFrame.Angles(-CAMERA_PITCH, 0, 0)).LookVector
	camera.CFrame = CFrame.lookAt(center - direction * distance, center)
end

--// Info panel --------------------------------------------------------------------

local function setInfoVisible(visible: boolean)
	infoName.Visible = visible
	infoRarity.Visible = visible
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

local function selectCard(card: Card)
	if selectedId ~= card.id then
		selectedId = card.id
		buildPreview(infoViewport, card.id)
	end
	renderInfo()
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

--// Cards -------------------------------------------------------------------------

local function refreshCard(card: Card)
	local entry = card.entry
	local status = entry.status

	if card.pulse then
		card.pulse:Cancel()
		card.pulse = nil
	end

	local locked = status == "Locked"
	card.nameLabel.Text = if locked then LOCKED_TEXT else entry.name
	if card.viewport then
		card.viewport.ImageColor3 = if locked then LOCKED_TINT else Color3.new(1, 1, 1)
	end

	if locked then
		card.rarityLabel.Text = LOCKED_TEXT
		card.rarityLabel.TextColor3 = CLAIMED_COLOR
	elseif status == "Found" then
		card.rarityLabel.Text = `Claim +{formatWithCommas(entry.indexLuck)} Luck`
		card.rarityLabel.TextColor3 = CLAIM_COLOR
	else
		card.rarityLabel.Text = entry.rarity
		card.rarityLabel.TextColor3 = entry.color
	end

	local stroke = card.stroke
	if stroke then
		stroke.Thickness = card.strokeThickness
		if status == "Found" then
			stroke.Color = CLAIM_COLOR
			card.pulse = tweenService:Create(stroke, PULSE_TWEEN, { Thickness = card.strokeThickness + 2 })
			card.pulse:Play()
		elseif status == "Claimed" then
			stroke.Color = entry.color
		else
			stroke.Color = card.strokeColor
		end
	end
end

local function createCard(entry: any, order: number): Card
	local frame = cardTemplate:Clone()
	frame.Name = entry.id
	frame.LayoutOrder = order
	frame.Visible = true

	local viewport = frame:FindFirstChildOfClass("ViewportFrame")
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local card: Card = {
		id = entry.id,
		frame = frame,
		nameLabel = frame:WaitForChild("ItemName") :: TextLabel,
		rarityLabel = frame:WaitForChild("Rarity") :: TextLabel,
		viewport = viewport,
		stroke = stroke,
		strokeColor = if stroke then stroke.Color else Color3.new(1, 1, 1),
		strokeThickness = if stroke then stroke.Thickness else 0,
		pulse = nil,
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

	renderInfo()
	renderClaimAll()
	task.defer(updateCanvasSize)
end

--// Open / close -----------------------------------------------------------------------

local function closeIndex()
	mainFrame.Visible = false
end

local function openIndex()
	if mainFrame.Visible then
		return
	end

	network.fireServer(network.RemoteEvents.RequestIndexState)

	openScale.Scale = 0.85
	mainFrame.Visible = true
	tweenService:Create(openScale, OPEN_TWEEN, { Scale = 1 }):Play()
end

--// Setup -------------------------------------------------------------------------------

-- Kept across respawns: a reset would swap in a fresh copy and leave this script driving the destroyed one.
indexGui.ResetOnSpawn = false
indexGui.Enabled = true
mainFrame.Visible = false
cardTemplate.Visible = false
claimAllFrame.Visible = false
alertBadge.Visible = false
setInfoVisible(false)

if cardContainer:IsA("ScrollingFrame") then
	cardContainer.AutomaticCanvasSize = Enum.AutomaticSize.None
	local layout = cardContainer:FindFirstChildWhichIsA("UIGridStyleLayout")
	if layout then
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
	end
end

openButton.MouseButton1Click:Connect(function()
	if mainFrame.Visible then
		closeIndex()
	else
		openIndex()
	end
end)

if closeButton then
	closeButton.MouseButton1Click:Connect(closeIndex)
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

network.connectEvent(network.RemoteEvents.IndexClaimResult, function(id: string, success: boolean)
	if id == "All" then
		if success then
			pop(claimAllFrame)
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
	else
		shake(claimButton)
	end
end)

network.fireServer(network.RemoteEvents.RequestIndexState)
