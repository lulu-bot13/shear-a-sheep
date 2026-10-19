--[[
	Puts a copy of Workspace.Part.PlayerHUD on each player's head: display name with VIP, verified and Premium badges,
	and their best find with its rarity in that rarity's color.
]]--

--// Services
local players = game:GetService("Players")
local marketplaceService = game:GetService("MarketplaceService")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local SheepData = require(serverScriptService.Modules.Constants.SheepData)

--// Configs
local VIP_GAMEPASS_ID = 0 -- TODO: set to the VIP game pass id
local HUD_NAME = "PlayerHUD"
local VERIFIED_ICON = utf8.char(0xE000) -- Roblox's built-in verified badge glyph
local PREMIUM_ICON = utf8.char(0xE001) -- Roblox's built-in Premium glyph
local VIP_COLOR = "#FFD54A"

local hudTemplate = workspace:WaitForChild("Part"):WaitForChild(HUD_NAME) :: BillboardGui

--// State
local isVip: { [Player]: boolean } = {}

local function ownsVip(player: Player): boolean
	if VIP_GAMEPASS_ID == 0 then
		return false
	end

	local success, owns = pcall(marketplaceService.UserOwnsGamePassAsync, marketplaceService, player.UserId, VIP_GAMEPASS_ID)
	return success and owns == true
end

local function getDisplayNameText(player: Player): string
	local text = player.DisplayName
	if isVip[player] then
		text = `<font color="{VIP_COLOR}"><b>[VIP]</b></font> {text}`
	end
	if player.HasVerifiedBadge then
		text ..= ` {VERIFIED_ICON}`
	end
	if player.MembershipType == Enum.MembershipType.Premium then
		text ..= ` {PREMIUM_ICON}`
	end
	return text
end

local function getBestFindText(player: Player): string
	local bestFind = player:GetAttribute("BestFind")
	local info = if type(bestFind) == "string" then SheepData.Sheep[bestFind] else nil
	if not info then
		return "Best Find: None"
	end
	return `Best Find: {info.name} <font color="#{info.color:ToHex()}"><b>[{info.rarity}]</b></font>`
end

local function getHud(player: Player): BillboardGui?
	local head = player.Character and player.Character:FindFirstChild("Head")
	local hud = head and head:FindFirstChild(HUD_NAME)
	return if hud and hud:IsA("BillboardGui") then hud else nil
end

local function refreshHud(player: Player)
	local hud = getHud(player)
	if not hud then
		return
	end

	local displayName = hud:FindFirstChild("DisplayName")
	if displayName and displayName:IsA("TextLabel") then
		displayName.RichText = true
		displayName.Text = getDisplayNameText(player)
	end

	local bestFind = hud:FindFirstChild("BestFind")
	if bestFind and bestFind:IsA("TextLabel") then
		bestFind.RichText = true
		bestFind.Text = getBestFindText(player)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end

	local hud = hudTemplate:Clone()
	hud.Adornee = head
	hud.Parent = head
	refreshHud(player)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	player:GetAttributeChangedSignal("BestFind"):Connect(function()
		refreshHud(player)
	end)
	player:GetPropertyChangedSignal("MembershipType"):Connect(function()
		refreshHud(player)
	end)

	isVip[player] = ownsVip(player)
	refreshHud(player)
end

marketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, purchased)
	if purchased and gamePassId == VIP_GAMEPASS_ID then
		isVip[player] = true
		refreshHud(player)
	end
end)

players.PlayerAdded:Connect(onPlayerAdded)
players.PlayerRemoving:Connect(function(player)
	isVip[player] = nil
end)

-- Players who joined before this script connected.
for _, player in players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
