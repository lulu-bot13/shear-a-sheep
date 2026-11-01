--!strict

--[[
	/givesheared [player] [amount] chat command: adds to the named player's (default the speaker) lifetime sheep sheared (default 10).
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.GiveShearedHandler
]]--

--// Modules
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local PRIMARY_ALIAS = "/givesheared"
local SECONDARY_ALIAS = "/gs"
local DEFAULT_AMOUNT = 10

local GiveShearedHandler = {}

local function onTriggered(speaker: Player, message: string)
	-- "/givesheared 5" targets the speaker; otherwise the first argument names the player.
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
		warn(`GiveShearedHandler: no player matching "{firstArg}".`)
		return
	end
	if not PlayerDataHandler.getData(target) then
		return
	end

	local amount = if amountText then tonumber(amountText) else DEFAULT_AMOUNT
	if not amount or amount < 1 then
		return
	end

	local wholeAmount = math.floor(amount)
	local newCount = PlayerDataHandler.increment(target, "SheepShearedCount", wholeAmount)
	print(`GiveShearedHandler: gave {target.Name} {wholeAmount} sheep sheared (now {newCount}).`)
end

--// Lifecycle -----------------------------------------------------------------------

function GiveShearedHandler.Start()
	AdminCommands.register("GiveShearedCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
end

return GiveShearedHandler
