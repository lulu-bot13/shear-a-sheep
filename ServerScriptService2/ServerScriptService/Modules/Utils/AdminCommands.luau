--!strict

--[[
	Shared helpers for the admin chat commands: who may use them, finding a player by name and registering a TextChatCommand.

	Location: ServerScriptService.Modules.Utils.AdminCommands
]]--

--// Services
local players = game:GetService("Players")
local runService = game:GetService("RunService")
local textChatService = game:GetService("TextChatService")

--// Configs
local GROUP_ID = 1106600128
local OWNER_USER_IDS = { -- the game is group-owned, so CreatorId can't identify its owner
	[392302380] = true,
}
local ADMIN_ROLES = { -- group role names allowed to use admin commands
	Testers = true,
}

local AdminCommands = {}

-- Anyone in OWNER_USER_IDS, the creator of a user-owned place, or anyone in Studio.
function AdminCommands.isOwner(player: Player): boolean
	if runService:IsStudio() or OWNER_USER_IDS[player.UserId] then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

-- The game's owner, group members with a role in ADMIN_ROLES, or anyone in Studio.
function AdminCommands.isAdmin(player: Player): boolean
	if AdminCommands.isOwner(player) then
		return true
	end
	local success, role = pcall(player.GetRoleInGroupAsync, player, GROUP_ID)
	return success and ADMIN_ROLES[role] == true
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
