--[[
	The upgrade shop UI (StarterGui.UpgradeShop), opened from the "UpgradeShop" prompt on the player's own shack
	or the HUD's Upgrades button.
	One card per upgrade is cloned from the Template and filled from the server's UpgradeState; UpgradeHandler decides everything.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.UpgradeShopClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
local shopGui = playerGui:WaitForChild("UpgradeShop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: Frame
local scrollFrame = mainFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local cardTemplate = scrollFrame:WaitForChild("Template") :: Frame
local closeButton = (mainFrame:FindFirstChild("Close") or mainFrame:FindFirstChild("Exit")) :: GuiButton?
local hudButtons = playerGui:WaitForChild("Main"):FindFirstChild("Buttons")
local hudButton = hudButtons and hudButtons:FindFirstChild("Upgrades") :: GuiButton? -- optional: the shack prompts work without it
local alertBadge = hudButton and hudButton:FindFirstChild("Alert", true) :: GuiObject? -- optional badge on the HUD button
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue

--// Configs
local SHOP_PROMPT_TAG = "UpgradeShop"
local CLOSE_DISTANCE_EXTRA = 6 -- studs past the prompt's activation range before the shop closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local MESSAGE_SECONDS = 1.3
local AFTER_COLOR = "#1EFF3C" -- the "after" number in the Upgrade text
local MAX_COLOR = "#FFD54A"

local REASON_TEXT = {
	NoWool = "Not enough wool",
	Maxed = "Maxed",
	NotLoaded = "Loading...",
}

type Card = {
	frame: Frame,
	title: TextLabel,
	price: TextLabel,
	upgrade: TextLabel,
	level: TextLabel,
	purchase: GuiButton,
	icon: GuiObject?,
	state: any,
	messageToken: number,
}

--// State
local cards: { [string]: Card } = {}
local activePrompt: ProximityPrompt? = nil
local openToken = 0

local layout = scrollFrame:FindFirstChildOfClass("UIListLayout") or scrollFrame:FindFirstChildOfClass("UIGridLayout")
local framePadding = scrollFrame:FindFirstChildOfClass("UIPadding")

-- Scale on Y inside a ScrollingFrame is relative to the canvas, so these are turned into pixels of the visible window.
local cardSize = cardTemplate.Size
local listPadding = if layout and layout:IsA("UIListLayout") then layout.Padding else nil
local gridCellSize = if layout and layout:IsA("UIGridLayout") then layout.CellSize else nil
local gridCellPadding = if layout and layout:IsA("UIGridLayout") then layout.CellPadding else nil

--// Helpers ---------------------------------------------------------------------

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
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

local function toWindowPixels(size: UDim, windowHeight: number): UDim
	return UDim.new(0, math.floor(size.Offset + size.Scale * windowHeight))
end

-- Sizes the cards (and the layout's gaps) from the window height so a taller canvas can't make them grow.
local function updateCardSizes()
	local windowHeight = scrollFrame.AbsoluteWindowSize.Y
	local height = toWindowPixels(cardSize.Y, windowHeight)
	for _, card in cards do
		card.frame.Size = UDim2.new(cardSize.X, height)
	end

	if listPadding then
		local list = layout :: UIListLayout
		list.Padding = toWindowPixels(listPadding, windowHeight)
	elseif gridCellSize and gridCellPadding then
		local grid = layout :: UIGridLayout
		grid.CellSize = UDim2.new(gridCellSize.X, toWindowPixels(gridCellSize.Y, windowHeight))
		grid.CellPadding = UDim2.new(gridCellPadding.X, toWindowPixels(gridCellPadding.Y, windowHeight))
	end
end

-- Only when the cards don't fit does the canvas get taller (in pixels) so the player can scroll to the rest.
local function updateCanvasSize()
	if not layout then
		return
	end

	local windowHeight = scrollFrame.AbsoluteWindowSize.Y
	local paddingY = 0
	if framePadding then
		paddingY = framePadding.PaddingTop.Offset + framePadding.PaddingTop.Scale * windowHeight
			+ framePadding.PaddingBottom.Offset + framePadding.PaddingBottom.Scale * windowHeight
	end

	local needed = math.ceil(layout.AbsoluteContentSize.Y + paddingY)
	local canvasSize = UDim2.fromOffset(0, if needed > windowHeight then needed else 0)
	if scrollFrame.CanvasSize ~= canvasSize then
		scrollFrame.CanvasSize = canvasSize
	end
end

local function renderCard(card: Card)
	local state = card.state
	card.title.Text = state.title
	card.level.Text = `lvl {state.level or 0}`

	if state.after then
		card.upgrade.Text = `{state.before} -> <font color="{AFTER_COLOR}"><b>{state.after}</b></font>`
		card.price.Text = `{numberFormatter:Format(state.cost, 1)} Wool`
	else
		card.upgrade.Text = `{state.before} <font color="{MAX_COLOR}"><b>(MAX)</b></font>`
		card.price.Text = "MAXED"
	end

	if card.icon and card.icon:IsA("ImageLabel") and state.icon ~= "" then
		card.icon.Image = state.icon
	end
end

-- Shows a short message in the card's Price, then goes back to the price.
local function flashMessage(card: Card, text: string)
	card.messageToken += 1
	local token = card.messageToken
	card.price.Text = text
	shake(card.purchase)

	task.delay(MESSAGE_SECONDS, function()
		if token == card.messageToken then
			renderCard(card)
		end
	end)
end

local function createCard(state: any, order: number): Card
	local frame = cardTemplate:Clone()
	frame.Name = state.id
	frame.LayoutOrder = order
	frame.Size = UDim2.new(cardSize.X, toWindowPixels(cardSize.Y, scrollFrame.AbsoluteWindowSize.Y))
	frame.Visible = true

	local shearImage = frame:FindFirstChild("ShearImage")
	local card: Card = {
		frame = frame,
		title = frame:WaitForChild("Title") :: TextLabel,
		price = frame:WaitForChild("Price") :: TextLabel,
		upgrade = frame:WaitForChild("Upgrade") :: TextLabel,
		level = frame:WaitForChild("Level") :: TextLabel,
		purchase = frame:WaitForChild("Purchase") :: GuiButton,
		icon = if shearImage then shearImage:FindFirstChild("Icon") :: GuiObject? else nil,
		state = state,
		messageToken = 0,
	}
	card.upgrade.RichText = true

	card.purchase.Activated:Connect(function()
		if not card.state.after then
			flashMessage(card, REASON_TEXT.Maxed)
			return
		end
		network.fireServer(network.RemoteEvents.PurchaseUpgrade, card.state.id)
	end)

	frame.Parent = scrollFrame
	return card
end

-- The HUD button's "Alert" badge shows an exclamation mark while any upgrade is affordable.
local function updateAlert()
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
		card.messageToken += 1 -- a pending message must not overwrite the fresh price
		renderCard(card)
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

local function closeShop()
	if not shopGui.Enabled then
		return
	end

	openToken += 1
	activePrompt = nil
	shopGui.Enabled = false
end

-- `prompt` is the shack it was opened from; nil when opened from the HUD button (it then stays open wherever you go).
local function openShop(prompt: ProximityPrompt?)
	activePrompt = prompt
	if shopGui.Enabled then
		return
	end

	openToken += 1
	local token = openToken

	network.fireServer(network.RemoteEvents.RequestUpgradeState)

	shopGui.Enabled = true

	if not prompt then
		return
	end

	-- Walk away from the shack and the shop closes itself.
	task.spawn(function()
		while token == openToken do
			local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local current = activePrompt
			local promptPosition = if current then getPromptPosition(current) else nil
			if not rootPart or not current or not promptPosition then
				closeShop()
				return
			end

			if (rootPart.Position - promptPosition).Magnitude > current.MaxActivationDistance + CLOSE_DISTANCE_EXTRA then
				closeShop()
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

		if shopGui.Enabled then
			closeShop()
		else
			openShop(instance)
		end
	end)
end

--// Setup ---------------------------------------------------------------------------

-- Kept across respawns: a reset would swap in a fresh copy and leave this script opening the destroyed one.
shopGui.ResetOnSpawn = false
mainFrame.Visible = true
cardTemplate.Visible = false
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None -- updateCanvasSize sizes it instead
shopGui.Enabled = false
updateAlert()
wool.Changed:Connect(updateAlert)

if layout then
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
end
scrollFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function()
	updateCardSizes()
	updateCanvasSize()
end)
updateCardSizes()
updateCanvasSize()

if closeButton then
	closeButton.Activated:Connect(closeShop)
end

if hudButton then
	hudButton.Activated:Connect(function()
		if shopGui.Enabled then
			closeShop()
		else
			openShop(nil)
		end
	end)
end

for _, instance in collectionService:GetTagged(SHOP_PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(SHOP_PROMPT_TAG):Connect(connectPrompt)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradeState, applyState)

network.connectEvent(network.RemoteEvents.UpgradeResult, function(id: any, success: boolean, reason: string?)
	local card = if type(id) == "string" then cards[id] else nil
	if not card then
		return
	end

	if not success then
		flashMessage(card, REASON_TEXT[reason or ""] or "Can't buy")
	end
end)

network.fireServer(network.RemoteEvents.RequestUpgradeState)
