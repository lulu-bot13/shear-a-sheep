--!strict

--[[
	/givegems [player] [amount] chat command: adds Gems (default 1) to the named player (default the speaker), with the Gem popup.
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.GiveGemsHandler
]]--

--// Modules
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local GemHandler = require(script.Parent.GemHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local PRIMARY_ALIAS = "/givegems"
local SECONDARY_ALIAS = "/gg"
local DEFAULT_AMOUNT = 1

local GiveGemsHandler = {}

local function onTriggered(speaker: Player, message: string)
	-- "/givegems 5" targets the speaker; otherwise the first argument names the player.
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
		warn(`GiveGemsHandler: no player matching "{firstArg}".`)
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
	local newGems = GemHandler.give(target, wholeAmount)
	print(`GiveGemsHandler: gave {target.Name} {wholeAmount} Gems (now {newGems}).`)
end

--// Lifecycle -----------------------------------------------------------------------

function GiveGemsHandler.Start()
	AdminCommands.register("GiveGemsCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
end

return GiveGemsHandler
