--!strict

--[[
	Shared helpers for the admin chat commands: who may use them, finding a player by name and registering a TextChatCommand.

	Location: ServerScriptService.Modules.Utils.AdminCommands
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local textChatService = game:GetService("TextChatService")

local AdminCommands = {}

-- Only the game's owner, or anyone in Studio.
function AdminCommands.isAdmin(player: Player): boolean
	if runService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- Matches "me", then an exact username/display name, then a username/display name prefix (case-insensitive).
function AdminCommands.findPlayer(speaker: Player, query: string): Player?
	local lowered = string.lower(query)
	if lowered == "me" then
		return speaker
	end

	local prefixMatch: Player? = nil
	for _, other in players:GetPlayers() do
		local name = string.lower(other.Name)
		local displayName = string.lower(other.DisplayName)
		if name == lowered or displayName == lowered then
			return other
		end
		if not prefixMatch and (string.sub(name, 1, #lowered) == lowered or string.sub(displayName, 1, #lowered) == lowered) then
			prefixMatch = other
		end
	end
	return prefixMatch
end

-- Creates the TextChatCommand; `onTriggered` only runs for admins.
function AdminCommands.register(name: string, primaryAlias: string, secondaryAlias: string, onTriggered: (speaker: Player, message: string) -> ())
	local command = Instance.new("TextChatCommand")
	command.Name = name
	command.PrimaryAlias = primaryAlias
	command.SecondaryAlias = secondaryAlias
	command.Triggered:Connect(function(textSource: TextSource, message: string)
		local speaker = players:GetPlayerByUserId(textSource.UserId)
		if speaker and AdminCommands.isAdmin(speaker) then
			onTriggered(speaker, message)
		end
	end)
	command.Parent = textChatService
end

return AdminCommands
