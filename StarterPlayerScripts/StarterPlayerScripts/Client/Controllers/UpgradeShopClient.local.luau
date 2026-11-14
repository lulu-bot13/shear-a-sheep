--[[
	The upgrade shop (StarterGui.UpgradeShop), opened at the player's own shack or the HUD's Upgrades button: one card per upgrade from
	the server's UpgradeState, bought 1X or MAX with the MultiplierFrame switch. UpgradeHandler decides everything.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.UpgradeShopClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local alertPulse = require(script.Parent.Parent.Modules.AlertPulse)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
local shopGui = playerGui:WaitForChild("UpgradeShop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: Frame
local scrollFrame = mainFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local cardTemplate = scrollFrame:WaitForChild("Template") :: ImageLabel
local layout = scrollFrame:WaitForChild("UIListLayout") :: UIListLayout
-- The 1X / MAX switch: its Button slides along the MultiplierFrame track like the rebirth screen's Switch.
local amountSwitch = mainFrame:WaitForChild("MultiplierFrame") :: Frame
local amountKnob = amountSwitch:WaitForChild("Button") :: TextButton
local amountLabel = amountKnob:WaitForChild("Multiplier") :: TextLabel
local hudButtons = playerGui:WaitForChild("Main"):FindFirstChild("Buttons")
local hudButton = hudButtons and hudButtons:FindFirstChild("Upgrades") :: GuiButton? -- optional: the shack prompts work without it
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue

--// Sounds
local cashInSound = soundService:FindFirstChild("UISounds"):FindFirstChild("Cash")
local errorSound = soundService:FindFirstChild("UISounds"):FindFirstChild("Error")

--// Configs
local SHOP_PROMPT_TAG = "UpgradeShop"
local SHACK_NAME = "UpgradePlotShack" -- matches UpgradeData.ShackName on the server
local SHACK_LABEL_NAME = "Upgrades" -- the TextLabel over each shack
local CLOSE_DISTANCE_EXTRA = 6 -- studs past the prompt's activation range before the shop closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local AFTER_COLOR = "#1EFF3C" -- the "after" number in the Upgrade text
local MAX_COLOR = "#FFD54A"
local DISABLED_COLOR = Color3.fromRGB(130, 130, 130) -- the Purchase button's ImageColor3 while the upgrade can't be bought
local MIN_SCALE_FACTOR = 0.05 -- below this the window is closing, so card sizes aren't measured
local LEVEL_BOUGHT_COLOR = Color3.fromRGB(102, 255, 56) -- a ProgressionFrame cell for a level the player owns
local LEVEL_EMPTY_COLOR = Color3.fromRGB(120, 120, 120)
local STATE_RETRY_SECONDS = 1 -- while the shop is open with no cards yet, the state is asked for again this often
local OPEN_SETTLE_SECONDS = 0.25 -- after the open tween, when the cards are measured again at full size
local LEVELS_PER_PAGE = 16 -- cells in a full ProgressionFrame; buying past them starts the next page
local CELLS_PER_ROW = 8
local AMOUNTS = { 1, "max" } -- what the switch flips between; "max" buys as many levels as the wool covers
local KNOB_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- the rebirth Switch's slide

-- Alert text when an upgrade can't be bought; "%s" is the upgrade's name.
local REASON_TEXT = {
	NoWool = "Not enough wool for %s",
	Maxed = "%s is MAXED",
	Capped = "%s is maxed for this rebirth",
	NotLoaded = "Still loading, try again",
}

type Card = {
	frame: ImageLabel,
	title: TextLabel,
	price: TextLabel,
	upgrade: TextLabel,
	purchase: ImageButton,
	purchaseColor: Color3, -- the Purchase button's ImageColor3 as built in Studio
	purchaseRotation: number, -- its rest angle, which the shake returns to
	icon: ImageLabel,
	progression: Frame,
	progressionTemplate: Frame,
	progressionText: TextLabel,
	progressionCells: { GuiObject },
	state: any,
}

--// State
local cards: { [string]: Card } = {}
local activePrompt: ProximityPrompt? = nil
local openToken = 0
local amountIndex = 1 -- into AMOUNTS; back to 1X every time the shop opens
local knobOnePosition = amountKnob.Position -- the 1X side, as built in Studio
-- The MAX side mirrors the 1X side across the track.
local knobMirror = 2 * amountKnob.AnchorPoint.X - 1
local knobMaxPosition = UDim2.new(
	1 - knobOnePosition.X.Scale + knobMirror * amountKnob.Size.X.Scale,
	-knobOnePosition.X.Offset + knobMirror * amountKnob.Size.X.Offset,
	knobOnePosition.Y.Scale,
	knobOnePosition.Y.Offset
)

--[[
	Scale on Y inside a ScrollingFrame is relative to the canvas, so these are turned into pixels using the canvas
	height Studio laid them out on (taken before updateCanvasSize changes it), giving the same size as in Studio.
]]
local designCanvasY = scrollFrame.CanvasSize.Y
local cardSize = cardTemplate.Size
local listPadding = layout.Padding

--// Helpers ---------------------------------------------------------------------

local function shake(button: GuiObject, restRotation: number)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = restRotation + angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function getSelectedAmount(): number | string
	return AMOUNTS[amountIndex]
end

-- The plot the instance sits in, or nil if it isn't inside one.
local function getPlot(instance: Instance): Instance?
	local current = instance.Parent
	while current and current.Parent ~= plotsFolder do
		current = current.Parent
	end
	return current
end

-- A shed on someone else's plot can't be used; one outside every plot can.
local function canUsePrompt(prompt: ProximityPrompt): boolean
	local plot = getPlot(prompt)
	return plot == nil or plot:GetAttribute("Owner") == player.UserId
end

--// Cards -----------------------------------------------------------------------------

-- A window that hasn't been laid out yet (its gui is off) measures 0; its cards keep their Studio size until it has been.
local function toWindowPixels(size: UDim, windowHeight: number): UDim
	if windowHeight < 1 then
		return size
	end
	local canvasHeight = math.max(windowHeight, designCanvasY.Offset + designCanvasY.Scale * windowHeight)
	return UDim.new(0, math.floor(size.Offset + size.Scale * canvasHeight))
end

-- Nil while the window is shrunk to (almost) nothing by its close tween.
local function getScaleFactor(): number?
	local factor = windowsManager.getScaleFactor(scrollFrame)
	return if factor > MIN_SCALE_FACTOR then factor else nil
end

-- Sizes the cards (and the list's gaps) from the window height so a taller canvas can't make them grow.
local function updateCardSizes()
	local factor = getScaleFactor()
	if not factor then
		return
	end

	local windowHeight = scrollFrame.AbsoluteWindowSize.Y / factor
	local height = toWindowPixels(cardSize.Y, windowHeight)
	for _, card in cards do
		card.frame.Size = UDim2.new(cardSize.X, height)
	end
	layout.Padding = toWindowPixels(listPadding, windowHeight)
end

-- Only when the cards don't fit does the canvas get taller (in pixels) so the player can scroll to the rest.
local function updateCanvasSize()
	local factor = getScaleFactor()
	if not factor then
		return
	end

	local windowHeight = scrollFrame.AbsoluteWindowSize.Y / factor
	local needed = math.ceil(layout.AbsoluteContentSize.Y / factor)
	local canvasSize = UDim2.fromOffset(0, if needed > windowHeight then needed else 0)
	if scrollFrame.CanvasSize ~= canvasSize then
		scrollFrame.CanvasSize = canvasSize
	end
end

-- Turns the ProgressionFrame grid's offset sizes into scale for a full page, so the cells fit the frame on any screen.
local function scaleProgressionGrid(grid: UIGridLayout)
	local rows = math.ceil(LEVELS_PER_PAGE / CELLS_PER_ROW)
	local cellSize, cellPadding = grid.CellSize, grid.CellPadding
	local ratioX = if cellSize.X.Offset > 0 then cellPadding.X.Offset / cellSize.X.Offset else 0
	local ratioY = if cellSize.Y.Offset > 0 then cellPadding.Y.Offset / cellSize.Y.Offset else 0
	local cellWidth = 1 / (CELLS_PER_ROW + (CELLS_PER_ROW - 1) * ratioX)
	local cellHeight = 1 / (rows + (rows - 1) * ratioY)

	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirectionMaxCells = CELLS_PER_ROW
	grid.CellSize = UDim2.fromScale(cellWidth, cellHeight)
	grid.CellPadding = UDim2.fromScale(cellWidth * ratioX, cellHeight * ratioY)
end

local function buildProgressionCells(card: Card, count: number)
	local template = card.progressionTemplate
	for _, cell in card.progressionCells do
		cell:Destroy()
	end
	table.clear(card.progressionCells)

	for index = 1, count do
		local cell = template:Clone()
		cell.Name = tostring(index)
		cell.LayoutOrder = index
		cell.Visible = true
		cell.Parent = card.progression
		table.insert(card.progressionCells, cell)
	end
end

--[[
	Levels are shown a page of LEVELS_PER_PAGE at a time: green for bought, grey for the rest, with "page/pages" in
	ProgressionText. Filling a page moves on to the next (all grey again); the last page only has the levels left.
	Hidden for upgrades with no level limit.
]]
local function renderProgression(card: Card)
	local maxLevel = card.state.maxLevel
	local hasLimit = type(maxLevel) == "number" and maxLevel >= 1
	card.progression.Visible = hasLimit
	card.progressionText.Visible = hasLimit
	if not hasLimit then
		return
	end

	local level = math.clamp(card.state.level or 0, 0, maxLevel)
	local pages = math.ceil(maxLevel / LEVELS_PER_PAGE)
	local page = math.min(level // LEVELS_PER_PAGE + 1, pages)
	local pageStart = (page - 1) * LEVELS_PER_PAGE
	local cellCount = math.min(LEVELS_PER_PAGE, maxLevel - pageStart)

	if #card.progressionCells ~= cellCount then
		buildProgressionCells(card, cellCount)
	end
	for index, cell in card.progressionCells do
		cell.BackgroundColor3 = if index <= level - pageStart then LEVEL_BOUGHT_COLOR else LEVEL_EMPTY_COLOR
	end

	card.progressionText.Text = `{page}/{pages}`
end

--[[
	How many levels a click buys right now and their total wool: 1X buys the next level, MAX as many of the server's
	`steps` (in order) as the player's wool covers. A count of 0 means not even one is affordable.
	Only a preview; UpgradeHandler works the MAX count out again from its own data.
]]
local function getPurchase(state: any): (number, number)
	local steps = if type(state.steps) == "table" then state.steps else {}
	local limit = if getSelectedAmount() == "max" then #steps else math.min(#steps, 1)
	local count, total = 0, 0
	for index = 1, limit do
		local nextTotal = total + steps[index].cost
		if nextTotal > wool.Value then
			break
		end
		count, total = index, nextTotal
	end
	return count, total
end

-- The card previews what a click buys: the value after those levels and their price (one level's while none is affordable).
local function renderCard(card: Card)
	local state = card.state
	card.title.Text = state.title

	if state.after then
		local count, total = getPurchase(state)
		local lastStep = if type(state.steps) == "table" then state.steps[math.max(count, 1)] else nil
		local after = if lastStep then lastStep.after else state.after
		local levels = if count > 1 then ` <font color="{AFTER_COLOR}">(+{count})</font>` else ""
		card.upgrade.Text = `{state.before} -> <font color="{AFTER_COLOR}"><b>{after}</b></font>{levels}`
		card.price.Text = `{numberFormatter:Format(if count > 0 then total else state.cost, 1)} Wool`
	elseif state.note then
		-- A cap that rises later (Spawn Luck's per rebirth) says how to raise it instead of "(MAX)".
		card.upgrade.Text = `{state.before}\n<font color="{MAX_COLOR}"><b>{state.note}</b></font>`
		card.price.Text = "MAXED"
	else
		card.upgrade.Text = `{state.before} <font color="{MAX_COLOR}"><b>(MAX)</b></font>`
		card.price.Text = "MAXED"
	end

	if state.icon ~= "" then
		card.icon.Image = state.icon
	end

	renderProgression(card)
end

-- Greys out the Purchase button's image while the player can't afford a level (or it's maxed).
local function updatePurchaseButton(card: Card)
	local canBuy = card.state.after ~= nil and getPurchase(card.state) > 0
	card.purchase.ImageColor3 = if canBuy then card.purchaseColor else DISABLED_COLOR
end

local function renderAll()
	for _, card in cards do
		renderCard(card)
		updatePurchaseButton(card)
	end
end

local function setAmountIndex(index: number)
	amountIndex = index
	local amount = getSelectedAmount()
	amountLabel.Text = if amount == "max" then "MAX" else `{amount}X`
	local knobPosition = if amount == "max" then knobMaxPosition else knobOnePosition
	tweenService:Create(amountKnob, KNOB_TWEEN, { Position = knobPosition }):Play()
	renderAll()
end

-- The card's text stays as it is; the reason goes in an alert at the top of the screen.
local function showFailure(card: Card, reason: string?)
	local text = REASON_TEXT[reason or ""] or "Can't buy %s"
	alerts.show(string.format(text, card.state.title), "error")
	shake(card.purchase, card.purchaseRotation)

	if errorSound and errorSound:IsA("Sound") then
		errorSound:Play()
	end
end

local function createCard(state: any, order: number): Card
	local frame = cardTemplate:Clone()
	frame.Name = state.id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(cardSize.X, toWindowPixels(cardSize.Y, scrollFrame.AbsoluteWindowSize.Y / (getScaleFactor() or 1)))
	frame.Visible = true

	local purchase = frame:WaitForChild("Purchase") :: ImageButton
	local progression = frame:WaitForChild("ProgressionFrame") :: Frame
	local progressionTemplate = progression:WaitForChild("Template") :: Frame
	local progressionText = frame:WaitForChild("ProgressionText") :: TextLabel
	scaleProgressionGrid(progression:WaitForChild("UIGridLayout") :: UIGridLayout)
	progressionTemplate.Visible = false

	local card: Card = {
		frame = frame,
		title = frame:WaitForChild("Title") :: TextLabel,
		price = frame:WaitForChild("Price") :: TextLabel,
		upgrade = frame:WaitForChild("Upgrade") :: TextLabel,
		purchase = purchase,
		purchaseColor = purchase.ImageColor3,
		purchaseRotation = purchase.Rotation,
		icon = frame:WaitForChild("ImageFrame"):WaitForChild("UpgradeImage") :: ImageLabel,
		progression = progression,
		progressionTemplate = progressionTemplate,
		progressionText = progressionText,
		progressionCells = {},
		state = state,
	}
	card.upgrade.RichText = true

	-- Sends 1 or "max"; for MAX the server counts the affordable levels itself.
	card.purchase.Activated:Connect(function()
		if not card.state.after then
			showFailure(card, if card.state.note then "Capped" else "Maxed")
			return
		end
		network.fireServer(network.RemoteEvents.PurchaseUpgrade, card.state.id, getSelectedAmount())
	end)

	frame.Parent = scrollFrame
	return card
end

-- The HUD button's optional "Alert" badge, looked up in the current Main (a respawn swaps in a fresh copy).
local pulsedBadges: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function getAlertBadge(): GuiObject?
	local main = playerGui:FindFirstChild("Main")
	local buttons = main and main:FindFirstChild("Buttons")
	local button = buttons and buttons:FindFirstChild("Upgrades")
	local badge = button and button:FindFirstChild("Alert", true)
	if not badge or not badge:IsA("GuiObject") then
		return nil
	end
	if not pulsedBadges[badge] then
		pulsedBadges[badge] = true
		alertPulse.attach(badge)
	end
	return badge
end

-- The HUD button's "Alert" badge shows an exclamation mark while any upgrade is affordable.
local function updateAlert()
	local alertBadge = getAlertBadge()
	if not alertBadge then
		return
	end

	local affordable = false
	for _, card in cards do
		local cost = card.state.cost
		if cost and wool.Value >= cost then
			affordable = true
			break
		end
	end

	alertBadge.Visible = affordable
	if affordable and (alertBadge:IsA("TextLabel") or alertBadge:IsA("TextButton")) then
		alertBadge.Text = "!"
	end
end

-- Fills every card from the server's state, creating any card that doesn't exist yet.
local function applyState(states: { any })
	for index, state in states do
		local card = cards[state.id]
		if not card then
			card = createCard(state, index)
			cards[state.id] = card
		end

		card.state = state
		renderCard(card)
		updatePurchaseButton(card)
	end
	updateAlert()
end

--// Open / close ------------------------------------------------------------------

local function getPromptPosition(prompt: ProximityPrompt): Vector3?
	local holder = prompt.Parent
	if holder and holder:IsA("BasePart") then
		return holder.Position
	elseif holder and holder:IsA("Attachment") then
		return holder.WorldPosition
	end
	return nil
end

local window = windowsManager.register("UpgradeShop", {
	gui = shopGui,
	frame = mainFrame,
	openButton = hudButton,
	onOpen = function()
		openToken += 1
		local token = openToken
		setAmountIndex(1)
		network.fireServer(network.RemoteEvents.RequestUpgradeState)

		-- Measured again at full size once the pop-in is done, and the state asked for until the cards exist (a dropped or
		-- early request must never leave the shop empty, e.g. straight after joining in the tutorial).
		task.delay(OPEN_SETTLE_SECONDS, function()
			updateCardSizes()
			updateCanvasSize()
		end)
		task.spawn(function()
			while next(cards) == nil and token == openToken do
				task.wait(STATE_RETRY_SECONDS)
				if next(cards) == nil and token == openToken then
					network.fireServer(network.RemoteEvents.RequestUpgradeState)
				end
			end
		end)
	end,
	onClose = function()
		openToken += 1
		activePrompt = nil
	end,
})

-- Opened from a shack's prompt; the HUD button opens it through the window instead (and it then stays open wherever you go).
local function openShop(prompt: ProximityPrompt)
	activePrompt = prompt
	if window.isOpen() then
		return
	end

	window.open()
	local token = openToken

	-- Walk away from the shack and the shop closes itself.
	task.spawn(function()
		while token == openToken do
			local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local current = activePrompt
			local promptPosition = if current then getPromptPosition(current) else nil
			if not rootPart or not current or not promptPosition then
				window.close()
				return
			end

			if (rootPart.Position - promptPosition).Magnitude > current.MaxActivationDistance + CLOSE_DISTANCE_EXTRA then
				window.close()
				return
			end
			task.wait(DISTANCE_CHECK_SECONDS)
		end
	end)
end

local function connectPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end

	-- Hidden (for this player only) on sheds they don't own; follows the plot changing hands.
	local plot = getPlot(instance)
	if plot then
		instance.Enabled = canUsePrompt(instance)
		plot:GetAttributeChangedSignal("Owner"):Connect(function()
			instance.Enabled = canUsePrompt(instance)
		end)
	end

	instance.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer ~= player or not canUsePrompt(instance) then
			return
		end

		if window.isOpen() then
			window.close()
		else
			openShop(instance)
		end
	end)
end

-- The "Upgrades" text over a shack only shows (for this player) on their own plot; follows the plot changing hands.
local function connectShackLabel(plot: Instance)
	local shack = plot:WaitForChild(SHACK_NAME, 10)
	local label = shack and shack:FindFirstChild(SHACK_LABEL_NAME, true)
	if not label or not label:IsA("TextLabel") then
		return
	end

	local function update()
		label.Visible = plot:GetAttribute("Owner") == player.UserId
	end
	plot:GetAttributeChangedSignal("Owner"):Connect(update)
	update()
end

--// Setup ---------------------------------------------------------------------------

cardTemplate.Visible = false
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None -- updateCanvasSize sizes it instead
updateAlert()
playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "Main" then
		task.delay(1, updateAlert) -- the respawned HUD's badge
	end
end)
-- MAX's level count and price follow the wool; 1X only needs its button greyed or not.
wool.Changed:Connect(function()
	updateAlert()
	if getSelectedAmount() == "max" and window.isOpen() then
		renderAll()
		return
	end
	for _, card in cards do
		updatePurchaseButton(card)
	end
end)

amountKnob.Activated:Connect(function()
	setAmountIndex(amountIndex % #AMOUNTS + 1)
end)
setAmountIndex(1)

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
scrollFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
	updateCardSizes()
	updateCanvasSize()
end)
updateCardSizes()
updateCanvasSize()

for _, instance in collectionService:GetTagged(SHOP_PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(connectPrompt)

for _, plot in plotsFolder:GetChildren() do
	task.spawn(connectShackLabel, plot)
end
plotsFolder.ChildAdded:Connect(connectShackLabel)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradeState, applyState)

network.connectEvent(network.RemoteEvents.UpgradeResult, function(id: any, success: boolean, reason: string?, level: number?, count: number?)
	local card = if type(id) == "string" then cards[id] else nil
	if not card then
		return
	end

	if not success then
		showFailure(card, reason)
		return
	end

	local bought = if type(count) == "number" and count > 1 then ` (+{count})` else ""
	alerts.show(`Upgraded {card.state.title} -> lvl {level or card.state.level or 0}{bought}`, "success")
	if cashInSound and cashInSound:IsA("Sound") then
		cashInSound:Play()
	end
end)

network.fireServer(network.RemoteEvents.RequestUpgradeState)
