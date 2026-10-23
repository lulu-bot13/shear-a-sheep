--[[
	Puts a copy of ReplicatedStorage.Assets.UI.PlayerHUD on each player's head: display name with VIP, verified and
	Roblox Plus badges, their best find as its base odds ("Best Find: 1 in 9B") in its rarity's color, and their title.
]]--

--// Services
local players = game:GetService("Players")
local marketplaceService = game:GetService("MarketplaceService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local SheepData = require(serverScriptService.Modules.Constants.SheepData)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Configs
local VIP_GAMEPASS_ID = 0 -- TODO: set to the VIP game pass id
local HUD_NAME = "PlayerHUD"
local VERIFIED_ICON = utf8.char(0xE000) -- Roblox's built-in verified badge glyph
local PLUS_ICON = utf8.char(0xE003) -- Roblox's built-in Roblox Plus glyph
local VIP_COLOR = "#FFD54A"
local DEBUG = false -- TODO: set to false once the HUD shows up

local function debugLog(message: string)
	if DEBUG then
		print(`[PlayerHUD] {message}`)
	end
end

debugLog("script started (new version: template from ReplicatedStorage.Assets.UI)")

local hudTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("UI"):WaitForChild(HUD_NAME) :: BillboardGui
if not hudTemplate:IsA("BillboardGui") then
	warn(`[PlayerHUD] Assets.UI.{HUD_NAME} is a {hudTemplate.ClassName}, it needs to be a BillboardGui`)
end
debugLog(`found template ({hudTemplate.ClassName}), children: {#hudTemplate:GetChildren()}`)

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
		text ..= ` {PLUS_ICON}`
	end
	return text
end

local function getBestFindText(player: Player): string
	local bestFind = player:GetAttribute("BestFind")
	local info = if type(bestFind) == "string" then SheepData.Sheep[bestFind] else nil
	local odds = if info then SheepData.getOdds(bestFind, 0) else nil
	if not info or not odds then
		return "Best Find: None"
	end
	return `Best Find: <font color="#{info.color:ToHex()}"><b>1 in {numberFormatter:Format(odds, 1)}</b></font>`
end

local function getHud(player: Player): BillboardGui?
	local hud = player.Character and player.Character:FindFirstChild(HUD_NAME)
	return if hud and hud:IsA("BillboardGui") then hud else nil
end

local function refreshHud(player: Player)
	local hud = getHud(player)
	if not hud then
		debugLog(`refresh skipped for {player.Name}: no HUD on their character yet`)
		return
	end

	local displayName = hud:FindFirstChild("DisplayName")
	if displayName and displayName:IsA("TextLabel") then
		displayName.Visible = true
		displayName.RichText = true
		displayName.Text = getDisplayNameText(player)
		debugLog(`{player.Name} DisplayName = "{displayName.Text}"`)
	else
		warn(`[PlayerHUD] no DisplayName TextLabel in the HUD`)
	end

	local bestFind = hud:FindFirstChild("BestFind")
	if bestFind and bestFind:IsA("TextLabel") then
		bestFind.Visible = true
		bestFind.RichText = true
		bestFind.Text = getBestFindText(player)
		debugLog(`{player.Name} BestFind = "{bestFind.Text}"`)
	else
		warn(`[PlayerHUD] no BestFind TextLabel in the HUD`)
	end

	local title = hud:FindFirstChild("Title")
	local titleName = player:GetAttribute("Title")
	local titleColor = player:GetAttribute("TitleColor")
	if title and title:IsA("TextLabel") then
		title.Visible = true
		title.Text = if type(titleName) == "string" then titleName else ""
		if typeof(titleColor) == "Color3" then
			title.TextColor3 = titleColor
		end
		debugLog(`{player.Name} Title = "{title.Text}"`)
	else
		warn(`[PlayerHUD] no Title TextLabel in the HUD`)
	end
end

-- The HUD lives on the character, not the head: loading the avatar's appearance can swap in a new Head part,
-- which would destroy a HUD parented to the old one. The adornee follows whichever Head is current.
local function onCharacterAdded(player: Player, character: Model)
	local hud = hudTemplate:Clone()
	hud.Enabled = true
	hud.Parent = character
	debugLog(`added HUD to {player.Name}'s character`)

	local function adornHead()
		local head = character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			hud.Adornee = head
			debugLog(`{player.Name} HUD adornee = {head:GetFullName()} (Size {hud.Size}, StudsOffset {hud.StudsOffset}, MaxDistance {hud.MaxDistance})`)
		end
	end

	character.ChildAdded:Connect(function(child)
		if child.Name == "Head" then
			adornHead()
		end
	end)

	if not character:WaitForChild("Head", 10) then
		warn(`PlayerHUD: {player.Name}'s character has no Head`)
	end
	adornHead()
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
	player:GetAttributeChangedSignal("Title"):Connect(function()
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
