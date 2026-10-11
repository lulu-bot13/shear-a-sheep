--!strict

--[[
	Everything a rebirth costs and unlocks. Edit TIERS to change what each rebirth gives a player.
	Rows are resolved once at load, so every lookup is a single table read.

	Location: ServerScriptService.Modules.Constants.RebirthData
]]--

local EconomyData = require(script.Parent.EconomyData)

export type Tier = {
	pen: string,
	luck: number,
	cost: number?,
	sellMultiplier: number,
	slots: number,
	spawnPoints: number,
	builds: { string },
}

type TierRow = {
	pen: string?,
	luck: number?,
	cost: number?,
	sellMultiplier: number?,
	slots: number?,
	spawnPoints: number?,
	builds: { string }?,
}

local rebirthData = {}

rebirthData.MAX_REBIRTHS = 20

--[[
	Each row applies from that rebirth count onwards. pen/luck/slots/spawnPoints carry over until a later row changes them,
	builds add up and stay, and cost (to rebirth out of this tier) / sellMultiplier use the formulas below when left out.
	pen is a model name in ReplicatedStorage.Assets.Models.Pens.
]]
local TIERS: { [number]: TierRow } = {
	[0] = { pen = "RustedPen", luck = 1, slots = 2, spawnPoints = 1 },
	[1] = { pen = "WoodenPen", luck = 1.25, slots = 3 },
	[2] = { pen = "MeadowPen", luck = 1.5, slots = 4 },
	[3] = { pen = "FarmlandPen", luck = 2, slots = 5 },
	[4] = {pen = "ForestPen", luck = 2.5, slots = 6 },
	[5] = {pen = "StonePen", luck = 3, spawnPoints = 2 },
	[6] = {pen = "SecurityPen", luck = 3.5, slots = 7 },
	[7] = {pen = "WaterfallPen", luck = 4, slots = 8 },
}

rebirthData.COST_BASE = 300
rebirthData.COST_GROWTH = 2.25
rebirthData.SELL_MULTIPLIER_PER_REBIRTH = 0.5

rebirthData.LUCK_RARITIES = {
	{ name = "Common", minLuck = 0, color = Color3.fromRGB(210, 210, 210) },
	{ name = "Uncommon", minLuck = 1.25, color = Color3.fromRGB(90, 220, 110) },
	{ name = "Rare", minLuck = 1.5, color = Color3.fromRGB(70, 160, 255) },
	{ name = "Epic", minLuck = 2, color = Color3.fromRGB(190, 95, 255) },
	{ name = "Legendary", minLuck = 3, color = Color3.fromRGB(255, 170, 40) },
	{ name = "Mythic", minLuck = 5, color = Color3.fromRGB(255, 55, 90) },
}

rebirthData.PENS_CAP = EconomyData.MAX_PENS
rebirthData.PENS_REQUIRED_BASE = 2
rebirthData.WORKERS_REQUIRED_BASE = 1
rebirthData.MAX_WORKERS_BASE = 2

rebirthData.STARTING_MONEY = 1000

rebirthData.debugMode = true
rebirthData.DEBUG_STARTING_MONEY = 1000000

local resolvedTiers: { [number]: Tier } = {}
local buildUnlockRebirth: { [string]: number } = {}
local slotUnlockRebirth: { [number]: number } = {}
local penNames: { string } = {}

do
	local pen, luck, slots, spawnPoints = "", 1, 1, 1
	local builds: { string } = {}

	for rebirths = 0, rebirthData.MAX_REBIRTHS do
		local row = TIERS[rebirths]
		if row then
			pen = row.pen or pen
			luck = row.luck or luck
			slots = row.slots or slots
			spawnPoints = row.spawnPoints or spawnPoints
			if row.builds then
				for _, build in row.builds do
					table.insert(builds, build)
					buildUnlockRebirth[build] = rebirths
				end
			end
			if row.pen and not table.find(penNames, row.pen) then
				table.insert(penNames, row.pen)
			end
		end

		for slot = 1, slots do
			if not slotUnlockRebirth[slot] then
				slotUnlockRebirth[slot] = rebirths
			end
		end

		local formulaCost = math.floor(rebirthData.COST_BASE * rebirthData.COST_GROWTH ^ rebirths)
		resolvedTiers[rebirths] = table.freeze({
			pen = pen,
			luck = luck,
			cost = if rebirths < rebirthData.MAX_REBIRTHS then (row and row.cost) or formulaCost else nil,
			sellMultiplier = (row and row.sellMultiplier) or 1 + rebirthData.SELL_MULTIPLIER_PER_REBIRTH * rebirths,
			slots = slots,
			spawnPoints = spawnPoints,
			builds = table.freeze(table.clone(builds)),
		})
	end
end

function rebirthData.getTier(rebirths: number): Tier
	return resolvedTiers[math.clamp(rebirths, 0, rebirthData.MAX_REBIRTHS)]
end

-- Every pen model name used by a tier, in unlock order.
function rebirthData.getPenNames(): { string }
	return table.clone(penNames)
end

function rebirthData.getStartingMoney(): number
	return if rebirthData.debugMode then rebirthData.DEBUG_STARTING_MONEY else rebirthData.STARTING_MONEY
end

-- Money needed for the next rebirth; nil once the player has reached the maximum.
function rebirthData.getMoneyCost(rebirths: number): number?
	return rebirthData.getTier(rebirths).cost
end

function rebirthData.getMultiplier(rebirths: number): number
	return rebirthData.getTier(rebirths).sellMultiplier
end

function rebirthData.getSlotLimit(rebirths: number): number
	return rebirthData.getTier(rebirths).slots
end

-- Rebirths a player needs before this slot can be used; nil if no tier ever unlocks it.
function rebirthData.getUnlockRebirth(slotNumber: number): number?
	return slotUnlockRebirth[slotNumber]
end

-- Every build named in TIERS, mapped to whether this many rebirths has unlocked it.
function rebirthData.getBuildStates(rebirths: number): { [string]: boolean }
	local states = {}
	for build, required in buildUnlockRebirth do
		states[build] = rebirths >= required
	end
	return states
end

function rebirthData.getLuckColor(luck: number): Color3
	local color = rebirthData.LUCK_RARITIES[1].color
	for _, rarity in rebirthData.LUCK_RARITIES do
		if luck >= rarity.minLuck then
			color = rarity.color
		end
	end
	return color
end

function rebirthData.getPensRequired(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.PENS_REQUIRED_BASE + rebirths)
end

function rebirthData.getWorkersRequired(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.WORKERS_REQUIRED_BASE + rebirths)
end

function rebirthData.getMaxWorkers(rebirths: number): number
	return math.min(rebirthData.PENS_CAP, rebirthData.MAX_WORKERS_BASE + rebirths)
end

return rebirthData
