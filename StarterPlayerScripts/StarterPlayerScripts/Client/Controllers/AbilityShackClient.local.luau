--[[
	The Ability Shack at workspace.Base.CenterPlaza.AbilityShack.Podium: the roll carousel (AbilityRollEffect) and the Studio-built Abilities window for rolling and equipping.
	Only requests and displays; AbilityShackHandler rolls, spends wool and equips.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AbilityShackClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local rollEffect = require(script.Parent.Parent.Modules.AbilityRollEffect)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue
local abilitiesGui = playerGui:WaitForChild("Abilities") :: ScreenGui
local main = abilitiesGui:WaitForChild("Main") :: Frame
local inventoryList = main:WaitForChild("Inventory") :: ScrollingFrame
local rollChances = main:WaitForChild("RollChances") :: Frame
local pityLabel = main:WaitForChild("Pity") :: TextLabel
local rollBar = main:WaitForChild("RollBar") :: Frame
local rollButton = rollBar:WaitForChild("Roll") :: TextButton
local priceLabel = rollBar:WaitForChild("Cost"):WaitForChild("Price") :: TextLabel
local rollAmount = main:WaitForChild("RollAmount")
local inventoryTemplate = inventoryList:WaitForChild("Template") :: ImageButton
local chanceTemplate = rollChances:WaitForChild("Template") :: Frame

--// Configs
local SHACK_NAME = "AbilityShack"
local PODIUM_NAME = "Podium"
local ACTIVE_ATTRIBUTE = "ActiveAbility" -- set by AbilityHandler while an ability runs
local AMOUNT_ATTRIBUTE = "Amount" -- on the RollAmount buttons
local WINDOW_NAME = "AbilityShack"
local FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
local FONT_HEAVY = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.ExtraBold)
local ROLL_TIMEOUT = 5 -- seconds without a reply before rolling unlocks again
local RESULT_SECONDS = 7
local RESULT_BASE_HEIGHT = 124
local RESULT_ROW_HEIGHT = 28
local RESULT_MAX_ROWS = 5
local AMOUNT_SELECTED_COLOR = Color3.fromRGB(49, 190, 61)
local AMOUNT_UNSELECTED_COLOR = Color3.fromRGB(255, 255, 150)
local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local PANEL_COLOR = Color3.fromRGB(30, 32, 44)
local EQUIP_COLOR = Color3.fromRGB(64, 190, 90)
local ROLL_COLOR = Color3.fromRGB(235, 160, 40)
local OPEN_COLOR = Color3.fromRGB(70, 120, 220)

local REASON_TEXT = {
	NoWool = "Not enough wool",
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
	rarity: string,
	color: Color3,
	cooldown: number,
	duration: number,
	chance: number,
	owned: boolean,
}

type State = {
	equipped: string,
	abilities: { Entry },
	cost: number,
	pity: number,
	pityRolls: number,
	pityLabel: string,
}

type ResultRow = {
	frame: Frame,
	name: TextLabel,
	detail: TextLabel,
}

--// State
local state: State? = nil
local queuedState: State? = nil -- held back while a roll plays so the board and window don't spoil the result
local rolling = false
local revealing = false
local rollToken = 0
local selectedAmount = 1
local lastAmount = 1
local pendingEquip: string? = nil
local podiumConnections: { RBXScriptConnection } = {}
local resultToken = 0
local resultId: string? = nil

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
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
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

local function getRollablePool(): { Entry }
	local pool = {}
	for _, entry in (if state then state.abilities else {}) :: { Entry } do
		if entry.chance > 0 then
			table.insert(pool, entry)
		end
	end
	return pool
end

local function create(className: string, properties: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in properties do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function addCorner(parent: Instance, radius: UDim?)
	create("UICorner", { CornerRadius = radius or UDim.new(0, 10) }, parent)
end

local function addStroke(parent: Instance, thickness: number?)
	create("UIStroke", {
		Color = BLACK,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function makeText(parent: Instance, properties: { [string]: any }): TextLabel
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, nil)
	for key, value in properties do
		(label :: any)[key] = value
	end
	create("UIStroke", { Color = BLACK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, label)
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, text: string, color: Color3, properties: { [string]: any }): TextButton
	local button = create("TextButton", {
		BackgroundColor3 = color,
		FontFace = FONT_HEAVY,
		Text = text,
		TextColor3 = WHITE,
		TextScaled = true,
	}, nil)
	for key, value in properties do
		(button :: any)[key] = value
	end
	addCorner(button)
	addStroke(button)
	create("UIStroke", { Color = BLACK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, button)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}, button)
	button.Parent = parent
	return button
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

--// Podium ----------------------------------------------------------------------

local function getPodiumPart(podium: Instance): BasePart?
	if podium:IsA("BasePart") then
		return podium
	elseif podium:IsA("Model") then
		return podium.PrimaryPart or podium:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

--// Abilities window --------------------------------------------------------------

local window = windowsManager.register(WINDOW_NAME, {
	gui = abilitiesGui,
	frame = main,
	onOpen = function()
		network.fireServer(network.RemoteEvents.RequestAbilityState)
	end,
})

local function onEquipClicked(id: string, button: GuiObject)
	local current = state
	local entry = getEntry(id)
	if not current or not entry then
		return
	elseif not entry.owned then
		shake(button)
		alerts.show(REASON_TEXT.NotOwned, "error")
		return
	elseif id == current.equipped then
		return
	elseif player:GetAttribute(ACTIVE_ATTRIBUTE) ~= nil then
		shake(button)
		alerts.show(REASON_TEXT.Active, "error")
		return
	end

	pendingEquip = id
	network.fireServer(network.RemoteEvents.EquipAbility, id)
end

local function refreshInventory(current: State)
	clearClones(inventoryList)
	for index, entry in current.abilities do
		if not entry.owned then
			continue
		end

		local card = inventoryTemplate:Clone()
		card.Name = entry.id
		card.LayoutOrder = index
		card.BackgroundColor3 = entry.color
		card.Visible = true
		setText(card, "AbilityName", entry.name)
		setText(card, "Rarity", entry.rarity)
		local badge = card:FindFirstChild("Equipped")
		if badge and badge:IsA("GuiObject") then
			badge.Visible = entry.id == current.equipped
		end
		card.Activated:Connect(function()
			onEquipClicked(entry.id, card)
		end)
		card.Parent = inventoryList
	end
end

local function refreshRollChances(current: State)
	clearClones(rollChances)
	for index, entry in current.abilities do
		if entry.chance <= 0 then
			continue
		end

		local card = chanceTemplate:Clone()
		card.Name = entry.id
		card.LayoutOrder = index
		card.BackgroundColor3 = entry.color
		card.Visible = true
		setText(card, "AbilityName", entry.name)
		setText(card, "Rarity", entry.rarity)
		local chance = card:FindFirstChild("Chance")
		if chance and chance:IsA("TextLabel") then
			chance.Text = formatPercent(entry.chance)
			chance.Visible = true
		end
		local badge = card:FindFirstChild("Owned")
		if badge and badge:IsA("GuiObject") then
			badge.Visible = entry.owned
		end
		card.Parent = rollChances
	end
end

local function refreshPity(current: State)
	local rollsLeft = math.max(current.pityRolls - current.pity, 1)
	pityLabel.Text = if rollsLeft <= 1
		then `Next roll: guaranteed {current.pityLabel}!`
		else `Guaranteed {current.pityLabel} in {rollsLeft} rolls`
end

local function refreshPrice()
	local current = state
	if current then
		priceLabel.Text = formatWithCommas(current.cost * selectedAmount)
	end
end

local function refreshAmountButtons()
	for _, button in rollAmount:GetChildren() do
		local amount = button:GetAttribute(AMOUNT_ATTRIBUTE)
		if button:IsA("GuiButton") and type(amount) == "number" then
			button.BackgroundColor3 = if amount == selectedAmount then AMOUNT_SELECTED_COLOR else AMOUNT_UNSELECTED_COLOR
		end
	end
	refreshPrice()
end

local function refreshWindow()
	local current = state
	if not current then
		return
	end
	refreshInventory(current)
	refreshRollChances(current)
	refreshPity(current)
	refreshPrice()
end

--// Roll result popup ------------------------------------------------------------

local resultGui = create("ScreenGui", {
	Name = "AbilityShackResult",
	ResetOnSpawn = false,
	Enabled = false,
	DisplayOrder = 4,
}, playerGui)
local resultFrame = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.6),
	Size = UDim2.new(0.92, 0, 0, RESULT_BASE_HEIGHT),
	BackgroundColor3 = PANEL_COLOR,
}, resultGui)
create("UISizeConstraint", { MaxSize = Vector2.new(440, 1000) }, resultFrame)
addCorner(resultFrame, UDim.new(0, 14))
local resultStroke = create("UIStroke", { Thickness = 3, Color = BLACK }, resultFrame)
local resultScale = create("UIScale", {}, resultFrame)
local resultHeader = makeText(resultFrame, {
	FontFace = FONT_HEAVY,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 26),
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Center,
})
local resultRowsHolder = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 40),
	Size = UDim2.new(1, -24, 1, -104),
}, resultFrame)
create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, resultRowsHolder)
local resultRows: { ResultRow } = {}
for index = 1, RESULT_MAX_ROWS do
	local rowFrame = create("Frame", {
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, RESULT_ROW_HEIGHT - 4),
		Visible = false,
	}, resultRowsHolder)
	addCorner(rowFrame, UDim.new(0, 8))
	addStroke(rowFrame, 2)
	local nameLabel = makeText(rowFrame, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.fromScale(0.6, 1),
		TextScaled = true,
	})
	local detailLabel = makeText(rowFrame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0),
		Size = UDim2.new(0.4, -12, 1, 0),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	resultRows[index] = { frame = rowFrame, name = nameLabel, detail = detailLabel }
