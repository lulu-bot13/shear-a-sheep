--!strict

--[[
	Each plot's GroupShear claim: group members get GroupData.RewardShearId for free, once (owning it counts as claimed).
	Location: ServerScriptService.Modules.Controllers.GroupShearHandler
]]--

--// Services
local groupService = game:GetService("GroupService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local GroupData = require(replicatedStorage.Shared.Constants.GroupData)
local ShearShopHandler = require(script.Parent.ShearShopHandler)

--// Configs
local CLAIM_COOLDOWN = 2 -- seconds; every claim makes a group web call

--// State
local lastClaim: { [Player]: number } = {}

local GroupShearHandler = {}

-- IsInGroupAsync can hold an old answer for a player who joined mid-session, so a "no" is checked against their group list.
local function isInGroup(player: Player, groupId: number): boolean
	local success, inGroup = pcall(player.IsInGroupAsync, player, groupId)
	if success and inGroup then
		return true
	end

	local listed, groups = pcall(groupService.GetGroupsAsync, groupService, player.UserId)
	if listed and type(groups) == "table" then
		for _, group in groups do
			if group.Id == groupId then
				return true
			end
		end
	end
	return false
end

local function onClaim(player: Player)
	local now = os.clock()
	if now - (lastClaim[player] or 0) < CLAIM_COOLDOWN then
		return
	end
	lastClaim[player] = now

	local shearId = GroupData.RewardShearId
	local groupId = GroupData.getGroupId()
	local reason: string? = nil
	if ShearShopHandler.ownsShear(player, shearId) then
		reason = "Owned"
	elseif groupId == 0 or not isInGroup(player, groupId) then
		reason = "NotInGroup"
	elseif not ShearShopHandler.grantShear(player, shearId) then
		reason = "Failed"
	end
	network.fireClient(network.RemoteEvents.GroupShearResult, player, reason == nil, reason)
end

function GroupShearHandler.Start()
	network.waitUntilReadyAsync()
	network.connectEvent(network.RemoteEvents.ClaimGroupShear, onClaim)

	players.PlayerRemoving:Connect(function(player: Player)
		lastClaim[player] = nil
	end)
end

return GroupShearHandler
