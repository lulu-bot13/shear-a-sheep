--!strict

--[[
	/resetdata (or /restdata) chat command: puts the speaker back to a brand-new player's progress.
	Only the game's owner, or anyone in Studio, can use it.

	Location: ServerScriptService.Modules.Controllers.ResetDataHandler
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local textChatService = game:GetService("TextChatService")

--// Modules
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)

--// Configs
local PRIMARY_ALIAS = "/resetdata"
local SECONDARY_ALIAS = "/restdata"

local ResetDataHandler = {}

local function canReset(player: Player): boolean
	if runService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function onTriggered(textSource: TextSource)
	local player = players:GetPlayerByUserId(textSource.UserId)
	if not player or not canReset(player) or not PlayerDataHandler.getData(player) then
		return
	end

	PlayerDataHandler.reset(player)
	SheepSpawnHandler.resetFarm(player)
	print(`ResetDataHandler: reset {player.Name}'s data.`)
end

--// Lifecycle -----------------------------------------------------------------------

function ResetDataHandler.Start()
	local command = Instance.new("TextChatCommand")
	command.Name = "ResetDataCommand"
	command.PrimaryAlias = PRIMARY_ALIAS
	command.SecondaryAlias = SECONDARY_ALIAS
	command.Triggered:Connect(onTriggered)
	command.Parent = textChatService
end

return ResetDataHandler