end
local resultButtons = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 10, 1, -58),
	Size = UDim2.new(1, -20, 0, 50),
}, resultFrame)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
}, resultButtons)
local resultEquip = makeButton(resultButtons, "EQUIP", EQUIP_COLOR, { LayoutOrder = 1, Size = UDim2.fromScale(0.31, 1) })
local resultRoll = makeButton(resultButtons, "ROLL AGAIN", ROLL_COLOR, { LayoutOrder = 2, Size = UDim2.fromScale(0.31, 1) })
local resultOpen = makeButton(resultButtons, "ABILITIES", OPEN_COLOR, { LayoutOrder = 3, Size = UDim2.fromScale(0.31, 1) })

local function hideResult()
	resultToken += 1
	resultGui.Enabled = false
end

local function showResults(results: { any }, best: Entry)
	resultToken += 1
	local token = resultToken
	resultId = best.id

	local count = math.min(#results, RESULT_MAX_ROWS)
	resultHeader.Text = if count > 1 then `{count}X ROLL!` else (if results[1].isNew then "NEW ABILITY!" else "DUPLICATE")
	resultStroke.Color = best.color
	resultFrame.Size = UDim2.new(0.92, 0, 0, RESULT_BASE_HEIGHT + count * RESULT_ROW_HEIGHT)

	for index, row in resultRows do
		local result = results[index]
		local entry = if index <= count then getEntry(result.id) else nil
		row.frame.Visible = entry ~= nil
		if entry then
			row.frame.BackgroundColor3 = entry.color
			row.name.Text = `{entry.name} ({entry.rarity})`
			if result.isNew then
				row.detail.Text = if result.guaranteed then "NEW! (pity)" else "NEW!"
			else
				row.detail.Text = if (result.refund or 0) > 0 then `+{formatWithCommas(result.refund)} Wool` else "Owned"
			end
		end
	end
	resultEquip.Visible = state == nil or state.equipped ~= best.id

	resultScale.Scale = 0.6
	resultGui.Enabled = true
	tweenService:Create(resultScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(RESULT_SECONDS, function()
		if token == resultToken then
			resultGui.Enabled = false
		end
	end)
end

--// Rolling ------------------------------------------------------------------------

local function applyState(newState: State)
	state = newState
	if pendingEquip and newState.equipped == pendingEquip then
		local entry = getEntry(pendingEquip)
		alerts.show(`Equipped {if entry then entry.name else pendingEquip}`, "success")
		pendingEquip = nil
	end
	if resultGui.Enabled then
		resultEquip.Visible = resultId ~= newState.equipped
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

local function requestRoll(amount: number)
	if rolling then
		return
	end
	local current = state
	if current and wool.Value < current.cost * amount then
		alerts.show(REASON_TEXT.NoWool, "error")
		return
	end

	hideResult()
	rolling = true
	lastAmount = amount
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
	hideResult()
	window.close()

	local items = {}
	local best: Entry? = nil
	for _, rolled in result.results do
		local entry = getEntry(rolled.id)
		if entry then
			table.insert(items, { entry = entry, isNew = rolled.isNew == true, refund = rolled.refund or 0 })
			if not best or entry.chance < best.chance then
				best = entry
			end
		end
	end

	if #items > 0 then
		local ok, message = pcall(rollEffect.play, player.Character, getRollablePool(), items)
		if not ok then
			warn(`AbilityShackClient: roll effect failed: {message}`)
		end
	end

	finishRoll()
	if best then
		showResults(result.results, best)
	end
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
		if roller ~= player and typeof(roller) == "Instance" and roller:IsA("Player") and roller.Character and entry then
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
	if type(newState) ~= "table" then
		return
	end

	if rolling then
		queuedState = newState
	else
		applyState(newState)
	end
end

resultEquip.Activated:Connect(function()
	if resultId then
		onEquipClicked(resultId, resultEquip)
	end
end)
resultRoll.Activated:Connect(function()
	requestRoll(lastAmount)
end)
resultOpen.Activated:Connect(function()
	hideResult()
	window.open()
end)

rollButton.Activated:Connect(function()
	requestRoll(selectedAmount)
end)

for _, button in rollAmount:GetChildren() do
	local amount = button:GetAttribute(AMOUNT_ATTRIBUTE)
	if button:IsA("GuiButton") and type(amount) == "number" then
		button.Activated:Connect(function()
			selectedAmount = amount
			refreshAmountButtons()
		end)
	end
end
refreshAmountButtons()

--// Podium binding ---------------------------------------------------------------

-- Walking into the podium opens the Abilities window.
local function onPodiumTouched(hit: BasePart)
	local character = player.Character
	if not character or not hit:IsDescendantOf(character) or rolling or window.isOpen() then
		return
	end
	window.open()
end

local function bindPodium(part: BasePart)
	table.insert(podiumConnections, part.Touched:Connect(onPodiumTouched))
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

		bindPodium(part)
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
