--!strict

--[[
	The sheep Index: shearing a sheep type bare the first time finds it, and claiming it in the Index UI grants its IndexLuck.
	Claimed Luck is permanent: rebirths add it back on top of their own Luck.

	Location: ServerScriptService.Modules.Controllers.IndexHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local CLAIM_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local FOUND = "Found"
local CLAIMED = "Claimed"

-- One card in the Index UI.
export type EntryState = {
	id: string, -- SheepData type key (also the model name in Assets.Models.Sheeps)
	name: string,
	rarity: string,
	color: Color3,
	indexLuck: number,
	odds: number, -- N in "1 in N" at base Luck
	status: string, -- "Locked", "Found" or "Claimed"
	tier: string, -- the Index tab it's listed under: "Baby" or "Normal"
}

local IndexHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getIndex(player: Player): { [string]: string }
	local index = PlayerDataHandler.get(player, "SheepIndex")
	return if type(index) == "table" then index else {}
end

local function setStatus(player: Player, sheepType: string, status: string)
	local index = table.clone(getIndex(player))
	index[sheepType] = status
	PlayerDataHandler.set(player, "SheepIndex", index)
end

--// Public API ------------------------------------------------------------------------

-- Every sheep type's card, commonest first.
function IndexHandler.getState(player: Player): { EntryState }
	local index = getIndex(player)
	local state: { EntryState } = {}
	for _, sheepType in SheepData.IndexOrder do
		local info = SheepData.Sheep[sheepType]
		table.insert(state, {
			id = sheepType,
			name = info.name,
			rarity = info.rarity,
			color = info.color,
			indexLuck = SheepData.getIndexLuck(sheepType),
			odds = SheepData.getOdds(sheepType, 0) or 1,
			status = index[sheepType] or "Locked",
			tier = if info.baby then "Baby" else "Normal",
		})
	end
	return state
end

-- Total Luck from every claimed type; rebirths keep this much on top of their own.
function IndexHandler.getClaimedLuck(player: Player): number
	return SheepData.getClaimedIndexLuck(getIndex(player))
end

-- Marks the type as found the first time the player shears one bare, and shows them the unlock popup.
function IndexHandler.discover(player: Player, sheepType: any)
	if type(sheepType) ~= "string" or not SheepData.Sheep[sheepType] or not PlayerDataHandler.getData(player) then
		return
	end
	if getIndex(player)[sheepType] == nil then
		setStatus(player, sheepType, FOUND)
		local info = SheepData.Sheep[sheepType]
		network.fireClient(network.RemoteEvents.SheepUnlocked, player, sheepType, info.name, info.rarity, info.color)
	end
end

--[[
	Claims a found type's IndexLuck. Returns true on success, or false plus a reason
	("NotLoaded", "Unknown", "NotFound" or "Claimed").
]]
function IndexHandler.claim(player: Player, sheepType: any): (boolean, string?)
	if not PlayerDataHandler.getData(player) then
		return false, "NotLoaded"
	end
	if type(sheepType) ~= "string" or not SheepData.Sheep[sheepType] then
		return false, "Unknown"
	end

	local status = getIndex(player)[sheepType]
	if status == CLAIMED then
		return false, "Claimed"
	elseif status ~= FOUND then
		return false, "NotFound"
	end

	setStatus(player, sheepType, CLAIMED)
	PlayerDataHandler.increment(player, "Luck", SheepData.getIndexLuck(sheepType))
	return true, nil
end

-- Claims every found type at once. Returns how many were claimed (0 if none were ready).
function IndexHandler.claimAll(player: Player): number
	if not PlayerDataHandler.getData(player) then
		return 0
	end

	local index = table.clone(getIndex(player))
	local count, luck = 0, 0
	for sheepType, status in index do
		if status == FOUND and SheepData.Sheep[sheepType] then
			index[sheepType] = CLAIMED
			count += 1
			luck += SheepData.getIndexLuck(sheepType)
		end
	end

	if count > 0 then
		PlayerDataHandler.set(player, "SheepIndex", index)
		PlayerDataHandler.increment(player, "Luck", luck)
	end
	return count
end

--// Lifecycle ---------------------------------------------------------------------

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.IndexState, player, IndexHandler.getState(player))
	end
end

function IndexHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.ClaimIndexReward, function(player: Player, sheepType: any)
		local success, reason = IndexHandler.claim(player, sheepType)
		network.fireClient(network.RemoteEvents.IndexClaimResult, player, sheepType, success, reason)
	end, { network.Middleware.RateLimit(CLAIM_COOLDOWN) })

	-- Answered with IndexClaimResult under the id "All".
	network.connectEvent(network.RemoteEvents.ClaimAllIndexRewards, function(player: Player)
		local claimed = IndexHandler.claimAll(player)
		network.fireClient(network.RemoteEvents.IndexClaimResult, player, "All", claimed > 0, if claimed > 0 then nil else "NotFound")
	end, { network.Middleware.RateLimit(CLAIM_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestIndexState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(pushState)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "SheepIndex" then
			pushState(player)
		end
	end)

	for _, player in players:GetPlayers() do
		task.spawn(pushState, player)
	end
end

return IndexHandler
