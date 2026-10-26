--!strict

--[[
	/givewool [amount] chat command: adds wool to the speaker, or with no amount tops them up to their next rebirth's cost.
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.GiveWoolHandler
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local textChatService = game:GetService("TextChatService")

--// Modules
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Configs
local PRIMARY_ALIAS = "/givewool"
local SECONDARY_ALIAS = "/gw"

local GiveWoolHandler = {}

local function canGive(player: Player): boolean
	if runService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- Wool still missing for one more rebirth (0 when already affordable or maxed).
local function getMissingForRebirth(player: Player): number
	local state = RebirthHandler.getState(player)
	if state.maxed then
		return 0
	end
	local wool = PlayerDataHandler.get(player, "Wool") :: number
	return math.max(state.woolCost - wool, 0)
end

local function onTriggered(textSource: TextSource, message: string)
	local player = players:GetPlayerByUserId(textSource.UserId)
	if not player or not canGive(player) or not PlayerDataHandler.getData(player) then
		return
	end

	local amountText = string.match(message, "^%S+%s+(%S+)")
	local amount = if amountText then tonumber(amountText) else getMissingForRebirth(player)
	if not amount or amount <= 0 then
		return
	end

	local newWool = PlayerDataHandler.increment(player, "Wool", math.floor(amount))
	print(`GiveWoolHandler: gave {player.Name} {math.floor(amount)} wool (now {newWool}).`)
end

--// Lifecycle -----------------------------------------------------------------------

function GiveWoolHandler.Start()
	local command = Instance.new("TextChatCommand")
	command.Name = "GiveWoolCommand"
	command.PrimaryAlias = PRIMARY_ALIAS
	command.SecondaryAlias = SECONDARY_ALIAS
	command.Triggered:Connect(onTriggered)
	command.Parent = textChatService
end

return GiveWoolHandler
