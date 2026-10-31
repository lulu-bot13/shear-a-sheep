--!strict

--[[
	The sheep Index: shearing a sheep type bare the first time finds it, and claiming it in the Index UI grants its IndexLuck.
	Claimed Luck is permanent: a Prestige resets Luck back to it. Each card shows the player's own odds.

	Location: ServerScriptService.Modules.Controllers.IndexHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MutationData = require(script.Parent.Parent.Constants.MutationData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Configs
local CLAIM_COOLDOWN = 0.25
local STATE_REQUEST_COOLDOWN = 0.5
local FOUND = "Found"
local CLAIMED = "Claimed"

-- One card in the Index UI.
export type EntryState = {
	id: string, -- SheepData type key (also its model's name in Assets.Models.Sheeps or its Baby/Giant folder)
	name: string,
	rarity: string,
	color: Color3,
	indexLuck: number,
	odds: number, -- N in "1 in N" with the player's Luck, rebirths and Prestiges (Halloween sheep: their Halloween odds)
	status: string, -- "Locked", "Found" or "Claimed"
	halloween: boolean, -- only spawns during Halloween
	variant: string?, -- "Baby" or "Giant"; nil for the adult
}

local IndexHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

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

-- Every sheep type's card: a row of Baby, adult, Giant per type, commonest first.
function IndexHandler.getState(player: Player): { EntryState }
	local index = getIndex(player)
	local luck, rebirths, prestiges = getNumber(player, "Luck"), getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	local halloween = WeatherHandler.isHalloween()
	local state: { EntryState } = {}
	for _, sheepType in SheepData.IndexOrder do
		local info = SheepData.Sheep[sheepType]
		table.insert(state, {
			id = sheepType,
			name = info.name,
			rarity = info.rarity,
			color = info.color,
			indexLuck = SheepData.getIndexLuck(sheepType),
			odds = SheepData.getOdds(sheepType, luck, rebirths, prestiges, nil, halloween) or 1,
			status = index[sheepType] or "Locked",
			halloween = info.halloween == true,
			variant = info.variant,
		})
	end
	return state
end

-- Total Luck from every claimed type; a Prestige keeps this much.
function IndexHandler.getClaimedLuck(player: Player): number
	return SheepData.getClaimedIndexLuck(getIndex(player))
end

-- Marks the type as found the first time the player shears one bare, and shows them the unlock popup with that sheep's weight and mutation.
function IndexHandler.discover(player: Player, sheepType: any, sheep: Model?)
	if type(sheepType) ~= "string" or not SheepData.Sheep[sheepType] or not PlayerDataHandler.getData(player) then
		return
	end
	if getIndex(player)[sheepType] == nil then
		setStatus(player, sheepType, FOUND)
		local info = SheepData.Sheep[sheepType]
		Analytics.sheepDiscovered(player, sheepType, info.rarity)
		local weight = if sheep then sheep:GetAttribute("Weight") else nil
		local mutation = if sheep then MutationData.get(sheep:GetAttribute(MutationData.Attribute)) else nil
		network.fireClient(network.RemoteEvents.SheepUnlocked, player, sheepType, info.name, info.rarity, info.color,
			if type(weight) == "number" then weight else nil,
			if mutation then { name = mutation.id, color = mutation.color, rainbow = mutation.rainbowName == true } else nil)
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
	Analytics.indexClaimed(player, 1, SheepData.getIndexLuck(sheepType))
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
		Analytics.indexClaimed(player, count, luck)
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

	-- Answered with IndexClaimResult under the id "All", plus how many were claimed.
	network.connectEvent(network.RemoteEvents.ClaimAllIndexRewards, function(player: Player)
		local claimed = IndexHandler.claimAll(player)
		network.fireClient(network.RemoteEvents.IndexClaimResult, player, "All", claimed > 0, if claimed > 0 then nil else "NotFound", claimed)
	end, { network.Middleware.RateLimit(CLAIM_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestIndexState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(pushState)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		-- Luck changes every hit, so its odds refresh when the Index is opened instead.
		if key == "SheepIndex" or key == "Rebirths" or key == "Prestiges" then
			pushState(player)
		end
	end)

	for _, player in players:GetPlayers() do
		task.spawn(pushState, player)
	end
end

return IndexHandler
