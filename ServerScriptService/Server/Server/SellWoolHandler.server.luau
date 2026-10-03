--!strict

--[[
Sells a player's wool for money when they trigger a sell prompt

Location: ServerScriptService.Server.SellWoolHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local InventoryHandler = require(serverScriptService.Modules.Controllers.InventoryHandler)
local EconomyData = require(serverScriptService.Modules.Constants.EconomyData)
local RebirthData = require(serverScriptService.Modules.Constants.RebirthData)

--// Variables
local onCooldown: { [Player]: boolean } = {}

--// Configs
local SELL_PROMPT_TAG = "SellWool"
local WOOL_ITEM = "Wool"
local BASE_AMOUNT = EconomyData.WOOL_SELL_PRICE
local COOLDOWN_SECONDS = 3

local function calculateCashReward(player: Player, woolAmount: number): number
	local rebirths = player:GetAttribute("Rebirths")
	local multiplier = RebirthData.getWoolMultiplier(if type(rebirths) == "number" then rebirths else 0)
	return math.floor(woolAmount * BASE_AMOUNT * multiplier)
end

-- Sells the player's whole wool stack; nothing is taken unless the money can be paid out.
local function sellWool(player: Player)
	if onCooldown[player] then
		return
	end

	local woolAmount = InventoryHandler.getItem(player, WOOL_ITEM)
	if woolAmount <= 0 then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	if not money or not money:IsA("IntValue") then
		warn(`SellWoolHandler: {player.Name} has no Money stat.`)
		return
	end

	if not InventoryHandler.removeItem(player, WOOL_ITEM, woolAmount) then
		return
	end

	local cash = calculateCashReward(player, woolAmount)
	money.Value += cash
	print(`{player.Name} sold {woolAmount} wool for {cash}.`)
	network.fireClient(network.RemoteEvents.WoolSold, player, woolAmount, cash)

	onCooldown[player] = true
	task.delay(COOLDOWN_SECONDS, function()
		onCooldown[player] = nil
	end)
end

-- Every tagged prompt sells, so each plot's farmer works, including ones added later.
local function connectPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		warn(`SellWoolHandler: {instance:GetFullName()} is tagged {SELL_PROMPT_TAG} but is not a ProximityPrompt.`)
		return
	end

	instance.Triggered:Connect(sellWool)
end

for _, instance in collectionService:GetTagged(SELL_PROMPT_TAG) do
	connectPrompt(instance)
end
collectionService:GetInstanceAddedSignal(SELL_PROMPT_TAG):Connect(connectPrompt)

players.PlayerRemoving:Connect(function(player)
	onCooldown[player] = nil
end)
