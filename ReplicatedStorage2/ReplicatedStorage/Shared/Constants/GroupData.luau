--!strict

--[[
	The game's Roblox group (join prompts and the group shear's claim) and the shear its members can claim for free.
	Location: ReplicatedStorage.Shared.Constants.GroupData
]]--

local groupData = {}

groupData.GroupId = 0 -- 0 = the group that owns the game
groupData.RewardShearId = "RoyalShear" -- given by each plot's GroupShear to group members

-- The configured group, else the owning group's id, else 0 when a user owns the game.
function groupData.getGroupId(): number
	if groupData.GroupId ~= 0 then
		return groupData.GroupId
	end
	return if game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
end

return groupData
