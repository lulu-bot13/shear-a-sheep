--!strict

--[[
	Friend boost: each friend in the server adds +10% wool (up to +40%), mirrored to the FriendBoost player attribute (e.g. 1.2).
	Friendships are checked once per pair on join (Player:IsFriendsWith) and cached until either leaves.

	Location: ServerScriptService.Modules.Controllers.FriendBoostHandler
]]--

--// Services
local players = game:GetService("Players")

--// Configs
local BOOST_PER_FRIEND = 0.1
local MAX_FRIENDS = 4
local ATTRIBUTE = "FriendBoost"

--// State
local friendsOf: { [Player]: { [Player]: boolean } } = {}

local FriendBoostHandler = {}

local function getFriendCount(player: Player): number
	local count = 0
	for other in friendsOf[player] or {} do
		if other.Parent then
			count += 1
		end
	end
	return count
end

local function updateBoost(player: Player)
	if player.Parent then
		player:SetAttribute(ATTRIBUTE, FriendBoostHandler.getMultiplier(player))
	end
end

-- 1 + 0.1 per friend in the server, at most 1.4.
function FriendBoostHandler.getMultiplier(player: Player): number
	return 1 + BOOST_PER_FRIEND * math.min(getFriendCount(player), MAX_FRIENDS)
end

local function onPlayerAdded(player: Player)
	friendsOf[player] = friendsOf[player] or {}
	updateBoost(player)

	for _, other in players:GetPlayers() do
		if other == player or not friendsOf[other] then
			continue
		end
		local success, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
		if success and isFriend and player.Parent and other.Parent and friendsOf[player] and friendsOf[other] then
			friendsOf[player][other] = true
			friendsOf[other][player] = true
			updateBoost(player)
			updateBoost(other)
		end
	end
end

local function onPlayerRemoving(player: Player)
	local friends = friendsOf[player]
	friendsOf[player] = nil
	for other in friends or {} do
		local otherFriends = friendsOf[other]
		if otherFriends then
			otherFriends[player] = nil
			updateBoost(other)
		end
	end
end

function FriendBoostHandler.Start()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return FriendBoostHandler
