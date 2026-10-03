--!strict

--[[
	Server side of rebirth (prestige). To rebirth a player needs, all at once:
	  - a sheep of at least the required rarity seated in one of their pens (it is used up),
	  - enough money,
	  - enough wool in their inventory.
	Rebirthing resets money, wool, pens and pen upgrades, and raises the "Rebirths" player attribute,
	which drives the wool sell bonus (SellWoolHandler) and the Rare+ luck bonus (Pen).

	The client only asks and displays: every requirement is checked here, and the check and the
	reset happen without yielding so the state can't change in between.

	Request actions (RebirthRequest): "Status" refreshes the panel, "Confirm" attempts the rebirth.
	Replies come on RebirthUpdate as (status, result?) where result is "Success" or a failure reason.

	Location: ServerScriptService.Modules.Controllers.RebirthHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local InventoryHandler = require(script.Parent.InventoryHandler)
local PenHandler = require(script.Parent.PenHandler)
local ShearHandler = require(script.Parent.ShearHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)

--// Configs
local REBIRTHS_ATTRIBUTE = "Rebirths"
local WOOL_ITEM = "Wool"
local REQUEST_COOLDOWN_SECONDS = 0.3

export type Status = {
	rebirths: number,
	maxed: boolean,
	nextRebirth: number,
	minRarity: string,
	money: { have: number, need: number, met: boolean },
	wool: { have: number, need: number, met: boolean },
	sheep: { met: boolean, name: string? },
	canRebirth: boolean,
}

--// State
local rebirthing: { [Player]: boolean } = {}

local RebirthHandler = {}

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

function RebirthHandler.getRebirths(player: Player): number
	local count = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	return if type(count) == "number" then count else 0
end

-- Finds a pen whose seated sheep is good enough for rebirth n; returns the pen and the sheep.
local function findQualifyingSheep(player: Player, n: number): (any?, Model?)
	for _, pen in PenHandler.getPens(player) do
		local id = pen.occupiedSheepId
		local sheep = if id and pen.seated then SheepHandler.getSheep(id) else nil
		if sheep and RebirthData.meetsRarity(sheep:GetAttribute("Rarity"), n) then
			return pen, sheep
		end
	end
	return nil, nil
end

function RebirthHandler.getStatus(player: Player): Status
	local rebirths = RebirthHandler.getRebirths(player)
	local n = rebirths + 1
	local requirements = RebirthData.getRequirements(n)

	local money = getMoney(player)
	local moneyHave = if money then money.Value else 0
	local woolHave = InventoryHandler.getItem(player, WOOL_ITEM)
	local _, sheep = findQualifyingSheep(player, n)

	local maxed = rebirths >= RebirthData.MAX_REBIRTHS
	local moneyMet = moneyHave >= requirements.money
	local woolMet = woolHave >= requirements.wool
	local sheepMet = sheep ~= nil

	local sheepName = if sheep then sheep:GetAttribute("SheepName") else nil

	return {
		rebirths = rebirths,
		maxed = maxed,
		nextRebirth = n,
		minRarity = requirements.minRarity,
		money = { have = moneyHave, need = requirements.money, met = moneyMet },
		wool = { have = woolHave, need = requirements.wool, met = woolMet },
		sheep = { met = sheepMet, name = if type(sheepName) == "string" then sheepName else nil },
		canRebirth = not maxed and moneyMet and woolMet and sheepMet,
	}
end

-- Attempts a rebirth; returns "Success" or the reason it was refused.
function RebirthHandler.tryRebirth(player: Player): string
	if rebirthing[player] then
		return "Busy"
	end
	if ShearHandler.isShearing(player) then
		return "Shearing"
	end

	local status = RebirthHandler.getStatus(player)
	if status.maxed then
		return "Maxed"
	end

	local n = status.nextRebirth
	local pen, sheep = findQualifyingSheep(player, n)
	local money = getMoney(player)
	if not money then
		return "NoMoney"
	end
	if not sheep or not pen then
		return "NoSheep"
	end
	if not status.money.met then
		return "NoMoney"
	end
	if not status.wool.met then
		return "NoWool"
	end

	-- Everything is checked: from here to the end nothing yields, so it all happens or none of it does.
	rebirthing[player] = true

	local requirements = RebirthData.getRequirements(n)
	local sheepId = pen.occupiedSheepId :: number
	SheepHandler.removeSheep(sheepId)
	pen:releaseSheep()

	InventoryHandler.removeItem(player, WOOL_ITEM, InventoryHandler.getItem(player, WOOL_ITEM))
	money.Value = RebirthData.getStartingMoney(n)
	player:SetAttribute(REBIRTHS_ATTRIBUTE, n)
	PenHandler.resetPens(player)

	rebirthing[player] = nil
	print(`{player.Name} rebirthed (#{n}, needed {requirements.money} money, {requirements.wool} wool, {requirements.minRarity}+ sheep).`)
	return "Success"
end

local function onRebirthRequest(player: Player, action: any)
	if action == "Status" then
		network.fireClient(network.RemoteEvents.RebirthUpdate, player, RebirthHandler.getStatus(player), nil)
	elseif action == "Confirm" then
		local result = RebirthHandler.tryRebirth(player)
		network.fireClient(network.RemoteEvents.RebirthUpdate, player, RebirthHandler.getStatus(player), result)
	end
end

function RebirthHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RebirthRequest, onRebirthRequest, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN_SECONDS),
	})

	players.PlayerAdded:Connect(function(player: Player)
		if player:GetAttribute(REBIRTHS_ATTRIBUTE) == nil then
			player:SetAttribute(REBIRTHS_ATTRIBUTE, 0)
		end
	end)
	for _, player in players:GetPlayers() do
		if player:GetAttribute(REBIRTHS_ATTRIBUTE) == nil then
			player:SetAttribute(REBIRTHS_ATTRIBUTE, 0)
		end
	end

	players.PlayerRemoving:Connect(function(player: Player)
		rebirthing[player] = nil
	end)
end

return RebirthHandler
