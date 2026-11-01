--!strict

--[[
	Daily rewards: one claim every 20 hours on a 7-day loop, starting over at day 1 after 48 hours without claiming.
	Every check uses the server's os.time(); amounts and timings live in DailyRewardData.

	Location: ServerScriptService.Modules.Controllers.DailyRewardHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local DailyRewardData = require(script.Parent.Parent.Constants.DailyRewardData)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local CLAIM_COOLDOWN = 1
local STATE_REQUEST_COOLDOWN = 0.5
-- Data keys whose change moves the cards, the timer or the reward amounts.
local STATE_KEYS = { DailyStreak = true, DailyLastClaim = true, DailyCycles = true, Rebirths = true, Prestiges = true }
local DAILY_KEYS = { "DailyStreak", "DailyLastClaim", "DailyCycles" }

export type State = {
	streak: number, -- days claimed in the current streak (0 once it has been broken)
	today: number, -- the card claimed next, 1 to DAY_COUNT
	claimable: boolean,
	secondsLeft: number, -- until the next claim opens; 0 while claimable
	cycles: number,
	rewards: { DailyRewardData.Reward }, -- every card's reward for the player's progress right now
}

--// State
local pushQueued: { [Player]: boolean } = {}

local DailyRewardHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

-- The streak after any reset for being away too long, whether a claim is open, and the seconds until one is.
local function getStatus(player: Player, now: number): (number, boolean, number)
	local lastClaim = getNumber(player, "DailyLastClaim")
	if lastClaim <= 0 then
		return 0, true, 0
	end

	-- A last claim in the future (e.g. set by hand) counts as just now.
	local elapsed = math.max(now - lastClaim, 0)
	local streak = if elapsed >= DailyRewardData.STREAK_RESET_SECONDS then 0 else getNumber(player, "DailyStreak")
	if elapsed >= DailyRewardData.CLAIM_COOLDOWN_SECONDS then
		return streak, true, 0
	end
	return streak, false, DailyRewardData.CLAIM_COOLDOWN_SECONDS - elapsed
end

--// Public API ------------------------------------------------------------------

function DailyRewardHandler.getState(player: Player): State
	local streak, claimable, secondsLeft = getStatus(player, os.time())
	local rebirths, prestiges = getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	local cycles = getNumber(player, "DailyCycles")

	local rewards = table.create(DailyRewardData.DAY_COUNT)
	for day = 1, DailyRewardData.DAY_COUNT do
		rewards[day] = DailyRewardData.getReward(day, rebirths, prestiges, cycles)
	end

	return {
		streak = streak,
		today = streak % DailyRewardData.DAY_COUNT + 1,
		claimable = claimable,
		secondsLeft = secondsLeft,
		cycles = cycles,
		rewards = rewards,
	}
end

--[[
	Claims today's reward. Returns true and the reward given, or false plus a reason the client can show
	("NotLoaded" or "NotReady"). Everything is checked here, on the server.
]]
function DailyRewardHandler.claim(player: Player): (boolean, string?, DailyRewardData.Reward?)
	if not PlayerDataHandler.getData(player) then
		return false, "NotLoaded", nil
	end

	local now = os.time()
	local streak, claimable = getStatus(player, now)
	if not claimable then
		return false, "NotReady", nil
	end

	local day = streak % DailyRewardData.DAY_COUNT + 1
	local cycles = getNumber(player, "DailyCycles")
	local reward = DailyRewardData.getReward(day, getNumber(player, "Rebirths"), getNumber(player, "Prestiges"), cycles)

	-- The claim is saved first, so a problem while granting can never let the same day be claimed twice.
	PlayerDataHandler.set(player, "DailyStreak", streak + 1)
	PlayerDataHandler.set(player, "DailyLastClaim", now)
	if day == DailyRewardData.DAY_COUNT then
		PlayerDataHandler.set(player, "DailyCycles", cycles + 1)
	end

	PlayerDataHandler.increment(player, reward.kind, reward.amount)
	Analytics.dailyRewardClaimed(player, reward.day, reward.kind, reward.amount, streak + 1)
	return true, nil, reward
end

--// Lifecycle ---------------------------------------------------------------------

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.DailyRewardState, player, DailyRewardHandler.getState(player))
	end
end

-- A claim changes several keys at once, so their pushes are folded into one at the end of the frame.
local function queuePush(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		pushState(player)
	end)
end

--[[
	Studio only, for testing the timings: setting one of the daily attributes on the server (e.g. from the command bar,
	which can't reach PlayerDataHandler's loaded saves) writes it into the save. Clients can't change server attributes.
]]
local function watchStudioOverrides(player: Player)
	for _, key in DAILY_KEYS do
		player:GetAttributeChangedSignal(key):Connect(function()
			local value = player:GetAttribute(key)
			if type(value) == "number" and PlayerDataHandler.getData(player) and value ~= PlayerDataHandler.get(player, key) then
				PlayerDataHandler.set(player, key, value)
			end
		end)
	end
end

function DailyRewardHandler.Start()
	network.waitUntilReadyAsync()

	if runService:IsStudio() then
		players.PlayerAdded:Connect(watchStudioOverrides)
		for _, player in players:GetPlayers() do
			watchStudioOverrides(player)
		end
	end

	network.connectEvent(network.RemoteEvents.ClaimDailyReward, function(player: Player)
		local success, reason, reward = DailyRewardHandler.claim(player)
		network.fireClient(network.RemoteEvents.DailyRewardResult, player, success, reason, reward)
	end, { network.Middleware.RateLimit(CLAIM_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestDailyRewardState, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	PlayerDataHandler.Loaded:Connect(pushState)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if STATE_KEYS[key] then
			queuePush(player)
		end
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		pushQueued[player] = nil
	end)

	for _, player in players:GetPlayers() do
		task.spawn(pushState, player)
	end
end

return DailyRewardHandler
