--[[
	The Ability Shack at workspace.Base.CenterPlaza.AbilityShack.Podium: the Abilities window (inventory, roll chances, roll buttons) and the roll carousel.
	Only requests and displays; AbilityShackHandler rolls, spends Gems and equips.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AbilityShackClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local alerts = require(script.Parent.Parent.Modules.Alerts)
local network = require(replicatedStorage.Shared.Utils.Network)
local rollEffect = require(script.Parent.Parent.Modules.AbilityRollEffect)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Configs
local SHACK_NAME = "AbilityShack"
local PODIUM_NAME = "Podium"
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs
local WINDOW_NAME = "AbilityShack"
local ROLL_TIMEOUT = 5 -- seconds without a reply before rolling unlocks again
local PIECE_TIMEOUT = 5 -- seconds to wait for a window piece before warning it's missing
local BLACK = Color3.fromRGB(0, 0, 0)
local HALLOWEEN_ONLY_TEXT = "Halloween only" -- a Halloween ability's chance outside Halloween
local OWNED_TEXT = "OWNED" -- the roll chance card's Equipped badge, shown on abilities already owned
local UNAVAILABLE_DARKEN = 0.5 -- how much darker a roll chance card is while it can't be rolled
local UNAFFORDABLE_DARKEN = 0.45 -- how much darker a roll button is while the player can't pay for it

-- Each roll button (art baked in) and how many rolls it buys; Price shows the cost of one roll.
local ROLL_BUTTONS = {
	{ buttonName = "RollButton1", amount = 1 },
	{ buttonName = "RollButton", amount = 5 },
}

local REASON_TEXT = {
	NoGems = "Not enough Gems",
	TooFar = "Get closer to the podium",
	Closed = "The Ability Shack is closed",
	NotOwned = "Roll it at the Ability Shack first",
	Active = "Wait for your ability to finish",
	Unknown = "Unknown ability",
}

type Entry = {
	id: string,
	name: string,
	description: string,
	icon: string,
	rarity: string,
	color: Color3,
	cooldown: number,
	duration: number,
	chance: number,
	halloween: boolean,
	owned: boolean,
}

type State = {
	equipped: string,
	abilities: { Entry },
	cost: number,
}

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local abilitiesGui = playerGui:WaitForChild("Abilities") :: ScreenGui
local main = abilitiesGui:WaitForChild("Main") :: Frame
local inventoryList = main:WaitForChild("Inventory") :: ScrollingFrame
local inventoryTemplate = inventoryList:WaitForChild("Template") :: ImageButton
local exitButton = main:WaitForChild("ExitButton") :: ImageButton

-- A window piece that may sit inside Main or beside it in the ScreenGui; warns and returns nil if it never shows up.
local function findWindowPiece(name: string, className: string): Instance?
	local deadline = os.clock() + PIECE_TIMEOUT
	repeat
		local piece = main:FindFirstChild(name) or abilitiesGui:FindFirstChild(name)
		if piece and piece:IsA(className) then
			return piece
		end
		task.wait(0.1)
	until os.clock() >= deadline
	warn(`AbilityShackClient: {abilitiesGui:GetFullName()} has no {name} ({className}) in Main or the ScreenGui.`)
	return nil
end

local rollChances = findWindowPiece("RollChances", "GuiObject") :: GuiObject?
local rollChancesTemplate = if rollChances then rollChances:FindFirstChild("Template") :: GuiObject? else nil
local priceLabel = findWindowPiece("Price", "TextLabel") :: TextLabel?

-- Each roll button with its Studio ImageColor3 (before dimming) and the rolls it buys.
local rollButtons: { { button: ImageButton, baseColor: Color3, amount: number } } = {}
for _, config in ROLL_BUTTONS do
	local button = findWindowPiece(config.buttonName, "ImageButton") :: ImageButton?
	if button then
		table.insert(rollButtons, { button = button, baseColor = button.ImageColor3, amount = config.amount })
	end
end

--// State
local state: State? = nil
local queuedState: State? = nil -- held back while a roll plays so the window doesn't spoil the result
local rolling = false
local revealing = false
local rollToken = 0
local pendingEquip: string? = nil
local podiumConnections: { RBXScriptConnection } = {}

--// Helpers ---------------------------------------------------------------------

local function formatWithCommas(amount: number): string
	local formatted = tostring(math.floor(amount)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function formatPercent(chance: number): string
	return `{string.format("%.3g", chance * 100)}%`
end

local function shake(button: GuiObject)
	task.spawn(function()
		local rest = button.Rotation
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = rest + angle }):Play()
			task.wait(0.04)
		end
	end)
end

local function getGems(): number
	local gems = player:GetAttribute("Gems")
	return if type(gems) == "number" then gems else 0
end

local function getEntry(id: any): Entry?
	local current = state
	if not current or type(id) ~= "string" then
		return nil
	end
	for _, entry in current.abilities do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function getRollablePool(): { rollEffect.Entry }
	local pool: { rollEffect.Entry } = {}
	for _, entry in (if state then state.abilities else {}) :: { Entry } do
		if entry.chance > 0 then
			table.insert(pool, {
				id = entry.id,
				name = entry.name,
				rarity = entry.rarity,
				color = entry.color,
				chance = entry.chance,
				icon = entry.icon,
			})
		end
	end
	return pool
end

-- Like WaitForChild, without the infinite-yield warning (AbilityShackHandler warns once on the server).
local function waitForChildQuietly(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end

	local thread = coroutine.running()
	local connection: RBXScriptConnection
	connection = parent.ChildAdded:Connect(function(added: Instance)
		if added.Name == name then
			connection:Disconnect()
			task.spawn(thread, added)
		end
	end)
	return coroutine.yield()
end

-- Clears the clones a list made, leaving its hidden Template and layout.
local function clearClones(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Template" then
			child:Destroy()
		end
	end
end

local function setText(parent: Instance, name: string, text: string)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Fills a card cloned from either Template: name, rarity text, icon and background colour.
local function fillCard(card: GuiObject, entry: Entry, rarityText: string, color: Color3)
	card.Name = entry.id
	card.BackgroundColor3 = color
	card.Visible = true
	setText(card, "AbilityName", entry.name)
	setText(card, "Rarity", rarityText)
	local icon = card:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = entry.icon
		icon.Visible = entry.icon ~= ""
	end
end

local function setBadge(card: GuiObject, visible: boolean, text: string?)
	local badge = card:FindFirstChild("Equipped")
	if badge and badge:IsA("TextLabel") then
		badge.Visible = visible
		if text then
			badge.Text = text
		end
	end
end

local function getPodiumPart(podium: Instance): BasePart?
	if podium:IsA("BasePart") then
		return podium
	elseif podium:IsA("Model") then
		return podium.PrimaryPart or podium:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

--// Abilities window --------------------------------------------------------------

local refreshWindow: () -> ()

-- Pieces beside Main (not inside it) pop in and out with it.
local extraFrames: { GuiObject } = {}
for _, piece in { rollChances, priceLabel } :: { GuiObject? } do
	if piece and not piece:IsDescendantOf(main) then
		table.insert(extraFrames, piece)
	end
end
for _, roll in rollButtons do
	if not roll.button:IsDescendantOf(main) then
		table.insert(extraFrames, roll.button)
	end
end

local window = windowsManager.register(WINDOW_NAME, {
	gui = abilitiesGui,
	frame = main,
	extraFrames = extraFrames,
	closeButton = exitButton,
	onOpen = function()
		refreshWindow()
		network.fireServer(network.RemoteEvents.RequestAbilityState)
	end,
})

local function onCardClicked(id: string, card: GuiObject)
	local current = state
	local entry = getEntry(id)
	if not current or not entry or id == current.equipped then
		return
	elseif not entry.owned then
		shake(card)
		alerts.show(REASON_TEXT.NotOwned, "error")
		return
	elseif player:GetAttribute(ACTIVE_ATTRIBUTE) ~= nil then
		shake(card)
		alerts.show(REASON_TEXT.Active, "error")
		return
	end

	pendingEquip = id
	network.fireServer(network.RemoteEvents.EquipAbility, id)
end

-- Every owned ability; clicking one equips it.
local function refreshInventory(current: State)
	clearClones(inventoryList)
	for index, entry in current.abilities do
		if not entry.owned then
			continue
		end

		local card = inventoryTemplate:Clone()
		card.LayoutOrder = index
		fillCard(card, entry, entry.rarity, entry.color)
		setBadge(card, entry.id == current.equipped)
		card.Activated:Connect(function()
			onCardClicked(entry.id, card)
		end)
		card.Parent = inventoryList
	end
end

-- Every ability a roll can land on, with its chance; Halloween abilities stay listed (dimmed) outside Halloween.
local function refreshRollChances(current: State)
	local list, template = rollChances, rollChancesTemplate
	if not list or not template then
		return
	end

	clearClones(list)
	for index, entry in current.abilities do
		local halloweenOnly = entry.halloween and entry.chance <= 0
		if entry.chance <= 0 and not halloweenOnly then
			continue
		end

		local card = template:Clone()
		card.LayoutOrder = index
		fillCard(
			card,
			entry,
			if halloweenOnly then HALLOWEEN_ONLY_TEXT else `{entry.rarity} - {formatPercent(entry.chance)}`,
			if halloweenOnly then entry.color:Lerp(BLACK, UNAVAILABLE_DARKEN) else entry.color
		)
		setBadge(card, entry.owned, OWNED_TEXT)
		card.Parent = list
	end
end

-- The price of one roll, with each roll button dimmed while the player's Gems can't cover it.
local function refreshPrices()
	local current = state
	if not current then
		return
	end
	if priceLabel then
		priceLabel.Text = formatWithCommas(current.cost)
	end
	local gems = getGems()
	for _, roll in rollButtons do
		local cost = current.cost * roll.amount
		roll.button.ImageColor3 = if gems < cost
			then roll.baseColor:Lerp(BLACK, UNAFFORDABLE_DARKEN)
			else roll.baseColor
	end
end

function refreshWindow()
	local current = state
	if not current then
		return
	end
	refreshInventory(current)
	refreshRollChances(current)
	refreshPrices()
end

--// Rolling ------------------------------------------------------------------------

local function applyState(newState: State)
	state = newState
	if pendingEquip and newState.equipped == pendingEquip then
		local entry = getEntry(pendingEquip)
		alerts.show(`Equipped {if entry then entry.name else pendingEquip}`, "success")
		pendingEquip = nil
	end
	refreshWindow()
end

local function finishRoll()
	rolling = false
	revealing = false
	local queued = queuedState
	if queued then
		queuedState = nil
		applyState(queued)
	end
end

local function requestRoll(amount: number, button: GuiObject)
	if rolling then
		return
	end
	local current = state
	if current and getGems() < current.cost * amount then
		shake(button)
		alerts.show(REASON_TEXT.NoGems, "error")
		return
	end

	rolling = true
	rollToken += 1
	local token = rollToken
	network.fireServer(network.RemoteEvents.RollAbility, amount)

	task.delay(ROLL_TIMEOUT, function()
		if token == rollToken and rolling and not revealing then
			finishRoll()
		end
	end)
end

local function playRoll(result: any)
	rolling = true
	revealing = true
	rollToken += 1
	window.close()

	local items = {}
	for _, rolled in result.results do
		local entry = getEntry(rolled.id)
		if entry then
			table.insert(items, { entry = entry, isNew = rolled.isNew == true, refund = rolled.refund or 0 })
		end
	end

	if #items > 0 then
		local ok, message = pcall(rollEffect.play, player.Character, getRollablePool(), items)
		if not ok then
			warn(`AbilityShackClient: roll effect failed: {message}`)
		end
	end

	finishRoll()
end

local function onRollResult(result: any)
	if type(result) ~= "table" then
		return
	end

	-- Someone else's roll nearby: a light version only.
	if result.roller ~= nil then
		local first = if type(result.results) == "table" then result.results[1] else nil
		local entry = if first then getEntry(first.id) else nil
		local roller = result.roller
		if
			roller ~= player
			and typeof(roller) == "Instance"
			and roller:IsA("Player")
			and roller.Character
			and entry
		then
			rollEffect.playSpectator(roller.Character, getRollablePool(), entry)
		end
		return
	end

	if result.success and type(result.results) == "table" then
		task.spawn(playRoll, result)
	elseif not revealing then
		alerts.show(REASON_TEXT[result.reason] or "Couldn't roll", "error")
		finishRoll()
	end
end

local function onState(newState: any, reason: any)
	if type(reason) == "string" then
		alerts.show(REASON_TEXT[reason] or reason, "error")
		pendingEquip = nil
	end
	if type(newState) ~= "table" or type(newState.abilities) ~= "table" then
		return
	end

	if rolling then
		queuedState = newState
	else
		applyState(newState)
	end
end

for _, roll in rollButtons do
	roll.button.Activated:Connect(function()
		requestRoll(roll.amount, roll.button)
	end)
end

player:GetAttributeChangedSignal("Gems"):Connect(refreshPrices)

--// Podium binding ---------------------------------------------------------------

-- Walking into the podium opens the Abilities window.
local function onPodiumTouched(hit: BasePart)
	local character = player.Character
	if not character or not hit:IsDescendantOf(character) or rolling or window.isOpen() then
		return
	end
	window.open()
end

local function unbindPodium()
	for _, connection in podiumConnections do
		connection:Disconnect()
	end
	table.clear(podiumConnections)
end

-- Follows the podium being rebuilt, replaced or streamed out and back in.
local function watchPodium()
	local base = waitForChildQuietly(workspace, "Base")
	local plaza = waitForChildQuietly(base, "CenterPlaza")
	local shack = waitForChildQuietly(plaza, SHACK_NAME)
	while true do
		local podium = waitForChildQuietly(shack, PODIUM_NAME)
		while podium.Parent == shack and not getPodiumPart(podium) do
			podium.DescendantAdded:Wait()
		end
		local part = getPodiumPart(podium)
		if not part or not part:IsDescendantOf(shack) then
			task.wait(0.5) -- a streamed-out PrimaryPart still resolves; wait for it to come back
			continue
		end

		table.insert(podiumConnections, part.Touched:Connect(onPodiumTouched))
		while podium.Parent == shack and part:IsDescendantOf(shack) do
			part.AncestryChanged:Wait()
		end
		unbindPodium()
	end
end

task.spawn(watchPodium)

network.waitUntilReadyAsync()
network.connectEvent(network.RemoteEvents.AbilityState, onState)
network.connectEvent(network.RemoteEvents.AbilityRollResult, onRollResult)
network.fireServer(network.RemoteEvents.RequestAbilityState)
