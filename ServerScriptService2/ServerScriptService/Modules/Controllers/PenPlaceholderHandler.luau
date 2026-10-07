--!strict

--[[
	Shows a placeholder pen on each plot's next pen slot (the owner's pen count + 1) and lets the owner buy it.

	The placeholder is a clone of ServerStorage.Assets.Placeholder_Pen, moved to the next slot as pens are added.
	Its UnlockRequirement GUI has two frames, only one of which is visible at a time:
		Requirements - the next slot is blocked by a rebirth; shows the rebirths needed.
		Price        - the next slot is unlocked; shows what it costs.
	The prompt tagged "PurchaseSlot" is only enabled in the Price state, and the purchase is handled on the server.

	The rebirth requirement comes from PenSlotUnlocks and the price from EconomyData, so new rows need no change here.

	Location: ServerScriptService.Modules.Controllers.PenPlaceholderHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local serverStorage = game:GetService("ServerStorage")

--// Modules
local EconomyData = require(script.Parent.Parent.Constants.EconomyData)
local PenSlotUnlocks = require(script.Parent.Parent.Constants.PenSlotUnlocks)
local PenHandler = require(script.Parent.PenHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local TEMPLATE_NAME = "Placeholder_Pen"
local FOLDER_NAME = "Placeholders"
local PURCHASE_TAG = "PurchaseSlot"
local OWNER_ATTRIBUTE = "Owner"
local REBIRTHS_ATTRIBUTE = "Rebirths"
local MAX_PENS = EconomyData.MAX_PENS

type Placeholder = {
	model: Model,
	prompt: ProximityPrompt,
	requirements: GuiObject,
	requirementsAmount: TextLabel,
	price: GuiObject,
	priceAmount: TextLabel,
	slot: number,
}

--// State
local template: Model? = nil
local placeholders: { [Folder]: Placeholder } = {}

local PenPlaceholderHandler = {}

local function getTemplate(): Model?
	if template then
		return template
	end

	local assets = serverStorage:FindFirstChild("Assets")
	local found = assets and assets:FindFirstChild(TEMPLATE_NAME)
	if found and found:IsA("Model") then
		template = found
	else
		warn(`PenPlaceholderHandler: ServerStorage.Assets.{TEMPLATE_NAME} is missing.`)
	end
	return template
end

local function getFolder(plot: Folder): Folder
	local folder = plot:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = plot
	return created
end

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

local function getPlotOwner(plot: Folder): Player?
	local ownerId = plot:GetAttribute(OWNER_ATTRIBUTE)
	return if typeof(ownerId) == "number" then players:GetPlayerByUserId(ownerId) else nil
end

-- The slot the owner can buy next, or nil if they own the last one.
local function getNextSlot(owner: Player): number?
	local slotNumber = #PenHandler.getPens(owner) + 1
	return if slotNumber <= MAX_PENS then slotNumber else nil
end

-- A frame under Center.UnlockRequirement with the label that shows its number.
local function getRequirementFrame(requirement: Instance, name: string): (GuiObject?, TextLabel?)
	local frame = requirement:FindFirstChild(name)
	if not frame or not frame:IsA("GuiObject") then
		return nil, nil
	end

	local amount = frame:FindFirstChild("Amount", true)
	return frame, if amount and amount:IsA("TextLabel") then amount else nil
end

local function findPurchasePrompt(model: Model): ProximityPrompt?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and collectionService:HasTag(descendant, PURCHASE_TAG) then
			return descendant
		end
	end
	return nil
end

-- Server-side purchase: everything is re-checked here, so a client can't buy a slot it shouldn't.
local function onPurchase(plot: Folder, player: Player)
	local placeholder = placeholders[plot]
	local owner = getPlotOwner(plot)
	if not placeholder or owner ~= player or not placeholder.model.Parent then
		return
	end

	local slotNumber = getNextSlot(player)
	if not slotNumber or slotNumber ~= placeholder.slot then
		return
	end
	if slotNumber > PenSlotUnlocks.getSlotLimit(RebirthHandler.getRebirths(player)) then
		return -- still blocked by a rebirth
	end

	local money = getMoney(player)
	local price = EconomyData.getPenPrice(slotNumber)
	if not money or money.Value < price then
		return
	end

	if PenHandler.createPen(player) then
		money.Value -= price
	end
end

local function createPlaceholder(plot: Folder): Placeholder?
	local source = getTemplate()
	if not source then
		return nil
	end

	local model = source:Clone()
	local center = model:FindFirstChild("Center")
	local requirement = center and center:FindFirstChild("UnlockRequirement", true)
	local prompt = findPurchasePrompt(model)
	local requirements, requirementsAmount, price, priceAmount
	if requirement then
		requirements, requirementsAmount = getRequirementFrame(requirement, "Requirements")
		price, priceAmount = getRequirementFrame(requirement, "Price")
	end

	if not prompt or not requirements or not requirementsAmount or not price or not priceAmount then
		warn(`PenPlaceholderHandler: {TEMPLATE_NAME} needs Center.UnlockRequirement.Requirements/Price (each with an Amount label) and a {PURCHASE_TAG} prompt.`)
		model:Destroy()
		return nil
	end

	local placeholder: Placeholder = {
		model = model,
		prompt = prompt,
		requirements = requirements,
		requirementsAmount = requirementsAmount,
		price = price,
		priceAmount = priceAmount,
		slot = 0,
	}
	placeholders[plot] = placeholder

	prompt.Triggered:Connect(function(player: Player)
		onPurchase(plot, player)
	end)

	return placeholder
end

local function hide(plot: Folder)
	local placeholder = placeholders[plot]
	if placeholder then
		placeholder.model.Parent = nil
		placeholder.prompt.Enabled = false
		placeholder.slot = 0
	end
end

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

local function refreshPlot(plot: Folder)
	local owner = getPlotOwner(plot)
	local slotNumber = if owner then getNextSlot(owner) else nil
	local pivot = if slotNumber then PenHandler.getSlotPivot(plot, slotNumber) else nil
	if not owner or not slotNumber or not pivot then
		hide(plot)
		return
	end

	-- A slot beyond the owner's limit is locked behind a rebirth; with no rebirth that unlocks it there is nothing to show.
	local locked = slotNumber > PenSlotUnlocks.getSlotLimit(RebirthHandler.getRebirths(owner))
	local required = PenSlotUnlocks.getUnlockRebirth(slotNumber)
	if locked and not required then
		hide(plot)
		return
	end

	local placeholder = placeholders[plot] or createPlaceholder(plot)
	if not placeholder then
		return
	end

	placeholder.requirements.Visible = locked
	placeholder.price.Visible = not locked
	placeholder.prompt.Enabled = not locked
	if locked then
		setText(placeholder.requirementsAmount, tostring(required))
	else
		setText(placeholder.priceAmount, `${EconomyData.getPenPrice(slotNumber)}`)
	end

	if placeholder.slot ~= slotNumber or not placeholder.model.Parent then
		placeholder.model:PivotTo(pivot)
		placeholder.model.Parent = getFolder(plot)
		placeholder.slot = slotNumber
	end
end

local function refreshPlayerPlot(player: Player)
	local plot = PlotHandler.getPlayerPlot(player)
	if plot then
		refreshPlot(plot)
	end
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(function()
		refreshPlayerPlot(player)
	end)
end

function PenPlaceholderHandler.Setup()
	for _, plot in plotsFolder:GetChildren() do
		if plot:IsA("Folder") then
			plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(function()
				refreshPlot(plot)
			end)
			refreshPlot(plot)
		end
	end

	PenHandler.PenAdded:Connect(refreshPlayerPlot)
	PenHandler.PenRemoved:Connect(refreshPlayerPlot)

	players.PlayerAdded:Connect(watchPlayer)
	for _, player in players:GetPlayers() do
		watchPlayer(player)
	end
end

return PenPlaceholderHandler
