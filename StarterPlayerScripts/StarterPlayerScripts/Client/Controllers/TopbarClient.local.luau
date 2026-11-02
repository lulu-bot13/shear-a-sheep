--[[
	TopbarPlus buttons in the Roblox topbar: Settings (right) and Daily Rewards (left) toggle their windows, Invite Friends (left) opens the invite prompt.
	The window buttons do nothing until a script registers that window with WindowsManager.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.TopbarClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local socialService = game:GetService("SocialService")

--// Modules
local icon = require(replicatedStorage.TopbarPlus.Icon)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer

--// Configs
local PLACEHOLDER_ICON = "rbxassetid://0"
local SETTINGS_ICON = "rbxassetid://104843963165382" -- TODO: upload gear icon
local FRIENDS_ICON = "rbxassetid://71584993006217" -- TODO: upload friends icon
local DAILY_REWARDS_ICON = "rbxassetid://84569724458877"
local SETTINGS_WINDOW_NAME = "Settings"
local DAILY_REWARDS_WINDOW_NAME = "DailyRewards"

-- Shows the label text instead while the image is still the placeholder, so the button isn't blank.
local function setIconImage(topbarIcon, image: string, fallbackLabel: string)
	if image == PLACEHOLDER_ICON then
		topbarIcon:setLabel(fallbackLabel)
	else
		topbarIcon:setImage(image)
	end
end

--// Settings
local settingsIcon = icon.new()
	:setName("Settings")
	:align("Right")
	:oneClick()
setIconImage(settingsIcon, SETTINGS_ICON, "Settings")

settingsIcon.selected:Connect(function()
	local settingsWindow = windowsManager.get(SETTINGS_WINDOW_NAME)
	if settingsWindow then
		settingsWindow.toggle()
	end
end)

--// Daily Rewards
local dailyRewardsIcon = icon.new()
	:setName("DailyRewards")
	:align("Right")
	:oneClick()
setIconImage(dailyRewardsIcon, DAILY_REWARDS_ICON, "Daily Rewards")

dailyRewardsIcon.selected:Connect(function()
	local dailyRewardsWindow = windowsManager.get(DAILY_REWARDS_WINDOW_NAME)
	if dailyRewardsWindow then
		dailyRewardsWindow.toggle()
	end
end)

--// Invite Friends
local inviteIcon = icon.new()
	:setName("InviteFriends")
	:setCaption("Invite Friends")
	:align("Right")
	:oneClick()
setIconImage(inviteIcon, FRIENDS_ICON, "Invite")

local prompting = false

inviteIcon.selected:Connect(function()
	if prompting then
		return
	end
	prompting = true

	local success, canInvite = pcall(socialService.CanSendGameInviteAsync, socialService, player)
	if success and canInvite then
		pcall(socialService.PromptGameInvite, socialService, player)
	end
	prompting = false
end)
