--[[
	Every 15 minutes asks players who aren't in the game's group to join it, through GroupService:PromptJoinAsync.
	Stops once they join or send a join request; held back while the tutorial has the HUD hidden.
]]--

--// Services
local groupService = game:GetService("GroupService")
local players = game:GetService("Players")

--// Modules
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local GROUP_ID = 0 -- 0 = the group that owns the game
local PROMPT_INTERVAL_SECONDS = 15 * 60
local RETRY_SECONDS = 30 -- wait before trying again while the tutorial or a window is in the way

local groupId = if GROUP_ID ~= 0 then GROUP_ID elseif game.CreatorType == Enum.CreatorType.Group then game.CreatorId else 0
if groupId == 0 then
	warn("[GroupPromptClient] set GROUP_ID, the game isn't owned by a group")
	return
end

local function isInGroup(): boolean
	local success, inGroup = pcall(player.IsInGroupAsync, player, groupId)
	return success and inGroup == true
end

-- Main is disabled while the tutorial runs; a prompt over an open window would get in the way.
local function canPromptNow(): boolean
	local main = playerGui:FindFirstChild("Main")
	return main ~= nil and main:IsA("ScreenGui") and main.Enabled and not windowsManager.anyOpen()
end

while true do
	task.wait(PROMPT_INTERVAL_SECONDS)
	if isInGroup() then
		break
	end
	while not canPromptNow() do
		task.wait(RETRY_SECONDS)
	end

	local success, status = pcall(groupService.PromptJoinAsync, groupService, groupId)
	if success and status ~= Enum.GroupMembershipStatus.None then
		break -- Joined, AlreadyMember or JoinRequestPending
	end
end
