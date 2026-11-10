--[[
	Shows a row of owned pass icons (player attributes Pass<key> from GamePassService) above every owner's head, over their PlayerHUD.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PassPerksClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local PASS_ATTRIBUTE_PREFIX = "Pass" -- Pass<key> = true once owned (GamePassService)
local PASS_ORDER = { "DoubleWool", "DoubleLuck", "AutoShears" } -- left to right over the head

local ICON_STUDS = 0.8 -- each icon's size above the head
local ICON_OFFSET = Vector3.new(0, 3.75, 0) -- just over PlayerHUD (StudsOffset 2.5, 1.5 studs tall)
local ICON_MAX_DISTANCE = 80

--// State
local heads: { [Player]: BillboardGui } = {}

local function ownsPass(owner: Player, key: string): boolean
	return owner:GetAttribute(PASS_ATTRIBUTE_PREFIX .. key) == true
end

local function getOwnedKeys(owner: Player): { string }
	local owned = {}
	for _, key in PASS_ORDER do
		local item = MonetizationData.Items[key]
		if item and ownsPass(owner, key) and type(item.icon) == "string" then
			table.insert(owned, key)
		end
	end
	return owned
end

local function buildIcons(owner: Player)
	local old = heads[owner]
	if old then
		old:Destroy()
		heads[owner] = nil
	end

	local character = owner.Character
	local head = character and character:FindFirstChild("Head")
	local owned = getOwnedKeys(owner)
	if not head or not head:IsA("BasePart") or #owned == 0 then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = `PassIcons_{owner.UserId}`
	billboard.Adornee = head
	billboard.Size = UDim2.new(ICON_STUDS * #owned, 0, ICON_STUDS, 0)
	billboard.StudsOffset = ICON_OFFSET
	billboard.MaxDistance = ICON_MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = billboard

	for order, key in owned do
		local icon = Instance.new("ImageLabel")
		icon.Name = key
		icon.LayoutOrder = order
		icon.BackgroundTransparency = 1
		icon.Image = MonetizationData.Items[key].icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Size = UDim2.fromScale(1, 1)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.Parent = billboard
	end

	billboard.Parent = playerGui
	heads[owner] = billboard
end

local function watchPlayer(owner: Player)
	local function onCharacter(character: Model)
		buildIcons(owner)
		-- Loading the avatar can swap in a new Head.
		character.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Head" and owner.Character == character then
				buildIcons(owner)
			end
		end)
	end

	owner.CharacterAdded:Connect(onCharacter)
	for _, key in PASS_ORDER do
		owner:GetAttributeChangedSignal(PASS_ATTRIBUTE_PREFIX .. key):Connect(function()
			buildIcons(owner)
		end)
	end
	if owner.Character then
		onCharacter(owner.Character)
	end
end

players.PlayerAdded:Connect(watchPlayer)
players.PlayerRemoving:Connect(function(owner: Player)
	local billboard = heads[owner]
	if billboard then
		billboard:Destroy()
		heads[owner] = nil
	end
end)
for _, owner in players:GetPlayers() do
	task.spawn(watchPlayer, owner)
end
