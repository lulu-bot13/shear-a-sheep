--[[
	Main.Bonuses: the 2x Luck / 2x Wool pass badges and the Premium +10% Luck badge, each shown only while the player has it.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.BonusesClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local alerts = require(script.Parent.Parent.Modules.Alerts)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local FRAME_NAME = "Bonuses" -- in StarterGui.Main
local GUI_WAIT_SECONDS = 10
local PASS_ATTRIBUTE_PREFIX = "Pass" -- GamePassService: Pass<key> = true once the pass is owned
local PREMIUM_BADGE = "Premium"
local PASS_BADGES = { "DoubleLuck", "DoubleWool" } -- badge names are MonetizationData keys
local ACTIVE_TEXT = {
	DoubleLuck = "2x Luck is active!",
	DoubleWool = "2x Wool is active!",
	Premium = "Premium: +10% Luck is active!",
}

--// State
local badges: { [string]: GuiButton } = {}
local boundMain: Instance? = nil

local function isActive(name: string): boolean
	if name == PREMIUM_BADGE then
		return player.MembershipType == Enum.MembershipType.Premium
	end
	return player:GetAttribute(PASS_ATTRIBUTE_PREFIX .. name) == true
end

local function refresh(name: string)
	local button = badges[name]
	if button then
		button.Visible = isActive(name)
	end
end

local function bindBadge(frame: Instance, name: string)
	local button = frame:FindFirstChild(name)
	if not button or not button:IsA("GuiButton") then
		warn(`BonusesClient: Main.{FRAME_NAME}.{name} button is missing; build it in Studio.`)
		return
	end

	local icon = button:FindFirstChild("Icon")
	local item = MonetizationData.get(name)
	if item and item.icon and icon and icon:IsA("ImageLabel") then
		icon.Image = item.icon
	end

	badges[name] = button
	button.Activated:Connect(function()
		alerts.show(ACTIVE_TEXT[name], "success")
	end)
	refresh(name)
end

-- Main resets on spawn, so the badges are found again in each new copy.
local function bind(main: Instance)
	if main.Name ~= "Main" or not main:IsA("ScreenGui") or main == boundMain then
		return
	end
	boundMain = main
	local frame = main:WaitForChild(FRAME_NAME, GUI_WAIT_SECONDS)
	if not frame then
		warn(`BonusesClient: PlayerGui.Main.{FRAME_NAME} is missing; build it in Studio.`)
		return
	end

	table.clear(badges)
	for _, name in PASS_BADGES do
		bindBadge(frame, name)
	end
	bindBadge(frame, PREMIUM_BADGE)
end

for _, name in PASS_BADGES do
	player:GetAttributeChangedSignal(PASS_ATTRIBUTE_PREFIX .. name):Connect(function()
		refresh(name)
	end)
end
players.PlayerMembershipChanged:Connect(function(changed: Player)
	if changed == player then
		refresh(PREMIUM_BADGE)
	end
end)

playerGui.ChildAdded:Connect(bind)
local existing = playerGui:FindFirstChild("Main")
if existing then
	task.spawn(bind, existing)
end
