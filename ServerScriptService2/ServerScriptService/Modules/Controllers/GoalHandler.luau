--!strict

--[[
	GoalTracker: one objective at a time. First the GoalData milestone chain (worked out from the save, so returning players skip
	what they've done), then 3 Gem-paying session quests. Progress is server-side and pushed to GoalClient with GoalState.

	Location: ServerScriptService.Modules.Controllers.GoalHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local GoalData = require(script.Parent.Parent.Constants.GoalData)
local MutationData = require(script.Parent.Parent.Constants.MutationData)
local ShearData = require(script.Parent.Parent.Constants.ShearData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local Analytics = require(script.Parent.Analytics)
local GemHandler = require(script.Parent.GemHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local RebirthHandler = require(script.Parent.RebirthHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local ShearShopHandler = require(script.Parent.ShearShopHandler)

--// Configs
local STEP_KEY = "GoalStep"
local QUESTS_KEY = "GoalQuests"
local STATE_REQUEST_COOLDOWN = 1
-- Data changes that can move a milestone along.
local WATCHED_KEYS = { SheepShearedCount = true, Rebirths = true, Prestiges = true, SheepIndex = true, OwnedShears = true, MaxSheep = true,
	RebirthPitySpawns = true }
for _, key in GoalData.UpgradeLevelKeys do
	WATCHED_KEYS[key] = true
end

type QuestState = { ids: { string }, index: number, progress: number, start: number? }

-- What GoalClient shows; `hidden` when there's nothing to do.
export type GoalState = {
	hidden: boolean,
	id: string?,
	header: string?,
	title: string?,
	progress: number,
	target: number,
	note: string?, -- replaces the "4 / 10" text (the rebirth sheep's pity countdown)
}

--// State
local lastSent: { [Player]: string } = {}
local random = Random.new()

local GoalHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getUpgradeLevels(player: Player): number
	local total = math.max(getNumber(player, "MaxSheep") - FarmData.StartingMaxSheep, 0)
	for _, key in GoalData.UpgradeLevelKeys do
		total += getNumber(player, key)
	end
	return total
end

local function ownsShear(player: Player, shearId: string): boolean
	local owned = PlayerDataHandler.get(player, "OwnedShears")
	return type(owned) == "table" and table.find(owned, shearId) ~= nil
end

local function getShearRequirement(shearId: string): number
	local shear = ShearData.get(shearId)
	return if shear then shear.sheepRequired else 1
end

-- Progress towards a milestone, whether it's done, and the number the bar fills to (a Shear milestone counts sheep sheared).
local function getMilestoneProgress(player: Player, milestone: GoalData.Milestone): (number, boolean, number)
	if milestone.prestigeDone and getNumber(player, "Prestiges") > 0 then
		return milestone.target, true, milestone.target
	end

	local kind = milestone.kind
	local progress = 0
	if kind == "Stat" and milestone.stat then
		progress = getNumber(player, milestone.stat)
	elseif kind == "Upgrades" then
		progress = getUpgradeLevels(player)
	elseif kind == "Found" and milestone.sheep then
		local index = PlayerDataHandler.get(player, "SheepIndex")
		progress = if type(index) == "table" and RebirthHandler.isSheepFound(index, milestone.sheep) then 1 else 0
	elseif kind == "Shear" and milestone.shear then
		local required = math.max(getShearRequirement(milestone.shear), 1)
		if ownsShear(player, milestone.shear) then
			return required, true, required
		end
		return math.min(getNumber(player, "SheepShearedCount"), required), false, required
	elseif kind == "Equip" then
		progress = if ShearShopHandler.getHeldTool(player) or getNumber(player, "SheepShearedCount") > 0 then 1 else 0
	elseif kind == "IndexClaim" then
		local index = PlayerDataHandler.get(player, "SheepIndex")
		for _, status in (if type(index) == "table" then index else {}) do
			if status == "Claimed" then
				progress = 1
				break
			end
		end
	end
	return math.min(progress, milestone.target), progress >= milestone.target, milestone.target
end

--// Quests ------------------------------------------------------------------------------

local function getQuestState(player: Player): QuestState?
	local saved = PlayerDataHandler.get(player, QUESTS_KEY)
	if type(saved) ~= "table" or type(saved.ids) ~= "table" or type(saved.index) ~= "number" then
		return nil
	end
	return saved :: any
end

local function setQuestState(player: Player, state: QuestState)
	PlayerDataHandler.set(player, QUESTS_KEY, state)
end

local function newQuestSet(): QuestState
	local pool = table.clone(GoalData.Quests)
	local ids = {}
	for _ = 1, math.min(GoalData.QUESTS_PER_SESSION, #pool) do
		local quest = table.remove(pool, random:NextInteger(1, #pool))
		table.insert(ids, quest.id)
	end
	return { ids = ids, index = 1, progress = 0 }
end

local function getCurrentQuest(player: Player): (GoalData.Quest?, QuestState?)
	local state = getQuestState(player)
	local quest = if state then GoalData.getQuest(state.ids[state.index]) else nil
	return quest, state
end

-- A fresh quest starts counting from now (Upgrades kinds remember the level total they started at).
local function startQuest(player: Player, state: QuestState)
	local quest = GoalData.getQuest(state.ids[state.index])
	state.progress = 0
	state.start = if quest and quest.kind == "Upgrades" then getUpgradeLevels(player) else nil
	setQuestState(player, state)
end

local function getQuestProgress(player: Player, quest: GoalData.Quest, state: QuestState): number
	if quest.kind == "Upgrades" then
		return math.max(getUpgradeLevels(player) - (state.start or getUpgradeLevels(player)), 0)
	end
	return state.progress
end

--// State ------------------------------------------------------------------------------

local function isChainDone(player: Player): boolean
	return getNumber(player, STEP_KEY) >= #GoalData.Milestones
end

function GoalHandler.getState(player: Player): GoalState
	local step = getNumber(player, STEP_KEY)
	local milestone = GoalData.Milestones[step + 1]
	if milestone then
		local progress, _, target = getMilestoneProgress(player, milestone)
		-- A shear that's unlocked but not bought yet sends the player to the shop.
		local readyToBuy = milestone.kind == "Shear" and progress >= target
		-- Hunting the rebirth sheep: the bar's text is its pity countdown.
		local required, found, pityLeft = RebirthHandler.getRequirement(player)
		local hunting = milestone.kind == "Found" and required == milestone.sheep and not found
		return {
			hidden = false,
			id = milestone.id,
			header = if milestone.gems > 0 then `NEXT GOAL  +{milestone.gems} Gems` else "NEXT GOAL",
			title = if readyToBuy then `{milestone.title} at the Shear Shop` else milestone.title,
			progress = progress,
			target = target,
			note = if hunting then `Guaranteed in {pityLeft} {if pityLeft == 1 then "spawn" else "spawns"}` else nil,
		}
	end

	local quest, state = getCurrentQuest(player)
	if quest and state then
		return {
			hidden = false,
			id = quest.id,
			header = `QUEST {state.index}/{#state.ids}  +{quest.gems} Gems`,
			title = quest.title,
			progress = math.min(getQuestProgress(player, quest, state), quest.target),
			target = quest.target,
		}
	end
	return { hidden = true, progress = 0, target = 1 }
end

local function pushState(player: Player, force: boolean?)
	if not PlayerDataHandler.getData(player) then
		return
	end
	local state = GoalHandler.getState(player)
	local signature = `{state.hidden}|{state.id}|{math.floor(state.progress * 100)}|{state.header}|{state.title}|{state.note}`
	if force or lastSent[player] ~= signature then
		lastSent[player] = signature
		network.fireClient(network.RemoteEvents.GoalState, player, state)
	end
end

--// Progress ---------------------------------------------------------------------------

-- Pays and moves past every finished milestone, then any finished quest. `live` = it happened now (rewarded and logged).
local function advance(player: Player, live: boolean)
	local step = getNumber(player, STEP_KEY)
	while GoalData.Milestones[step + 1] do
		local milestone = GoalData.Milestones[step + 1]
		local _, done = getMilestoneProgress(player, milestone)
		if not done then
			break
		end
		step += 1
		PlayerDataHandler.set(player, STEP_KEY, step)
		if live then
			if milestone.gems > 0 then
				GemHandler.give(player, milestone.gems)
			end
			Analytics.goalStep(player, step, milestone.id)
		end
	end

	if isChainDone(player) then
		local quest, state = getCurrentQuest(player)
		if quest and state and getQuestProgress(player, quest, state) >= quest.target then
			GemHandler.give(player, quest.gems)
			Analytics.goalQuestCompleted(player, quest.id, quest.gems)
			state.index += 1
			startQuest(player, state)
		end
	end
	pushState(player)
end

-- A sheep this player owned was shorn bare: counts towards a matching Shear quest.
local function onSheared(player: Player, sheep: Model)
	if not isChainDone(player) then
		return
	end
	local quest, state = getCurrentQuest(player)
	if not quest or not state or quest.kind ~= "Shear" then
		return
	end

	local sheepType = sheep:GetAttribute("SheepType")
	local info = if type(sheepType) == "string" then SheepData.Sheep[sheepType] else nil
	if not info then
		return -- bosses don't count
	elseif quest.rarities and not quest.rarities[info.rarity] then
		return
	elseif quest.variant and info.variant ~= quest.variant then
		return
	elseif quest.size and sheep:GetAttribute("SizeTier") ~= quest.size then
		return
	elseif quest.mutated and not MutationData.get(sheep:GetAttribute(MutationData.Attribute)) then
		return
	end

	state.progress += 1
	setQuestState(player, state)
	advance(player, true)
end

-- On load: skips milestones already done and gives a finished (or missing) quest set a fresh one for this session.
local function onLoaded(player: Player)
	local state = getQuestState(player)
	if not state or state.index > #state.ids or not GoalData.getQuest(state.ids[state.index]) then
		local fresh = newQuestSet()
		startQuest(player, fresh)
	end
	advance(player, false)
	pushState(player, true)
end

local function watchCharacter(player: Player, character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and not isChainDone(player) then
			task.defer(advance, player, true)
		end
	end)
end

--// Lifecycle -------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
end

function GoalHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.RequestGoalState, function(player: Player)
		pushState(player, true)
	end, { network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN) })

	PlayerDataHandler.Loaded:Connect(onLoaded)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if WATCHED_KEYS[key] then
			advance(player, true)
		end
	end)
	SheepHandler.Sheared:Connect(onSheared)

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		lastSent[player] = nil
	end)
	for _, player in players:GetPlayers() do
		onPlayerAdded(player)
		if PlayerDataHandler.getData(player) then
			task.spawn(onLoaded, player)
		end
	end
end

return GoalHandler
