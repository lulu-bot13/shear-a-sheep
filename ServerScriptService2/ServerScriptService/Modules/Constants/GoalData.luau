--!strict

--[[
	GoalTracker content: the first-session milestone chain (in order), then the Gem-paying session quests (3 per session).
	Location: ServerScriptService.Modules.Constants.GoalData
]]--

--[[
	Milestone kinds (GoalHandler works out progress from the save, so players past one skip it on load):
	Stat = data[stat] reaches target; Upgrades = upgrade levels bought; Found = `sheep` found in the Index (any variant);
	Shear = owns shear `shear` (progress: sheep sheared towards its sheepRequired); Equip = holding the shears; IndexClaim = any entry claimed.
	`prestigeDone` = already done for anyone who has Prestiged (their Rebirths / upgrades were reset).
]]
export type Milestone = {
	id: string,
	title: string,
	kind: string,
	target: number,
	stat: string?,
	sheep: string?,
	shear: string?,
	prestigeDone: boolean?,
	gems: number,
}

--[[
	Quest kinds: Shear = sheep shorn bare this quest that match `rarities` / `variant` / `size` / `mutated` (none set = any sheep);
	Upgrades = upgrade levels bought since the quest started.
]]
export type Quest = {
	id: string,
	title: string,
	kind: string,
	target: number,
	gems: number,
	rarities: { [string]: boolean }?,
	variant: string?,
	size: string?,
	mutated: boolean?,
}

local goalData = {}

goalData.Milestones = {
	{ id = "EquipShears", title = "Equip your Shears", kind = "Equip", target = 1, gems = 0 },
	{ id = "Shear10", title = "Shear 10 Sheep", kind = "Stat", stat = "SheepShearedCount", target = 10, gems = 0 },
	{ id = "FirstUpgrade", title = "Buy an Upgrade", kind = "Upgrades", target = 1, prestigeDone = true, gems = 0 },
	{ id = "FindFluffy", title = "Find the Fluffy Sheep", kind = "Found", sheep = "Fluffy", target = 1, gems = 1 },
	{ id = "FirstRebirth", title = "Rebirth for the first time", kind = "Stat", stat = "Rebirths", target = 1, prestigeDone = true, gems = 2 },
	{ id = "SteelShears", title = "Get the Steel Shears", kind = "Shear", shear = "SteelShears", target = 1, gems = 2 },
	{ id = "ClaimIndex", title = "Claim a reward in the Index", kind = "IndexClaim", target = 1, gems = 1 },
	{ id = "SpawnLuck", title = "Buy Spawn Luck", kind = "Stat", stat = "SpawnLuckLevel", target = 1, prestigeDone = true, gems = 1 },
	{ id = "Shear100", title = "Shear 100 Sheep", kind = "Stat", stat = "SheepShearedCount", target = 100, gems = 2 },
	{ id = "FindGolden", title = "Find the Golden Sheep", kind = "Found", sheep = "Golden", target = 1, gems = 3 },
	{ id = "Rebirth3", title = "Reach Rebirth 3", kind = "Stat", stat = "Rebirths", target = 3, prestigeDone = true, gems = 3 },
} :: { Milestone }

local RARE_PLUS = { Rare = true, Epic = true, Legendary = true, Mythic = true }
local EPIC_PLUS = { Epic = true, Legendary = true, Mythic = true }

-- Gems: a sheep shorn bare drops 1 Gem 1 time in 40, and an Ability Shack roll costs 4, so each quest is worth ~1 roll.
goalData.Quests = {
	{ id = "Shear150", title = "Shear 150 Sheep", kind = "Shear", target = 150, gems = 5 },
	{ id = "ShearRare", title = "Shear 8 Rare+ Sheep", kind = "Shear", rarities = RARE_PLUS, target = 8, gems = 4 },
	{ id = "ShearEpic", title = "Shear 2 Epic+ Sheep", kind = "Shear", rarities = EPIC_PLUS, target = 2, gems = 5 },
	{ id = "ShearGiant", title = "Shear 10 Giant Sheep", kind = "Shear", variant = "Giant", target = 10, gems = 4 },
	{ id = "ShearHuge", title = "Shear 3 Huge Sheep", kind = "Shear", size = "Huge", target = 3, gems = 4 },
	{ id = "ShearMutated", title = "Shear 3 Mutated Sheep", kind = "Shear", mutated = true, target = 3, gems = 5 },
	{ id = "BuyUpgrades", title = "Buy 5 Upgrade levels", kind = "Upgrades", target = 5, gems = 3 },
} :: { Quest }

goalData.QUESTS_PER_SESSION = 3

-- Data keys of every upgrade's level ("Upgrades" kinds add these; Capacity counts MaxSheep above FarmData.StartingMaxSheep).
goalData.UpgradeLevelKeys = { "MoreWoolLevel", "SpeedLevel", "DamageLevel", "RespawnLevel", "SpawnLuckLevel", "SizeLevel" }

function goalData.getQuest(id: any): Quest?
	for _, quest in goalData.Quests do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

return goalData
