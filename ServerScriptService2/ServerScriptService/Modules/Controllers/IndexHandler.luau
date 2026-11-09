--!strict

--[[
	The sheep Index: a page for Normal and for every mutation; shearing a sheep bare the first time finds its entry on its own page.
	Claiming an entry grants its IndexLuck (times the mutation's luck); claimed Luck is permanent, so a Prestige resets Luck back to it.

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
local NORMAL_PAGE = "Normal" -- the unmutated page (so no MutationData id may be "Normal")

-- One card in the Index UI.
export type EntryState = {
	id: string, -- SheepData type key (also its model's name in Assets.Models.Sheeps or its Baby/Giant folder)
	key: string, -- its SheepIndex key (SheepData.getIndexKey); what the client claims with
	mutation: string, -- the page it's on: "Normal" or a MutationData id
	name: string,
	rarity: string,
	color: Color3,
	indexLuck: number, -- claim reward, mutation multiplier included
	odds: number, -- N in "1 in N" with the player's Luck, rebirths and Prestiges, mutation chance included (Halloween sheep: their Halloween odds)
	status: string, -- "Locked", "Found" or "Claimed"
	halloween: boolean, -- only spawns during Halloween
	variant: string?, -- "Baby" or "Giant"; nil for the adult
}

-- One tab of the Index, sent with every IndexState so the client builds its tabs from MutationData.
export type PageInfo = {
	id: string, -- "Normal" or a MutationData id
	color: Color3,
	rainbow: boolean, -- its name cycles through the rainbow
}

local IndexHandler = {}

-- Normal first, then every mutation in MutationData order (rarest first).
local pages: { PageInfo } = { { id = NORMAL_PAGE, color = Color3.new(1, 1, 1), rainbow = false } }
for _, mutation in MutationData.Mutations do
	table.insert(pages, { id = mutation.id, color = mutation.color, rainbow = mutation.rainbowName == true })
end

--// Helpers ---------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getIndex(player: Player): { [string]: string }
	local index = PlayerDataHandler.get(player, "SheepIndex")
	return if type(index) == "table" then index else {}
end

local function setStatus(player: Player, key: string, status: string)
	local index = table.clone(getIndex(player))
	index[key] = status
	PlayerDataHandler.set(player, "SheepIndex", index)
end

--// Public API ------------------------------------------------------------------------

function IndexHandler.getPages(): { PageInfo }
	return pages
end

-- Every page's cards in tab order; each page has a row of Baby, adult, Giant per type, commonest first.
function IndexHandler.getState(player: Player): { EntryState }
	local index = getIndex(player)
	local luck, rebirths, prestiges = getNumber(player, "Luck"), getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	local halloween = WeatherHandler.isHalloween()

	local baseOdds: { [string]: number } = {}
	for _, sheepType in SheepData.IndexOrder do
		baseOdds[sheepType] = SheepData.getOdds(sheepType, luck, rebirths, prestiges, nil, halloween) or 1
	end

	local state: { EntryState } = {}
	for _, page in pages do
		local mutation = MutationData.get(page.id)
		local mutationId = if mutation then mutation.id else nil
		local mutationOdds = if mutation then MutationData.getOdds(mutation.id) or 1 else 1
		for _, sheepType in SheepData.IndexOrder do
			local info = SheepData.Sheep[sheepType]
			local key = SheepData.getIndexKey(sheepType, mutationId)
			table.insert(state, {
				id = sheepType,
				key = key,
				mutation = page.id,
				name = info.name,
				rarity = info.rarity,
				color = info.color,
				indexLuck = SheepData.getIndexEntryLuck(key),
				odds = math.max(1, math.floor(baseOdds[sheepType] * mutationOdds + 0.5)),
				status = index[key] or "Locked",
				halloween = info.halloween == true,
				variant = info.variant,
			})
		end
	end
	return state
end

-- Total Luck from every claimed entry; a Prestige keeps this much.
function IndexHandler.getClaimedLuck(player: Player): number
	return SheepData.getClaimedIndexLuck(getIndex(player))
end

--[[
	Marks the sheep's entry as found the first time the player shears one bare: a mutated sheep only finds its mutation's
	entry, a plain one the Normal entry. Shows them the unlock popup with that sheep's weight and mutation.
]]
function IndexHandler.discover(player: Player, sheepType: any, sheep: Model?)
	if type(sheepType) ~= "string" or not SheepData.Sheep[sheepType] or not PlayerDataHandler.getData(player) then
		return
	end

	local mutation = if sheep then MutationData.get(sheep:GetAttribute(MutationData.Attribute)) else nil
	local key = SheepData.getIndexKey(sheepType, if mutation then mutation.id else nil)
	if getIndex(player)[key] ~= nil then
		return
	end

	setStatus(player, key, FOUND)
	local info = SheepData.Sheep[sheepType]
	Analytics.sheepDiscovered(player, key, info.rarity)
	local weight = if sheep then sheep:GetAttribute("Weight") else nil
	network.fireClient(network.RemoteEvents.SheepUnlocked, player, sheepType, info.name, info.rarity, info.color,
		if type(weight) == "number" then weight else nil,
		if mutation then { name = mutation.id, color = mutation.color, rainbow = mutation.rainbowName == true } else nil)
end

--[[
	Claims a found entry's Luck by its Index key. Returns true on success, or false plus a reason
	("NotLoaded", "Unknown", "NotFound" or "Claimed").
]]
function IndexHandler.claim(player: Player, key: any): (boolean, string?)
	if not PlayerDataHandler.getData(player) then
		return false, "NotLoaded"
	end
	if not SheepData.parseIndexKey(key) then
		return false, "Unknown"
	end

	local status = getIndex(player)[key]
	if status == CLAIMED then
		return false, "Claimed"
	elseif status ~= FOUND then
		return false, "NotFound"
	end

	local luck = SheepData.getIndexEntryLuck(key)
	setStatus(player, key, CLAIMED)
	PlayerDataHandler.increment(player, "Luck", luck)
	Analytics.indexClaimed(player, 1, luck)
	return true, nil
end

-- Claims every found entry on every page at once. Returns how many were claimed (0 if none were ready).
function IndexHandler.claimAll(player: Player): number
	if not PlayerDataHandler.getData(player) then
		return 0
	end

	local index = table.clone(getIndex(player))
	local count, luck = 0, 0
	for key, status in index do
		if status == FOUND and SheepData.parseIndexKey(key) then
			index[key] = CLAIMED
			count += 1
			luck += SheepData.getIndexEntryLuck(key)
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

-- Every page at once (with the tab list), so switching tabs never waits on the server or its rate limit.
local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.IndexState, player, IndexHandler.getState(player), pages)
	end
end

function IndexHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.ClaimIndexReward, function(player: Player, key: any)
		local success, reason = IndexHandler.claim(player, key)
		network.fireClient(network.RemoteEvents.IndexClaimResult, player, key, success, reason)
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
