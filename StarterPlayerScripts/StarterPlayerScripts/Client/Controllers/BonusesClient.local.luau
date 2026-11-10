--[[
	Main.Bonuses: the 2x Luck / 2x Wool pass badges (GamePassService's Pass<key> attributes) and the Roblox Premium +10% Luck badge,
	bright while active and dimmed otherwise. Clicking an inactive badge prompts that game pass or Premium.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.BonusesClient
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)

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

local ACTIVE_BACKGROUND = Color3.fromRGB(45, 160, 75)
local INACTIVE_BACKGROUND = Color3.fromRGB(20, 24, 34)
local ACTIVE_TINT = Color3.new(1, 1, 1)
local INACTIVE_TINT = Color3.fromRGB(110, 110, 120)
local INACTIVE_TEXT_COLOR = Color3.fromRGB(165, 165, 175)
local INACTIVE_ICON_TRANSPARENCY = 0.3

type Badge = {
	button: GuiButton,
	icon: ImageLabel?,
	caption: TextLabel?,
	plus: GuiObject?, -- the green "+" corner, shown while the badge can be bought
}

--// State
local badges: { [string]: Badge } = {}
local boundMain: Instance? = nil

local function isActive(name: string): boolean
	if name == PREMIUM_BADGE then
		return player.MembershipType == Enum.MembershipType.Premium
	end
	return player:GetAttribute(PASS_ATTRIBUTE_PREFIX .. name) == true
end

local function paint(name: string)
	local badge = badges[name]
	if not badge then
		return
	end
	local active = isActive(name)
	badge.button.BackgroundColor3 = if active then ACTIVE_BACKGROUND else INACTIVE_BACKGROUND
	if badge.icon then
		badge.icon.ImageColor3 = if active then ACTIVE_TINT else INACTIVE_TINT
		badge.icon.ImageTransparency = if active then 0 else INACTIVE_ICON_TRANSPARENCY
	end
	if badge.caption then
		badge.caption.TextColor3 = if active then ACTIVE_TINT else INACTIVE_TEXT_COLOR
	end
	if badge.plus then
		badge.plus.Visible = not active
	end
end

local function onBadgeClicked(name: string)
	if isActive(name) then
		alerts.show(ACTIVE_TEXT[name], "success")
		return
	end
	if name == PREMIUM_BADGE then
		marketplaceService:PromptPremiumPurchase(player)
		return
	end

	local item = MonetizationData.get(name)
	if item and item.kind == "GamePass" and item.id ~= 0 then
		purchaseEffect.play()
		marketplaceService:PromptGamePassPurchase(player, item.id)
	end
end

local function bindBadge(frame: Instance, name: string)
	local button = frame:FindFirstChild(name)
	if not button or not button:IsA("GuiButton") then
		warn(`BonusesClient: Main.{FRAME_NAME}.{name} button is missing; build it in Studio.`)
		return
	end

	local icon = button:FindFirstChild("Icon")
	local caption = button:FindFirstChild("Caption")
	local plus = button:FindFirstChild("Plus")
	local item = MonetizationData.get(name)
	if item and item.icon and icon and icon:IsA("ImageLabel") then
		icon.Image = item.icon
	end

	badges[name] = {
		button = button,
		icon = if icon and icon:IsA("ImageLabel") then icon else nil,
		caption = if caption and caption:IsA("TextLabel") then caption else nil,
		plus = if plus and plus:IsA("GuiObject") then plus else nil,
	}
	button.Activated:Connect(function()
		onBadgeClicked(name)
	end)
	paint(name)
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
		paint(name)
	end)
end
players.PlayerMembershipChanged:Connect(function(changed: Player)
	if changed == player then
		paint(PREMIUM_BADGE)
	end
end)

playerGui.ChildAdded:Connect(bind)
local existing = playerGui:FindFirstChild("Main")
if existing then
	task.spawn(bind, existing)
end
