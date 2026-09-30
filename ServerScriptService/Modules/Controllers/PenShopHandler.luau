--[[
	Server side of the pen shop.

	Pen styles are cosmetic. A player owns a set of styles (player attribute "OwnedPenSkins", a
	comma separated id list) and has one equipped ("PenSkinId"); both replicate to the client.
	Buying validates everything on the server (range, ownership, money), charges the player and
	equips the new style. The equipped style is painted onto all of the player's pens, and onto
	every pen they create later (PenHandler.PenAdded).

	Styles are matched part by part against the template models in ReplicatedStorage.Assets.Models.Pens
	by position inside the model, so plots whose child order differs still skin correctly.

	Ownership is not saved between sessions yet (the shear shop isn't either).

	Location: ServerScriptService.Modules.Controllers.PenShopHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local PenShopData = require(script.Parent.Parent.Constants.PenShopData)
local PenHandler = require(script.Parent.PenHandler)

--// Configs
local ACTION_COOLDOWN = 0.3
local OWNED_ATTRIBUTE = "OwnedPenSkins"
local EQUIPPED_ATTRIBUTE = "PenSkinId"
local MATCH_TOLERANCE = 0.5

--// State
local lastAction: { [Player]: number } = {}

local penShopHandler = {}

--// Helpers -------------------------------------------------------------------

local function getTemplates(): Instance
	return replicatedStorage.Assets.Models.Pens
end

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

local function getOwned(player: Player): { [string]: boolean }
	local owned: { [string]: boolean } = { [PenShopData.DefaultSkinId] = true }
	local raw = player:GetAttribute(OWNED_ATTRIBUTE)
	if type(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			if PenShopData.get(id) then
				owned[id] = true
			end
		end
	end
	return owned
end

local function setOwned(player: Player, owned: { [string]: boolean })
	local ids = {}
	for _, info in PenShopData.Skins do
		if owned[info.id] then
			table.insert(ids, info.id)
		end
	end
	player:SetAttribute(OWNED_ATTRIBUTE, table.concat(ids, ","))
end

local function getEquipped(player: Player): string
	local id = player:GetAttribute(EQUIPPED_ATTRIBUTE)
	return if PenShopData.get(id) then id :: string else PenShopData.DefaultSkinId
end

local function isNearShop(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	for _, prompt in collectionService:GetTagged(PenShopData.ShopPromptTag) do
		local holder = prompt.Parent
		local position: Vector3? = nil
		if holder and holder:IsA("BasePart") then
			position = holder.Position
		elseif holder and holder:IsA("Attachment") then
			position = holder.WorldPosition
		end

		if position and (rootPart.Position - position).Magnitude <= PenShopData.PurchaseRange then
			return true
		end
	end

	return false
end

-- The parts of a pen that carry its look: the fence pieces and the two floor plates.
local function collectParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("Model") and child.Name == "Fence_Side_1" then
			for _, part in child:GetChildren() do
				if part:IsA("BasePart") then
					table.insert(parts, part)
				end
			end
		elseif child:IsA("BasePart") and (child.Name == "SheepPos" or child.Name == "PlayerPos") then
			table.insert(parts, child)
		end
	end
	return parts
end

-- Paints a pen model with a style: each part copies the look of the template part at the same spot.
local function applySkin(model: Model, skinId: string)
	local template = getTemplates():FindFirstChild(skinId)
	if not template or not template:IsA("Model") then
		warn(`PenShopHandler: missing pen template {skinId}`)
		return
	end

	local templatePivot = template:GetPivot()
	local entries = {}
	for _, part in collectParts(template) do
		table.insert(entries, { relative = templatePivot:PointToObjectSpace(part.Position), size = part.Size, part = part })
	end

	local pivot = model:GetPivot()
	for _, part in collectParts(model) do
		local relative = pivot:PointToObjectSpace(part.Position)
		local best, bestDistance = nil, math.huge
		for _, entry in entries do
			local distance = (entry.relative - relative).Magnitude + (entry.size - part.Size).Magnitude
			if distance < bestDistance then
				best, bestDistance = entry, distance
			end
		end

		if best and bestDistance <= MATCH_TOLERANCE then
			part.Color = best.part.Color
			part.Material = best.part.Material
			part.Transparency = best.part.Transparency
		end
	end
end

local function applyToAllPens(player: Player)
	local skinId = getEquipped(player)
	for _, pen in PenHandler.getPens(player) do
		applySkin(pen.model, skinId)
	end
end

local function reply(player: Player, id: string, success: boolean, reason: string?)
	network.fireClient(network.RemoteEvents.PenSkinResult, player, id, success, reason)
end

--// Actions -------------------------------------------------------------------

local function equip(player: Player, id: string)
	player:SetAttribute(EQUIPPED_ATTRIBUTE, id)
	applyToAllPens(player)
end

-- action: "Buy" (paying with money), "BuyRobux" or "Equip"
local function onPenSkinAction(player: Player, action: any, id: any)
	local info = PenShopData.get(id)
	if type(action) ~= "string" or not info then
		return
	end

	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_COOLDOWN then
		return
	end
	lastAction[player] = now

	if not isNearShop(player) then
		reply(player, info.id, false, "TooFar")
		return
	end

	local owned = getOwned(player)

	if action == "Equip" then
		if not owned[info.id] then
			reply(player, info.id, false, "NotOwned")
			return
		end
		equip(player, info.id)
		reply(player, info.id, true, nil)
	elseif action == "Buy" then
		if owned[info.id] then
			reply(player, info.id, false, "Owned")
			return
		end

		local money = getMoney(player)
		if not money or money.Value < info.price then
			reply(player, info.id, false, "NoMoney")
			return
		end

		money.Value -= info.price
		owned[info.id] = true
		setOwned(player, owned)
		equip(player, info.id)
		print(`{player.Name} bought pen style {info.id} for {info.price}.`)
		reply(player, info.id, true, nil)
	elseif action == "BuyRobux" then
		-- Needs a developer product + MarketplaceService.ProcessReceipt; not set up yet.
		reply(player, info.id, false, "RobuxUnavailable")
	end
end

--// Public API ------------------------------------------------------------------

function penShopHandler.getEquipped(player: Player): string
	return getEquipped(player)
end

--// Lifecycle ----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	setOwned(player, { [PenShopData.DefaultSkinId] = true })
	player:SetAttribute(EQUIPPED_ATTRIBUTE, PenShopData.DefaultSkinId)
end

function penShopHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.PenSkinAction, onPenSkinAction)

	-- Pens bought later start out classic; give them the equipped style.
	PenHandler.PenAdded:Connect(function(player: Player, pen)
		local skinId = getEquipped(player)
		if skinId ~= PenShopData.DefaultSkinId then
			applySkin(pen.model, skinId)
		end
	end)

	players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in players:GetPlayers() do
		if player:GetAttribute(EQUIPPED_ATTRIBUTE) == nil then
			onPlayerAdded(player)
		end
	end

	players.PlayerRemoving:Connect(function(player: Player)
		lastAction[player] = nil
	end)
end

return penShopHandler
