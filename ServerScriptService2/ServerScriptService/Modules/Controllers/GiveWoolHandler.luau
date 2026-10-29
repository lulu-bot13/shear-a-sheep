--!strict

--[[
	/givewool [player] [amount] chat command: adds wool to the named player (default the speaker), or with no amount
	tops them up to their next rebirth's cost. Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.GiveWoolHandler
]]--

--// Modules
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)

--// Configs
local PRIMARY_ALIAS = "/givewool"
local SECONDARY_ALIAS = "/gw"

local GiveWoolHandler = {}

-- Wool still missing for one more rebirth (0 when already affordable or maxed).
local function getMissingForRebirth(player: Player): number
	local state = RebirthHandler.getState(player)
	if state.maxed then
		return 0
	end
	local wool = PlayerDataHandler.get(player, "Wool") :: number
	return math.max(state.woolCost - wool, 0)
end

local function onTriggered(speaker: Player, message: string)
	-- "/givewool 500" targets the speaker; otherwise the first argument names the player.
	local firstArg, secondArg = string.match(message, "^%S+%s+(%S+)%s*(%S*)")
	local target: Player? = speaker
	local amountText: string? = nil
	if firstArg then
		if tonumber(firstArg) and secondArg == "" then
			amountText = firstArg
		else
			target = AdminCommands.findPlayer(speaker, firstArg)
			amountText = if secondArg ~= "" then secondArg else nil
		end
	end

	if not target then
		warn(`GiveWoolHandler: no player matching "{firstArg}".`)
		return
	end
	if not PlayerDataHandler.getData(target) then
		return
	end

	local amount = if amountText then tonumber(amountText) else getMissingForRebirth(target)
	if not amount or amount <= 0 then
		return
	end

	local newWool = PlayerDataHandler.increment(target, "Wool", math.floor(amount))
	print(`GiveWoolHandler: gave {target.Name} {math.floor(amount)} wool (now {newWool}).`)
end

--// Lifecycle -----------------------------------------------------------------------

function GiveWoolHandler.Start()
	AdminCommands.register("GiveWoolCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
end

return GiveWoolHandler
