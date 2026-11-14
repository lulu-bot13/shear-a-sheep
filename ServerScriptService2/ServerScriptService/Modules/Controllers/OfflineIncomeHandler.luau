--!strict

--[[
	Offline earnings: podium sheep keep paying their wool trickle for up to 3 hours while the player is away.
	The total waits in OfflineWool until claimed from the OfflineEarnings popup.

	Location: ServerScriptService.Modules.Controllers.OfflineIncomeHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)

--// Configs
local MAX_OFFLINE_SECONDS = 3 * 60 * 60
local OFFLINE_RATE = 1 -- share of the online podium trickle paid while away
local MIN_AWAY_SECONDS = 120 -- shorter gaps (a quick rejoin) pay nothing
local STAMP_SECONDS = 60 -- LastOnline is refreshed this often, so a server crash doesn't count play time as time away
local CLAIM_COOLDOWN = 1
local STATE_REQUEST_COOLDOWN = 0.5
-- Studio only, set on the server player: pretend they were away this long / earn this much wool a second instead of the podium rate.
local STUDIO_TEST_ATTRIBUTE = "OfflineTestSeconds"
local STUDIO_RATE_ATTRIBUTE = "OfflineTestRate"

export type State = {
	wool: number, -- waiting to be claimed
	awaySeconds: number, -- counted for this visit (capped)
	maxSeconds: number,
	perMinute: number, -- wool a minute away earns right now
}

--// State
local arrived: { [Player]: boolean } = {}
local awaySeconds: { [Player]: number } = {}

local OfflineIncomeHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function getRate(player: Player): number
	local testRate = if runService:IsStudio() then player:GetAttribute(STUDIO_RATE_ATTRIBUTE) else nil
	if type(testRate) == "number" then
		return testRate
	end
	return PodiumBonusHandler.getTrickleRate(player) * OFFLINE_RATE
end

function OfflineIncomeHandler.getState(player: Player): State
	return {
		wool = getNumber(player, "OfflineWool"),
		awaySeconds = awaySeconds[player] or 0,
		maxSeconds = MAX_OFFLINE_SECONDS,
		perMinute = math.floor(getRate(player) * 60),
	}
end

local function pushState(player: Player)
	if PlayerDataHandler.getData(player) then
		network.fireClient(network.RemoteEvents.OfflineEarningsState, player, OfflineIncomeHandler.getState(player))
	end
end

-- Adds `seconds` away (capped) of podium wool to what's waiting.
local function grant(player: Player, seconds: number)
	local counted = math.clamp(seconds, 0, MAX_OFFLINE_SECONDS)
	local earned = math.floor(getRate(player) * counted)
	if counted < MIN_AWAY_SECONDS or earned <= 0 then
		return
	end
	awaySeconds[player] = counted
	PlayerDataHandler.increment(player, "OfflineWool", earned)
end

local function stamp(player: Player)
	local data = PlayerDataHandler.getData(player)
	if data then
		data.LastOnline = os.time() -- written straight to the save: it's bookkeeping, nothing listens for it
	end
end

-- Once per visit, as soon as the save is loaded: pay the time since the player was last seen, then start the clock again.
local function onLoaded(player: Player)
	if arrived[player] or not PlayerDataHandler.getData(player) then
		return
	end
	arrived[player] = true

	local lastOnline = getNumber(player, "LastOnline")
	if lastOnline > 0 then
		grant(player, os.time() - lastOnline)
	end
	stamp(player)
	pushState(player)
end

function OfflineIncomeHandler.claim(player: Player): boolean
	local wool = getNumber(player, "OfflineWool")
	if wool <= 0 then
		return false
	end
	PlayerDataHandler.set(player, "OfflineWool", 0)
	PlayerDataHandler.increment(player, "Wool", wool)
	Analytics.woolEarned(player, wool, "Offline")
	return true
end

--// Lifecycle ---------------------------------------------------------------------

local function watchStudioTest(player: Player)
	player:GetAttributeChangedSignal(STUDIO_TEST_ATTRIBUTE):Connect(function()
		local seconds = player:GetAttribute(STUDIO_TEST_ATTRIBUTE)
		if type(seconds) == "number" and PlayerDataHandler.getData(player) then
			grant(player, seconds)
			pushState(player)
		end
	end)
	player:GetAttributeChangedSignal(STUDIO_RATE_ATTRIBUTE):Connect(function()
		pushState(player)
	end)
end

function OfflineIncomeHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.ClaimOfflineEarnings, function(player: Player)
		OfflineIncomeHandler.claim(player)
		pushState(player)
	end, { network.Middleware.RateLimit(CLAIM_COOLDOWN) })

	network.connectEvent(network.RemoteEvents.RequestOfflineEarnings, pushState, {
		network.Middleware.RateLimit(STATE_REQUEST_COOLDOWN),
	})

	-- The podium sheep set the rate shown on the leave warning.
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "PodiumSheep" and arrived[player] then
			pushState(player)
		end
	end)

	PlayerDataHandler.Loaded:Connect(onLoaded)
	players.PlayerRemoving:Connect(function(player: Player)
		arrived[player] = nil
		awaySeconds[player] = nil
	end)
	for _, player in players:GetPlayers() do
		task.spawn(onLoaded, player)
	end

	if runService:IsStudio() then
		players.PlayerAdded:Connect(watchStudioTest)
		for _, player in players:GetPlayers() do
			watchStudioTest(player)
		end
	end

	task.spawn(function()
		while true do
			task.wait(STAMP_SECONDS)
			for player in arrived do
				stamp(player)
			end
		end
	end)
end

return OfflineIncomeHandler
