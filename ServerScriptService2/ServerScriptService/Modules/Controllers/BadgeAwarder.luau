--!strict

--[[
	Badges: awards each badge at most once per session (owned ones are skipped, ids still 0 are ignored), on load or when a tracked numeric stat
	goes up past a milestone. Badge info is cached, and the player gets a toast for every badge newly awarded.

	Location: ServerScriptService.Modules.Controllers.BadgeAwarder
]]--

--// Services
local badgeService = game:GetService("BadgeService")
local players = game:GetService("Players")

--// Modules
local Wiring = require(script.Parent.MonetizationWiring)

export type Badge = {
	alertText: string,
	reward: { badge: number }, -- 0 = not set up yet
}

-- Awarded once the stat reaches `amount` (amount 1 = "the first X").
export type Milestone = Badge & { amount: number }

--// State
local store, notify = Wiring.store, Wiring.notify
local badgeInfoCache: { [number]: any } = {}
local ownedBadges: { [Player]: { [number]: boolean } } = {} -- owned or awarded this session
local checking: { [Player]: { [number]: boolean } } = {} -- badges with a check or award in flight
local lastValues: { [Player]: { [string]: number } } = {}
local loadBadges: { Badge } = {}
local trackedStats: { [string]: { Milestone } } = {}

local BadgeAwarder = {}

function BadgeAwarder:_awardBadge(player: Player, badgeId: number): boolean
	-- Fetch badge information (cached)
	local badgeInfo = badgeInfoCache[badgeId]
	if not badgeInfo then
		local success, result = pcall(function()
			return badgeService:GetBadgeInfoAsync(badgeId)
		end)
		if not success then
			warn("Error while fetching badge info: " .. tostring(result))
			return false
		end
		badgeInfo = result
		badgeInfoCache[badgeId] = badgeInfo
	end

	-- Confirm that badge can be awarded
	if not badgeInfo.IsEnabled then
		return false
	end

	-- Award badge
	local awarded, errorMessage = pcall(badgeService.AwardBadgeAsync, badgeService, player.UserId, badgeId)
	if not awarded then
		warn("Error while awarding badge:", errorMessage)
	end
	return awarded
end

function BadgeAwarder:_HasBadge(player: Player, badgeId: number): boolean
	local success, hasBadge = pcall(function()
		return badgeService:UserHasBadgeAsync(player.UserId, badgeId)
	end)

	if not success then
		warn("Error while checking if player has badge!")
		return false
	end

	return hasBadge
end

-- Awards a badge once: skipped for id 0, anything owned or already awarded this session, or a check already running.
function BadgeAwarder.award(player: Player, badgeId: number, alertText: string)
	local owned, inFlight = ownedBadges[player], checking[player]
	if badgeId == 0 or not owned or not inFlight or owned[badgeId] or inFlight[badgeId] then
		return
	end
	inFlight[badgeId] = true

	task.spawn(function()
		if BadgeAwarder:_HasBadge(player, badgeId) then
			owned[badgeId] = true
		elseif player.Parent and BadgeAwarder:_awardBadge(player, badgeId) then
			owned[badgeId] = true
			notify(player, `Badge unlocked: {alertText}!`, "success")
		end
		inFlight[badgeId] = nil
	end)
end

function BadgeAwarder.checkMilestones(player: Player, milestones: { Milestone }, value: number)
	for _, milestone in milestones do
		if value >= milestone.amount then
			BadgeAwarder.award(player, milestone.reward.badge, milestone.alertText)
		end
	end
end

-- Awarded to everyone once their data loads (e.g. a Welcome badge).
function BadgeAwarder.awardOnLoad(badge: Badge)
	table.insert(loadBadges, badge)
end

-- Checked against the save's number `statKey` on load (so earlier progress counts) and whenever it goes up (not when it's reset down).
function BadgeAwarder.trackStat(statKey: string, milestones: { Milestone })
	trackedStats[statKey] = milestones
end

--// Lifecycle ---------------------------------------------------------------------

local function onLoaded(player: Player)
	ownedBadges[player] = ownedBadges[player] or {}
	checking[player] = checking[player] or {}
	lastValues[player] = {}

	for _, badge in loadBadges do
		BadgeAwarder.award(player, badge.reward.badge, badge.alertText)
	end
	for statKey, milestones in trackedStats do
		local value = store.get(player, statKey)
		if type(value) == "number" then
			lastValues[player][statKey] = value
			BadgeAwarder.checkMilestones(player, milestones, value)
		end
	end
end

-- Registrations come from other modules' Setup, so these hooks start here.
function BadgeAwarder.Start()
	store.onLoaded(onLoaded)
	store.onChanged(function(player: Player, key: string, value: any)
		local last = lastValues[player]
		local milestones = trackedStats[key]
		if not last or not milestones or type(value) ~= "number" then
			return
		end
		local previous = last[key]
		last[key] = value
		if previous == nil or value > previous then
			BadgeAwarder.checkMilestones(player, milestones, value)
		end
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		ownedBadges[player] = nil
		checking[player] = nil
		lastValues[player] = nil
	end)
	for _, player in players:GetPlayers() do
		if store.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
end

return BadgeAwarder
