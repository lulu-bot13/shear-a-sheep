--[[
	Server side of the shear shop.

	Every player has exactly one equipped shear, stored as the player attribute "ShearId" (replicates to
	the client) and mirrored by a Tool in their Backpack. Bought shears stay in a temporary inventory
	("OwnedShears") and can be switched between at the shop. Buying a shear validates everything on
	the server (range, money), charges the player, equips it, destroys the old shear Tool and hands
	over the new one. The tool is re-synced on every respawn, since the
	StarterPack would otherwise hand back the default shear.

	Location: ServerScriptService.Modules.Controllers.ShearShopHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local ShearShopData = require(script.Parent.Parent.Constants.ShearShopData)
local ShearTimingData = require(replicatedStorage.Shared.Constants.ShearTimingData)

--// Configs
local PURCHASE_COOLDOWN = 0.3

--// State
local lastPurchase: { [Player]: number } = {}
local ownedShears: { [Player]: { [string]: boolean } } = {}

local shearShopHandler = {}

--// Helpers -------------------------------------------------------------------

local function getShearTemplates(): Instance
	return replicatedStorage.Assets.Shears
end

local function getMoney(player: Player): IntValue?
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return if money and money:IsA("IntValue") then money else nil
end

local function getShearId(player: Player): string
	local id = player:GetAttribute("ShearId")
	return if ShearShopData.get(id) then id :: string else ShearShopData.DefaultShearId
end

--[[
	Temporary inventory: the shears each player has bought, kept in memory only (lost when they leave).
	Mirrored to the player attribute "OwnedShears" ("DefaultShear,SteelShears") so the shop UI can read it.
]]--
local function isOwned(player: Player, id: string): boolean
	local owned = ownedShears[player]
	return owned ~= nil and owned[id] == true
end

local function addOwned(player: Player, id: string)
	local owned = ownedShears[player]
	if not owned then
		owned = {}
		ownedShears[player] = owned
	end
	owned[id] = true

	local ids: { string } = {}
	for _, info in ShearShopData.Shears do
		if owned[info.id] then
			table.insert(ids, info.id)
		end
	end
	player:SetAttribute("OwnedShears", table.concat(ids, ","))
end

-- Distance from a character to the closest shop prompt; nil if there is none / no character.
local function isNearShop(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	for _, prompt in collectionService:GetTagged(ShearShopData.ShopPromptTag) do
		local holder = prompt.Parent
		local position: Vector3? = nil
		if holder and holder:IsA("BasePart") then
			position = holder.Position
		elseif holder and holder:IsA("Attachment") then
			position = holder.WorldPosition
		end

		if position and (rootPart.Position - position).Magnitude <= ShearShopData.PurchaseRange then
			return true
		end
	end

	return false
end

-- Every shear Tool the player holds or carries (any container).
local function getShearTools(player: Player): { Tool }
	local found: { Tool } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and ShearShopData.get(child.Name) then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end

--[[
	Makes the player's tools match their ShearId: any other shear is destroyed, a missing one is
	cloned from the templates, and duplicates of the right one are removed.
]]--
local function syncTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local currentId = getShearId(player)
	local keeper: Tool? = nil

	for _, tool in getShearTools(player) do
		if tool.Name == currentId and not keeper then
			keeper = tool
		else
			tool:Destroy()
		end
	end

	if not keeper then
		local template = getShearTemplates():FindFirstChild(currentId)
		if not template or not template:IsA("Tool") then
			warn(`ShearShopHandler: missing shear template {currentId} in ReplicatedStorage.Assets.Shears`)
			return
		end

		keeper = template:Clone()
		keeper.Parent = backpack
	end
end

local function setShear(player: Player, id: string)
	local info = ShearShopData.get(id)
	if not info then
		return
	end

	player:SetAttribute("ShearId", id)
	syncTools(player)

	-- Required lazily: PenHandler -> Pen requires this module. Workers use the owner's shear too.
	for _, pen in require(script.Parent.PenHandler).getPens(player) do
		pen:refreshWorkerShears()
	end
end

local function reply(player: Player, id: string, success: boolean, reason: string?)
	network.fireClient(network.RemoteEvents.ShearPurchaseResult, player, id, success, reason)
end

--// Purchase ------------------------------------------------------------------

local function onPurchaseShear(player: Player, id: any)
	local info = ShearShopData.get(id)
	if not info then
		return
	end

	local now = os.clock()
	if now - (lastPurchase[player] or 0) < PURCHASE_COOLDOWN then
		return
	end
	lastPurchase[player] = now

	-- Required lazily: ShearHandler requires this module too.
	local ShearHandler = require(script.Parent.ShearHandler)
	if ShearHandler.isShearing(player) then
		reply(player, info.id, false, "Busy")
		return
	end

	if not isNearShop(player) then
		reply(player, info.id, false, "TooFar")
		return
	end

	if isOwned(player, info.id) then
		reply(player, info.id, false, "Owned")
		return
	end

	local money = getMoney(player)
	if not money or money.Value < info.price then
		reply(player, info.id, false, "NoMoney")
		return
	end

	money.Value -= info.price
	addOwned(player, info.id)
	setShear(player, info.id)
	print(`{player.Name} bought {info.id} for {info.price}.`)
	reply(player, info.id, true, nil)
end

-- Switches to a shear already in the player's (temporary) inventory.
local function onEquipShear(player: Player, id: any)
	local info = ShearShopData.get(id)
	if not info then
		return
	end

	local ShearHandler = require(script.Parent.ShearHandler)
	if ShearHandler.isShearing(player) then
		reply(player, info.id, false, "Busy")
		return
	end

	if not isNearShop(player) then
		reply(player, info.id, false, "TooFar")
		return
	end

	if not isOwned(player, info.id) then
		reply(player, info.id, false, "NotOwned")
		return
	end

	setShear(player, info.id)
	reply(player, info.id, true, nil)
end

--// Public API ------------------------------------------------------------------

function shearShopHandler.getShearId(player: Player): string
	return getShearId(player)
end

-- The player's shear stats for the shearing mini-game (multipliers; 1 = the basic shear).
function shearShopHandler.getStats(player: Player): ShearTimingData.ShearStats
	local info = ShearShopData.get(getShearId(player))
	if not info then
		return table.clone(ShearTimingData.DefaultShearStats)
	end

	return {
		damageMultiplier = info.damageMultiplier,
		zoneScale = info.zoneScale,
		cursorSpeed = info.cursorSpeed,
	}
end

-- Bumps the equipped shear's "Snips" attribute on every successful hit; clients watch it to play snip effects for everyone.
function shearShopHandler.registerSnip(player: Player)
	local currentId = getShearId(player)
	for _, tool in getShearTools(player) do
		if tool.Name == currentId then
			tool:SetAttribute("Snips", ((tool:GetAttribute("Snips") :: number?) or 0) + 1)
			return
		end
	end
end

--// Lifecycle ----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	addOwned(player, ShearShopData.DefaultShearId)
	setShear(player, ShearShopData.DefaultShearId)

	local function onCharacterAdded()
		-- The StarterPack fills the Backpack around spawn; sync once it has settled.
		player:WaitForChild("Backpack", 10)
		task.wait(0.1)
		if player.Parent then
			syncTools(player)
		end
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded)
	end
end

function shearShopHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.PurchaseShear, onPurchaseShear)
	network.connectEvent(network.RemoteEvents.EquipShear, onEquipShear)

	players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	players.PlayerRemoving:Connect(function(player: Player)
		lastPurchase[player] = nil
		ownedShears[player] = nil
	end)
end

return shearShopHandler
