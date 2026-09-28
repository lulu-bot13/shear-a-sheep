--!strict

--[[
	Lets a plot's owner select one of their pens -- by walking up to its
	"Manage Pen" proximity prompt, or by clicking it with the mouse -- to
	open a small management menu: see the pen's current rarity boost,
	upgrade it, sell it (last pen only) and hire an auto-shearing worker.

	Location: ServerScriptService.Server.PenMenuHandler
]]--

--// Services
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PenHandler = require(serverScriptService.Modules.Controllers.PenHandler)
local PenClass = require(serverScriptService.Modules.Classes.Pen)
local SheepData = require(serverScriptService.Modules.Constants.SheepData)
local EconomyData = require(serverScriptService.Modules.Constants.EconomyData)
type Pen = PenClass.Pen

--// Configs
local SELECT_HIGHLIGHT_SECONDS = 1.5
local MANAGE_ACTION_TEXT = "Manage Pen"
local MAX_ACTIVATION_DISTANCE = 10
local CLICK_MAX_DISTANCE = 32
local SELECTION_COLOR = Color3.fromRGB(255, 205, 70)

-- Briefly outlines the pen so a click/prompt trigger reads as a clear "selection".
local function flashSelection(pen: Pen)
	local existing = pen.model:FindFirstChild("_SelectionHighlight")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "_SelectionHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = SELECTION_COLOR
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = pen.model

	debris:AddItem(highlight, SELECT_HIGHLIGHT_SECONDS)
end

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

-- Everything the client needs to render the pen menu for one pen.
local function buildMenuData(player: Player, pen: Pen)
	local ownedPens = PenHandler.getPens(player)
	local isLast = pen.id == #ownedPens
	local canSell = isLast and pen.id > 1
	local level = pen:getLevel()

	return {
		penId = pen.id,
		penName = pen.model.Name,
		level = level,
		maxLevel = SheepData.MaxPenLevel,
		multipliers = SheepData.UpgradeMultipliers[level] or SheepData.UpgradeMultipliers[1],
		rarityOrder = SheepData.RarityOrder,
		rarityColors = SheepData.RarityColors,
		upgradeCost = EconomyData.getPenUpgradeCost(level),
		canSell = canSell,
		sellValue = canSell and EconomyData.getPenSellValue(pen.id) or 0,
		workerHired = pen.data.automated,
		workerCost = EconomyData.WORKER_HIRE_COST,
	}
end

local function openMenu(player: Player, pen: Pen)
	flashSelection(pen)
	network.fireClient(network.RemoteEvents.OpenPenMenu, player, buildMenuData(player, pen))
end

local function onUpgradePen(player: Player, penId: number)
	if typeof(penId) ~= "number" then
		return
	end

	local pen = PenHandler.getPen(player, penId)
	if not pen then
		return
	end

	local cost = EconomyData.getPenUpgradeCost(pen:getLevel())
	if not cost then
		return -- already at max level
	end

	local money = getMoney(player)
	if not money or money.Value < cost then
		return
	end

	if pen:upgrade() then
		money.Value -= cost
		openMenu(player, pen)
	end
end

local function onSellPen(player: Player, penId: number)
	if typeof(penId) ~= "number" then
		return
	end

	local pen = PenHandler.getPen(player, penId)
	if not pen then
		return
	end

	local ownedPens = PenHandler.getPens(player)
	if pen.id ~= #ownedPens or pen.id <= 1 then
		return -- only the most recently bought pen can be sold, and never the base pen
	end

	local refund = EconomyData.getPenSellValue(pen.id)
	if PenHandler.removePen(player, pen) then
		local money = getMoney(player)
		if money then
			money.Value += refund
		end
		network.fireClient(network.RemoteEvents.ClosePenMenu, player)
	end
end

local function onHireWorker(player: Player, penId: number)
	if typeof(penId) ~= "number" then
		return
	end

	local pen = PenHandler.getPen(player, penId)
	if not pen or pen.data.automated then
		return
	end

	local money = getMoney(player)
	if not money or money.Value < EconomyData.WORKER_HIRE_COST then
		return
	end

	if pen:hireWorker() then
		money.Value -= EconomyData.WORKER_HIRE_COST
		openMenu(player, pen)
	end
end

-- Wires the "Manage Pen" prompt and mouse-click selection onto one newly created pen.
local function connectPen(player: Player, pen: Pen)
	local playerPos = pen.model:FindFirstChild("PlayerPos")
	if not playerPos or not playerPos:IsA("BasePart") then
		warn(`PenMenuHandler: {pen.model.Name} has no PlayerPos to attach a menu prompt to.`)
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ManagePenPrompt"
	prompt.ActionText = MANAGE_ACTION_TEXT
	prompt.ObjectText = pen.model.Name
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = MAX_ACTIVATION_DISTANCE
	prompt.Parent = playerPos

	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == player then
			openMenu(player, pen)
		end
	end)

	-- Mouse-click selection: clicking anywhere on the pen's marker parts opens the same menu.
	for _, part in { playerPos, pen.model:FindFirstChild("SheepPos") } do
		if part and part:IsA("BasePart") then
			local clickDetector = Instance.new("ClickDetector")
			clickDetector.Name = "ManagePenClick"
			clickDetector.MaxActivationDistance = CLICK_MAX_DISTANCE
			clickDetector.Parent = part

			clickDetector.MouseClick:Connect(function(clickingPlayer: Player)
				if clickingPlayer == player then
					openMenu(player, pen)
				end
			end)
		end
	end
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradePen, onUpgradePen)
network.connectEvent(network.RemoteEvents.SellPen, onSellPen)
network.connectEvent(network.RemoteEvents.HireWorker, onHireWorker)

-- Connect first, THEN catch up on any pens created before this script got a chance to
-- connect (e.g. base pens handed out to players who joined before this script ran) --
-- covers both possible orderings against PenHandler.Setup() without ever double-connecting.
PenHandler.PenAdded:Connect(connectPen)

for _, player in players:GetPlayers() do
	for _, pen in PenHandler.getPens(player) do
		if not pen.model:FindFirstChild("ManagePenPrompt", true) then
			connectPen(player, pen)
		end
	end
end
