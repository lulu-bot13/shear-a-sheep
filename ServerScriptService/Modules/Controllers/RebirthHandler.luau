--!strict

--[[
	Server side of rebirth. A rebirth needs a sheep of the required rarity seated in a pen (it is used up),
	enough money and enough wool. It resets money, wool, pens and upgrades and raises the "Rebirths" player attribute.

	Client requests (RebirthRequest): "Status" refreshes the screen, "Confirm" attempts the rebirth.
	Replies come on RebirthUpdate as (status, result?), where result is "Success" or the reason it was refused.

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

export type Requirement = {
	id: string,
	label: string,
	current: number,
	required: number,
	met: boolean,
}

export type Status = {
	rebirths: number,
	nextRebirth: number,
	maxed: boolean,
	canRebirth: boolean,
	money: { current: number, required: number, met: boolean },
	requirements: { Requirement },
}

local RebirthHandler = {}

--[[
	Gets a player's Money stat.

	@param player The player to look up

	@return The Money IntValue, or nil if the player has none
]]--
local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

--[[
	Gets how many rebirths a player has completed.

	@param player The player to look up

	@return The rebirth count, 0 if they have none
]]--
function RebirthHandler.getRebirths(player: Player): number
	local count = player:GetAttribute(REBIRTHS_ATTRIBUTE)
	return if type(count) == "number" then count else 0
end

--[[
	Finds a pen holding a seated sheep that is rare enough for a rebirth.

	@param player The player whose pens are searched
	@param n The rebirth being attempted

	@return The pen and its sheep, or nil for both if none qualifies
]]--
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

--[[
	Builds everything the rebirth screen shows: the money bar and one entry per item the player must have.

	@param player The player the screen is for

	@return The status table sent to the client
]]--
function RebirthHandler.getStatus(player: Player): Status
	local rebirths = RebirthHandler.getRebirths(player)
	local n = rebirths + 1
	local needed = RebirthData.getRequirements(n)

	local money = getMoney(player)
	local moneyHave = if money then money.Value else 0
	local woolHave = InventoryHandler.getItem(player, WOOL_ITEM)
	local _, sheep = findQualifyingSheep(player, n)

	local moneyMet = moneyHave >= needed.money
	local woolMet = woolHave >= needed.wool
	local sheepMet = sheep ~= nil
	local maxed = rebirths >= RebirthData.MAX_REBIRTHS

	return {
		rebirths = rebirths,
		nextRebirth = n,
		maxed = maxed,
		canRebirth = not maxed and moneyMet and woolMet and sheepMet,
		money = { current = moneyHave, required = needed.money, met = moneyMet },
		requirements = {
			{
				id = "Sheep",
				label = `{needed.minRarity} or better sheep in a pen`,
				current = if sheepMet then 1 else 0,
				required = 1,
				met = sheepMet,
			},
			{ id = "Wool", label = "Wool", current = woolHave, required = needed.wool, met = woolMet },
		},
	}
end

--[[
	Checks every requirement and, if all are met, performs the rebirth.

	@param player The player rebirthing

	@return "Success", or the reason it was refused: "Shearing", "Maxed", "NoSheep", "NoMoney" or "NoWool"
]]--
function RebirthHandler.tryRebirth(player: Player): string
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
	if not pen or not sheep then
		return "NoSheep"
	end
	if not money or not status.money.met then
		return "NoMoney"
	end
	if not InventoryHandler.hasItem(player, WOOL_ITEM, RebirthData.getRequirements(n).wool) then
		return "NoWool"
	end

	SheepHandler.removeSheep(pen.occupiedSheepId)
	pen:releaseSheep()

	InventoryHandler.removeItem(player, WOOL_ITEM, InventoryHandler.getItem(player, WOOL_ITEM))
	money.Value = RebirthData.getStartingMoney(n)
	player:SetAttribute(REBIRTHS_ATTRIBUTE, n)
	PenHandler.resetPens(player)

	print(`{player.Name} reached rebirth {n}.`)
	return "Success"
end

--[[
	Answers a client's rebirth request with the current status (and the result of a confirm).

	@param player The player who sent the request
	@param action "Status" or "Confirm"
]]--
local function onRebirthRequest(player: Player, action: any)
	local result = if action == "Confirm" then RebirthHandler.tryRebirth(player) else nil
	if action == "Status" or action == "Confirm" then
		network.fireClient(network.RemoteEvents.RebirthUpdate, player, RebirthHandler.getStatus(player), result)
	end
end

--[[
	Gives a player a Rebirths attribute of 0 if they don't have one yet.

	@param player The player to set up
]]--
local function setupPlayer(player: Player)
	if player:GetAttribute(REBIRTHS_ATTRIBUTE) == nil then
		player:SetAttribute(REBIRTHS_ATTRIBUTE, 0)
	end
end

--[[
	Starts listening for rebirth requests and sets up every player.
]]--
function RebirthHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RebirthRequest, onRebirthRequest, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN_SECONDS),
	})

	players.PlayerAdded:Connect(setupPlayer)
	for _, player in players:GetPlayers() do
		setupPlayer(player)
	end
end

return RebirthHandler
