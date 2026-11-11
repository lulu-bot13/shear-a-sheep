--!strict

--[[
	Rebirth rules: spend wool, with the tier's sheep found in the Index (SheepPools), for a luck-factor boost; upgrades are kept.
	Also owns the rebirth sheep's pity counter and the RebirthSheepId / RebirthSheepFound / SpawnLuckMaxed / RebirthPity attributes.

	Location: ServerScriptService.Modules.Controllers.RebirthHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local SpawnOdds = require(replicatedStorage.Shared.Utils.SpawnOdds)
local PenStyleData = require(script.Parent.Parent.Constants.PenStyleData)
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local SheepPools = require(script.Parent.Parent.Constants.SheepPools)
local Analytics = require(script.Parent.Analytics)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local LEADERSTATS_WAIT_SECONDS = 15
local PITY_KEY = "RebirthPitySpawns" -- saved: spawns rolled since the hunt for the rebirth sheep (re)started
local FOUND_STATUSES = { Found = true, Claimed = true }
local REQUIREMENT_KEYS = { SheepIndex = true, Rebirths = true, Prestiges = true, SpawnLuckLevel = true, [PITY_KEY] = true }

export type State = {
	rebirths: number,
	prestiges: number,
	maxRebirths: number,
	maxed: boolean,
	wool: number,
	woolCost: number,
	canRebirth: boolean, -- one rebirth: affordable and its sheep found
	luck: number, -- Luck right now
	luckFactor: number, -- the odds multiplier right now
	nextLuckFactor: number, -- the odds multiplier after the next rebirth (same as luckFactor when maxed)

	-- The sheep the next rebirth needs (nil when none) and how close its pity is.
	requiredSheep: string?,
	requiredName: string?,
	requiredRarity: string?,
	requiredColor: Color3?,
	requiredFound: boolean,
	pityLeft: number, -- spawns until it's guaranteed (0 when there's nothing to find)
	needsSheep: boolean, -- the selected amount is blocked by a sheep that isn't found yet

	-- The same, for the amount the screen has selected (woolCost and canRebirth above are always for one rebirth).
	amount: Amount, -- the amount that was asked for
	amountCount: number, -- how many rebirths that amount does right now (0 when "max" can't afford one)
	amountCost: number, -- total wool for amountCount (for one rebirth when amountCount is 0)
	amountCanRebirth: boolean,
	amountLuckFactor: number,
}

export type Amount = number | "max"

--// State
local rebirthing: { [Player]: boolean } = {}
local lastFound: { [Player]: boolean } = {}

local RebirthHandler = {}

RebirthHandler.Rebirthed = Signal.new() -- (player, rebirthsBefore, rebirthsAfter)

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getIndex(player: Player): { [string]: string }
	local index = PlayerDataHandler.get(player, "SheepIndex")
	return if type(index) == "table" then index else {}
end

--// Requirement ---------------------------------------------------------------

-- True once any Index entry of this adult type (its Baby/Giant, or any mutation of them) is Found or Claimed.
function RebirthHandler.isSheepFound(index: { [string]: string }, adultKey: string): boolean
	for key, status in index do
		if FOUND_STATUSES[status] then
			local sheepType = SheepData.parseIndexKey(key)
			local info = sheepType and SheepData.Sheep[sheepType]
			if info and (info.adult or sheepType) == adultKey then
				return true
			end
		end
	end
	return false
end

-- The adult sheep key the player's next rebirth needs (nil = none), whether it's found, spawns left on its pity and the pity's size.
function RebirthHandler.getRequirement(player: Player): (string?, boolean, number, number)
	local required, pity = SheepPools.getRequirement(getNumber(player, "Rebirths"))
	if not required then
		return nil, true, 0, 0
	end
	local found = RebirthHandler.isSheepFound(getIndex(player), required)
	local left = if found then 0 else math.max(pity - getNumber(player, PITY_KEY), 1)
	return required, found, left, pity
end

-- Consecutive rebirths from now (at most `left`) whose sheep are already found.
local function getAllowedSteps(player: Player, rebirths: number, left: number): number
	local index = getIndex(player)
	for step = 0, left - 1 do
		local required = SheepPools.getRequirement(rebirths + step)
		if required and not RebirthHandler.isSheepFound(index, required) then
			return step
		end
	end
	return left
end

--[[
	Counts one spawn roll towards the rebirth sheep's pity. Returns the adult key to force when the pity is due (the count then
	starts over); nil otherwise, or when nothing needs finding.
]]
function RebirthHandler.rollPity(player: Player): string?
	local required, found, _, pity = RebirthHandler.getRequirement(player)
	if not required or found or pity <= 0 then
		return nil
	end
	local spawns = getNumber(player, PITY_KEY) + 1
	if spawns >= pity then
		PlayerDataHandler.set(player, PITY_KEY, 0)
		return required
	end
	PlayerDataHandler.set(player, PITY_KEY, spawns)
	return nil
end

-- The rebirth sheep turned up (rolled or forced): its pity starts over.
function RebirthHandler.noteSpawn(player: Player, sheepType: string)
	local required, found = RebirthHandler.getRequirement(player)
	local info = SheepData.Sheep[sheepType]
	if required and not found and info and (info.adult or sheepType) == required and getNumber(player, PITY_KEY) ~= 0 then
		PlayerDataHandler.set(player, PITY_KEY, 0)
	end
end

--// Public API ------------------------------------------------------------------

function RebirthHandler.getRebirths(player: Player): number
	return getNumber(player, "Rebirths")
end

-- A whole number from 1 to MAX_REBIRTHS, or "max"; anything else the client sends counts as 1.
function RebirthHandler.parseAmount(value: any): Amount
	if value == "max" then
		return "max"
	elseif type(value) == "number" and value % 1 == 0 and value >= 1 and value <= RebirthData.MAX_REBIRTHS then
		return value
	end
	return 1
end

-- Everything the client needs to draw the rebirth screen for this player, with `amount` rebirths selected.
function RebirthHandler.getState(player: Player, amount: Amount?): State
	local rebirths = RebirthHandler.getRebirths(player)
	local prestiges = getNumber(player, "Prestiges")
	local spawnLuck = getNumber(player, "SpawnLuckLevel")
	local woolCost = RebirthData.getWoolCost(rebirths)
	local wool = getNumber(player, "Wool")
	local luck = getNumber(player, "Luck")
	local required, found, pityLeft = RebirthHandler.getRequirement(player)
	local requiredInfo = if required then SheepData.Sheep[required] else nil

	local selected = RebirthHandler.parseAmount(amount)
	local rebirthsLeft = RebirthData.MAX_REBIRTHS - rebirths
	local allowed = getAllowedSteps(player, rebirths, rebirthsLeft)
	local amountCount, amountCost
	if selected == "max" then
		amountCount, amountCost = RebirthData.getMaxAffordable(rebirths, wool)
		if amountCount > allowed then
			amountCount = allowed
			amountCost = RebirthData.getTotalWoolCost(rebirths, allowed) or 0
		end
	else
		amountCount = math.min(selected, rebirthsLeft)
		amountCost = RebirthData.getTotalWoolCost(rebirths, amountCount) or 0
	end
	local needsSheep = rebirthsLeft > 0 and allowed < math.max(amountCount, 1)
	-- "max" with nothing affordable still previews one rebirth, so the bar and AFTER have something to show.
	local previewCount = if amountCount == 0 and rebirthsLeft > 0 then 1 else amountCount
	if amountCount == 0 then
		amountCost = woolCost or 0
	end

	return {
		rebirths = rebirths,
		prestiges = prestiges,
		maxRebirths = RebirthData.MAX_REBIRTHS,
		maxed = woolCost == nil,
		wool = wool,
		woolCost = woolCost or 0,
		canRebirth = woolCost ~= nil and wool >= woolCost and found,
		luck = luck,
		luckFactor = SheepData.getLuckFactor(luck, rebirths, prestiges, nil, spawnLuck),
		nextLuckFactor = SheepData.getLuckFactor(luck, rebirths + 1, prestiges, nil, spawnLuck),

		requiredSheep = required,
		requiredName = if requiredInfo then requiredInfo.name else nil,
		requiredRarity = if requiredInfo then requiredInfo.rarity else nil,
		requiredColor = if requiredInfo then requiredInfo.color else nil,
		requiredFound = found,
		pityLeft = pityLeft,
		needsSheep = needsSheep,

		amount = selected,
		amountCount = amountCount,
		amountCost = amountCost,
		amountCanRebirth = amountCount > 0 and wool >= amountCost and not needsSheep,
		amountLuckFactor = SheepData.getLuckFactor(luck, rebirths + previewCount, prestiges, nil, spawnLuck),
	}
end

--[[
	Tries to rebirth the player `amount` times at once (clamped to the rebirths left). Returns true and the number done on
	success, or false plus a reason the client can show ("Busy", "MaxRebirths", "NeedSheep" or "NotReady").
	A fixed amount is all or nothing. Everything is checked here, on the server.
	`free` (the Skip Rebirth product and its saved credits) does exactly one rebirth without the wool cost; the sheep is still needed.
]]
function RebirthHandler.rebirth(player: Player, amount: Amount?, free: boolean?): (boolean, string?, number?)
	if rebirthing[player] or not PlayerDataHandler.getData(player) then
		return false, "Busy", nil
	end

	local state = RebirthHandler.getState(player, if free then 1 else amount)
	if state.maxed then
		return false, "MaxRebirths", nil
	end
	if state.needsSheep then
		return false, "NeedSheep", nil
	end
	if not free and not state.amountCanRebirth then
		return false, "NotReady", nil
	end
	local cost = if free then 0 else state.amountCost

	rebirthing[player] = true

	-- The rebirths are counted first, so a problem while paying can never cost the player wool for nothing.
	PlayerDataHandler.set(player, PITY_KEY, 0)
	PlayerDataHandler.set(player, "Rebirths", state.rebirths + state.amountCount)

	local success, err = pcall(function()
		if cost > 0 then
			PlayerDataHandler.set(player, "Wool", getNumber(player, "Wool") - cost)
		end
	end)
	if not success then
		warn(`RebirthHandler: taking {player.Name}'s rebirth cost failed: {err}`)
	end

	rebirthing[player] = nil
	AnnouncementHandler.rebirth(player, state.rebirths, state.rebirths + state.amountCount)
	local penBefore = PenStyleData.getTier(state.rebirths, state.prestiges)
	local penAfter = PenStyleData.getTier(state.rebirths + state.amountCount, state.prestiges)
	if penAfter > penBefore then
		AnnouncementHandler.penUnlocked(player, PenStyleData.Tiers[penAfter].name)
	end
	Analytics.rebirthed(player, state.rebirths + state.amountCount, state.amountCount, cost)
	RebirthHandler.Rebirthed:Fire(player, state.rebirths, state.rebirths + state.amountCount)
	return true, nil, state.amountCount
end

--// Attributes ------------------------------------------------------------------

-- Saved Skip Rebirths wait for the sheep; once it's found they're spent here.
local function useFreeRebirths(player: Player)
	while player.Parent and getNumber(player, "FreeRebirths") > 0 do
		if not RebirthHandler.rebirth(player, 1, true) then
			return
		end
		PlayerDataHandler.increment(player, "FreeRebirths", -1)
		network.fireClient(network.RemoteEvents.RebirthResult, player, true, nil, RebirthHandler.getRebirths(player), 1)
	end
end

local function updateAttributes(player: Player)
	if not PlayerDataHandler.getData(player) then
		return
	end
	local required, found, pityLeft = RebirthHandler.getRequirement(player)
	local cap = SpawnOdds.getSpawnLuckCap(RebirthHandler.getRebirths(player))
	player:SetAttribute("RebirthSheepId", required or "")
	player:SetAttribute("RebirthSheepFound", found)
	player:SetAttribute("RebirthPity", pityLeft)
	player:SetAttribute("SpawnLuckMaxed", getNumber(player, "SpawnLuckLevel") >= cap)

	if found and lastFound[player] == false and getNumber(player, "FreeRebirths") > 0 then
		task.defer(useFreeRebirths, player)
	end
	lastFound[player] = found
end

--// Lifecycle ---------------------------------------------------------------------

-- Mirrors Rebirths as a leaderstat once the leaderstats folder exists.
local function onPlayerAdded(player: Player)
	if not PlayerDataHandler.waitForData(player) then
		return
	end
	updateAttributes(player)

	local leaderstats = player:WaitForChild("leaderstats", LEADERSTATS_WAIT_SECONDS)
	if not leaderstats then
		return
	end

	local display = Instance.new("IntValue")
	display.Name = "Rebirths"
	display.Value = RebirthHandler.getRebirths(player)
	display.Parent = leaderstats

	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		display.Value = RebirthHandler.getRebirths(player)
	end)
end

function RebirthHandler.Setup()
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		rebirthing[player] = nil
		lastFound[player] = nil
	end)

	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if REQUIREMENT_KEYS[key] then
			updateAttributes(player)
		end
	end)

	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RebirthHandler
