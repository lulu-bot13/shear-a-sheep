--[[
	Server side of the shear shop: buying shears with wool once enough sheep are sheared, switching between owned ones and keeping the
	equipped shear's Tool in the player's Backpack. Owned and equipped shears are saved through PlayerDataHandler.

	Location: ServerScriptService.Modules.Controllers.ShearShopHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local PURCHASE_COOLDOWN = 0.3

--// State
local lastPurchase: { [Player]: number } = {}

local shearShopHandler = {}

--// Helpers -------------------------------------------------------------------

local function getShearTemplates(): Instance
	return replicatedStorage.Assets.Shears
end

local function getShearId(player: Player): string
	local id = player:GetAttribute("ShearId")
	return if ShearData.get(id) then id :: string else ShearData.DefaultShearId
end

local function getOwned(player: Player): { string }
	local owned = PlayerDataHandler.get(player, "OwnedShears")
	return if type(owned) == "table" then owned else { ShearData.DefaultShearId }
end

local function isOwned(player: Player, id: string): boolean
	return table.find(getOwned(player), id) ~= nil
end

-- Mirrored as "DefaultShear,SteelShears" so the shop UI can read it.
local function updateOwnedAttribute(player: Player)
	player:SetAttribute("OwnedShears", table.concat(getOwned(player), ","))
end

local function addOwned(player: Player, id: string)
	local owned = table.clone(getOwned(player))
	if not table.find(owned, id) then
		table.insert(owned, id)
	end
	PlayerDataHandler.set(player, "OwnedShears", owned)
	updateOwnedAttribute(player)
end

local function getShopHitbox(): BasePart?
	local hitbox = workspace:FindFirstChild("Base")
	for _, name in { "CenterPlaza", "ShearShop", "Shack", "ShearShopHitbox" } do
		hitbox = hitbox and hitbox:FindFirstChild(name)
	end
	return if hitbox and hitbox:IsA("BasePart") then hitbox else nil
end

local function isNearShop(player: Player): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return false
	end

	local hitbox = getShopHitbox()
	if not hitbox then
		return false
	end

	-- Distance to the hitbox's surface, so the hitbox's size doesn't matter.
	local offset = hitbox.CFrame:PointToObjectSpace(rootPart.Position)
	local half = hitbox.Size / 2
	local clamped = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return (offset - clamped).Magnitude <= ShearData.PurchaseRange
end

-- Every shear Tool the player holds or carries (any container).
local function getShearTools(player: Player): { Tool }
	local found: { Tool } = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and ShearData.get(child.Name) then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end

-- Makes the player's tools match their ShearId: other shears are destroyed and a missing one is cloned in.
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
	end

	-- The client sizes the hitbox ring and paces its swings from these.
	local tool = keeper :: Tool
	local info = ShearData.get(currentId)
	if info then
		tool:SetAttribute("ShearRange", info.range)
		tool:SetAttribute("ShearCooldown", ShearData.SwingCooldown)
	end
	if not tool.Parent then
		tool.Parent = backpack
	end
end

local function setShear(player: Player, id: string)
	if not ShearData.get(id) then
		return
	end

	PlayerDataHandler.set(player, "ShearId", id)
	player:SetAttribute("ShearId", id)
	syncTools(player)
end

local function reply(player: Player, id: string, success: boolean, reason: string?)
	network.fireClient(network.RemoteEvents.ShearPurchaseResult, player, id, success, reason)
end

--// Remote handlers ---------------------------------------------------------------

local function onPurchaseShear(player: Player, id: any)
	local info = ShearData.get(id)
	if not info or not PlayerDataHandler.getData(player) then
		return
	end

	local now = os.clock()
	if now - (lastPurchase[player] or 0) < PURCHASE_COOLDOWN then
		return
	end
	lastPurchase[player] = now

	if not isNearShop(player) then
		reply(player, info.id, false, "TooFar")
		return
	end

	if isOwned(player, info.id) then
		reply(player, info.id, false, "Owned")
		return
	end

	local sheared = PlayerDataHandler.get(player, "SheepShearedCount")
	if (if type(sheared) == "number" then sheared else 0) < info.sheepRequired then
		reply(player, info.id, false, "Locked")
		return
	end

	if not PlayerDataHandler.spend(player, "Wool", info.price) then
		reply(player, info.id, false, "NoWool")
		return
	end

	addOwned(player, info.id)
	setShear(player, info.id)
	reply(player, info.id, true, nil)
end

-- Switches to a shear the player already owns.
local function onEquipShear(player: Player, id: any)
	local info = ShearData.get(id)
	if not info or not PlayerDataHandler.getData(player) then
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

-- The shear the player has equipped (its stats).
function shearShopHandler.getShear(player: Player): ShearData.ShearInfo
	return ShearData.get(getShearId(player)) or ShearData.Shears[1]
end

-- The equipped shear's Tool if the character is holding it out, else nil.
function shearShopHandler.getHeldTool(player: Player): Tool?
	local character = player.Character
	local tool = character and character:FindFirstChild(getShearId(player))
	return if tool and tool:IsA("Tool") then tool else nil
end

-- The equipped shear's Tool wherever it is (held out or in the Backpack), else nil.
function shearShopHandler.getTool(player: Player): Tool?
	local currentId = getShearId(player)
	for _, tool in getShearTools(player) do
		if tool.Name == currentId then
			return tool
		end
	end
	return nil
end

-- Bumps the equipped shear's "Snips" attribute on every hit; clients watch it to play snip effects for everyone.
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
	local data = PlayerDataHandler.waitForData(player)
	if not data then
		return
	end

	updateOwnedAttribute(player)
	setShear(player, if isOwned(player, data.ShearId) then data.ShearId else ShearData.DefaultShearId)

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
	end)
end

return shearShopHandler
