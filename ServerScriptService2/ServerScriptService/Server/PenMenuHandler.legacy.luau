--[[
	The pen menu: pops up on its own when a plot owner walks up to one of their
	pens and closes again when they walk away. From it they can START SHEARING,
	upgrade the pen (better odds for rare sheep), automate it with a worker, or
	sell it (only the newest pen).

	Location: ServerScriptService.Server.PenMenuHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PenHandler = require(serverScriptService.Modules.Controllers.PenHandler)
local SheepHandler = require(serverScriptService.Modules.Controllers.SheepHandler)
local ShearHandler = require(serverScriptService.Modules.Controllers.ShearHandler)
local SheepData = require(serverScriptService.Modules.Constants.SheepData)
local EconomyData = require(serverScriptService.Modules.Constants.EconomyData)
local WorkerHandler = require(serverScriptService.Modules.Controllers.WorkerHandler)

--// Configs
local ENTER_DISTANCE = 11 -- studs from the pen's PlayerPos before the menu pops up
local EXIT_DISTANCE = 14 -- studs before it closes again (bigger, so it doesn't flicker at the edge)
local ACTION_DISTANCE = 19 -- how far away a player may still press the menu's buttons
local POLL_SECONDS = 0.05
local REPLACE_COOLDOWN_SECONDS = 0.5

type Zone = {
	penId: number,
	signature: string,
}

--// State
local zones: { [Player]: Zone } = {}
local lastReplace: { [Player]: number } = {}

--// Helpers -------------------------------------------------------------------

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

local function getMoneyAmount(player: Player): number
	local money = getMoney(player)
	return if money then money.Value else 0
end

-- Flat (ground-plane) distance from a player's character to a pen's PlayerPos; nil if they have no live character.
local function getDistanceToPen(player: Player, pen: any): number?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	local offset = rootPart.Position - pen.playerPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

-- Everything the client needs to draw the menu for one pen.
local function buildMenuData(player: Player, pen: any)
	local ownedPens = PenHandler.getPens(player)
	local canSell = pen.id == #ownedPens and pen.id > 1
	local level = pen:getLevel()
	local upgradeCost = EconomyData.getPenUpgradeCost(level)
	local multipliers = SheepData.UpgradeMultipliers[level] or SheepData.UpgradeMultipliers[1]
	local money = getMoneyAmount(player)
	local workers = WorkerHandler.getState(player)

	local sheep =if pen.occupiedSheepId then SheepHandler.getSheep(pen.occupiedSheepId) else nil
	local sheepReady = sheep ~= nil and pen.seated == true

	local sheepType, sheepName, rarity, rarityColor, sheepDamaged
	if sheep and sheepReady then
		sheepType = sheep:GetAttribute("SheepType")
		local data = if type(sheepType) == "string" then SheepData[sheepType] else nil
		sheepName = if data then data.name else sheep.Name
		rarity = sheep:GetAttribute("Rarity")
		rarityColor = sheep:GetAttribute("RarityColor")
		sheepDamaged = (sheep:GetAttribute("ShearHealth") :: number) < (sheep:GetAttribute("MaxShearHealth") :: number)
	end

	return {
		penId = pen.id,
		penName = `Pen {pen.id}`,
		penModel = pen.penModel,
		penType = pen.penType,
		level = level,
		maxLevel = SheepData.MaxPenLevel,
		luck = multipliers.Rare,
		upgradeCost = upgradeCost,
		canAffordUpgrade = upgradeCost ~= nil and money >= upgradeCost,
		workerHired = pen.data.automated,
		workersAvailable = workers.available,
		canSell = canSell,
		sellValue = if canSell then EconomyData.getPenSellValue(pen.id) else 0,
		sheepReady = sheepReady,
		sheepId = pen.occupiedSheepId,
		sheepType = sheepType,
		sheepName = sheepName,
		rarity = rarity,
		rarityColor = rarityColor,
		sheepDamaged = sheepDamaged == true,
	}
end

-- Only the parts of the menu data that change what's drawn (so we don't spam the client).
local function getSignature(data: any): string
	return table.concat({
		tostring(data.penId),
		tostring(data.penType),
		tostring(data.level),
		tostring(data.canAffordUpgrade),
		tostring(data.workerHired),
		tostring(data.workersAvailable),
		tostring(data.canSell),
		tostring(data.sheepReady),
		tostring(data.sheepId),
		tostring(data.sheepDamaged),
	}, "|")
end

-- Draws (or redraws) the menu on the player's screen and remembers what was sent.
local function pushMenu(player: Player, pen: any)
	local data = buildMenuData(player, pen)

	local zone = zones[player]
	if not zone or zone.penId ~= pen.id then
		zone = { penId = pen.id, signature = "" }
		zones[player] = zone
	end
	zone.signature = getSignature(data)

	network.fireClient(network.RemoteEvents.OpenPenMenu, player, data)
end

local function closeMenu(player: Player)
	if zones[player] then
		zones[player] = nil
		network.fireClient(network.RemoteEvents.ClosePenMenu, player)
	end
end

-- Returns the pen for a menu button press, or nil if the press isn't allowed.
local function getActionPen(player: Player, penId: any): any?
	if typeof(penId) ~= "number" or ShearHandler.isShearing(player) then
		return nil
	end

	local pen = PenHandler.getPen(player, penId)
	if not pen then
		return nil
	end

	local distance = getDistanceToPen(player, pen)
	if not distance or distance > ACTION_DISTANCE then
		return nil
	end

	return pen
end

--// Menu buttons ---------------------------------------------------------------

local function onUpgradePen(player: Player, penId: any)
	local pen = getActionPen(player, penId)
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
		pushMenu(player, pen)
	end
end

local function onSellPen(player: Player, penId: any)
	local pen = getActionPen(player, penId)
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
		closeMenu(player)
	end
end

local function onHireWorker(player: Player, penId: any)
	local pen = getActionPen(player, penId)
	if not pen then
		return
	end

	-- Puts one of the player's unused workers on this pen (buying them is done in the Hire Workers screen).
	if WorkerHandler.assign(player, pen) then
		pushMenu(player, pen)
	end
end

-- Takes the worker off the pen; it goes back to the player's unused workers.
local function onRemoveWorker(player: Player, penId: any)
	local pen = getActionPen(player, penId)
	if not pen or not pen.data.automated then
		return
	end

	pen:removeWorker()
	pushMenu(player, pen)
end

-- Swaps the pen's model for a pen from the player's inventory (chosen in the pen manager).
local function onReplacePen(player: Player, penId: any, penType: any)
	if typeof(penType) ~= "string" then
		return
	end

	local now = os.clock()
	if now - (lastReplace[player] or 0) < REPLACE_COOLDOWN_SECONDS then
		return
	end
	lastReplace[player] = now

	local pen = getActionPen(player, penId)
	if not pen then
		return
	end

	if PenHandler.replacePenModel(player, pen, penType) then
		pushMenu(player, pen)
	end
end

--// Walk-up detection -------------------------------------------------------------

-- Opens/closes/refreshes the menu depending on where the player is standing.
local function updateZone(player: Player)
	if ShearHandler.isShearing(player) then
		closeMenu(player)
		return
	end

	local zone = zones[player]
	local target: any = nil

	-- Stay on the current pen until the player is clearly out of range...
	if zone then
		local current = PenHandler.getPen(player, zone.penId)
		local distance = if current then getDistanceToPen(player, current) else nil
		if current and distance and distance <= EXIT_DISTANCE then
			target = current
		end
	end

	-- ...otherwise pick the closest pen they've walked up to.
	if not target then
		local nearestDistance = ENTER_DISTANCE
		for _, pen in PenHandler.getPens(player) do
			local distance = getDistanceToPen(player, pen)
			if distance and distance <= nearestDistance then
				nearestDistance = distance
				target = pen
			end
		end
	end

	if not target then
		closeMenu(player)
		return
	end

	local latest = zones[player]
	if not latest or latest.penId ~= target.id then
		latest = { penId = target.id, signature = "" }
		zones[player] = latest
	end

	local data = buildMenuData(player, target)
	local signature = getSignature(data)
	if signature ~= latest.signature then
		latest.signature = signature
		network.fireClient(network.RemoteEvents.OpenPenMenu, player, data)
	end
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradePen, onUpgradePen)
network.connectEvent(network.RemoteEvents.SellPen, onSellPen)
network.connectEvent(network.RemoteEvents.HireWorker, onHireWorker)
network.connectEvent(network.RemoteEvents.RemoveWorker, onRemoveWorker)
network.connectEvent(network.RemoteEvents.ReplacePen, onReplacePen)

players.PlayerRemoving:Connect(function(player: Player)
	zones[player] = nil
	lastReplace[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(POLL_SECONDS)
		for _, player in players:GetPlayers() do
			local ok, err = pcall(updateZone, player)
			if not ok then
				warn(`PenMenuHandler: {err}`)
			end
		end
	end
end)
