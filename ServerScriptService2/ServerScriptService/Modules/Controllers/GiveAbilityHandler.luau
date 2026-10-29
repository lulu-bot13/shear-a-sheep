--!strict

--[[
	/giveability <player> <ability | all> chat command: adds the ability to the player's owned abilities and equips it.
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.GiveAbilityHandler
]]--

--// Modules
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local AbilityShackHandler = require(script.Parent.AbilityShackHandler)

--// Configs
local PRIMARY_ALIAS = "/giveability"
local SECONDARY_ALIAS = "/ga"
local ALL_KEYWORD = "all"

local GiveAbilityHandler = {}

-- Matches an id or display name, ignoring case and spaces, so "bat overhaul" and "batoverhaul" both work.
local function findAbility(query: string): AbilityData.AbilityInfo?
	local wanted = string.lower((string.gsub(query, "%s", "")))
	for _, id in AbilityData.Order do
		local ability = AbilityData.Abilities[id]
		if string.lower(id) == wanted or string.lower((string.gsub(ability.name, "%s", ""))) == wanted then
			return ability
		end
	end
	return nil
end

local function onTriggered(speaker: Player, message: string)
	local playerText, abilityText = string.match(message, "^%S+%s+(%S+)%s+(.-)%s*$")
	if not playerText or abilityText == "" then
		warn(`GiveAbilityHandler: usage is {PRIMARY_ALIAS} <player> <ability | {ALL_KEYWORD}> (abilities: {table.concat(AbilityData.Order, ", ")}).`)
		return
	end

	local target = AdminCommands.findPlayer(speaker, playerText)
	if not target then
		warn(`GiveAbilityHandler: no player matching "{playerText}".`)
		return
	end

	if string.lower(abilityText) == ALL_KEYWORD then
		for _, id in AbilityData.Order do
			AbilityShackHandler.grant(target, id)
		end
		print(`GiveAbilityHandler: gave {target.Name} every ability.`)
		return
	end

	local ability = findAbility(abilityText)
	if not ability then
		warn(`GiveAbilityHandler: unknown ability "{abilityText}" (abilities: {table.concat(AbilityData.Order, ", ")}).`)
		return
	end

	local isNew = AbilityShackHandler.grant(target, ability.id)
	local equipError = AbilityShackHandler.equip(target, ability.id)
	local equipNote = if equipError then ` (not equipped: {equipError})` else ", equipped"
	print(`GiveAbilityHandler: {if isNew then "gave" else "already owned,"} {target.Name} {ability.id}{equipNote}.`)
end

--// Lifecycle -----------------------------------------------------------------------

function GiveAbilityHandler.Start()
	AdminCommands.register("GiveAbilityCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
end

return GiveAbilityHandler
