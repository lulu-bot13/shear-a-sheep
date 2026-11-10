--!strict

--[[
	Decides when a player sees a contextual Robux offer (Starter Pack, Luck Boost, Auto Shears, Server Luck): one per 10 minutes at most,
	never in the tutorial, a fresh session or near a King Sheep spawn. Also runs the one-time Auto Shears trial and the Starter Pack window.

	Location: ServerScriptService.Modules.Controllers.OfferHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local GamePassService = require(script.Parent.GamePassService)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local SheepData = require(script.Parent.Parent.Constants.SheepData)

--// Configs
local CHECK_SECONDS = 5
local OFFER_COOLDOWN = 600 -- at most one offer per player this often
local SESSION_GRACE = 180 -- no offers this soon after joining
local BOSS_QUIET_SECONDS = 20 -- no offers this close to a King Sheep spawn
local OFFER_SHOW_SECONDS = 15 -- how long the client keeps an offer up (it can be dismissed sooner)
local RESPONSE_COOLDOWN = 0.5

local AUTO_SHEARS_SWINGS = 150 -- manual swings in a session before Auto Shears is offered
local SWING_COUNT_GAP = 0.25 -- swings closer together than this aren't counted (ShearHandler rate limits them anyway)
local TRIAL_SECONDS = 60 -- the free Auto Shears trial
local STUCK_SECONDS = 480 -- at max Spawn Luck without the rebirth sheep this long before Luck Boost is offered
local SERVER_LUCK_MIN_PLAYERS = 2
local SERVER_LUCK_MIN_SESSION = 600
local STARTER_PACK_HOURS = 72 -- after FirstJoinAt
local STARTER_PACK_SESSIONS = 3

local AUTO_SHEAR_ATTRIBUTE = "AutoShearPass" -- what ShearClient reads to unlock Auto Shear (MonetizationHandler sets it for owners)
local TRIAL_ENDS_ATTRIBUTE = "AutoShearTrialEndsAt" -- workspace:GetServerTimeNow() the trial ends, while it runs
local LUCK_BOOST_ENDS_ATTRIBUTE = "LuckBoostEndsAt" -- set by MonetizationHandler while a Luck Boost runs
local SERVER_LUCK_ATTRIBUTE = "ServerLuckEndsAt"
local BOSS_STATE_ATTRIBUTE = "WorldBossState" -- "None" | "Pending" | "Active" (WorldBossHandler)
local BOSS_AT_ATTRIBUTE = "WorldBossAt"

export type Offer = {
	key: string, -- MonetizationData key
	title: string,
	text: string,
	duration: number, -- seconds the client shows it
	secondsLeft: number?, -- the Starter Pack's countdown
	trial: boolean?, -- Auto Shears: the free trial can still be started
}

type Session = {
	startedAt: number,
	lastOfferAt: number,
	suppressed: { [string]: boolean }, -- answered this session, never shown again until rejoin
	swings: number,
	lastSwingAt: number,
	stuckSince: number?,
	trialActive: boolean,
	connections: { RBXScriptConnection },
}

--// State
local Items = MonetizationData.Items
local sessions: { [Player]: Session } = {}
local lastBossSpawnAt = -math.huge

local OfferHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function isSetUp(key: string): boolean
	local item = Items[key]
	return item ~= nil and item.id ~= 0
end

--// Rules ------------------------------------------------------------------------------

-- The tutorial runs until the first rebirth (TutorialClient), or while anything sets InTutorial.
local function isInTutorial(player: Player): boolean
	return player:GetAttribute("InTutorial") == true or (getNumber(player, "Rebirths") == 0 and getNumber(player, "Prestiges") == 0)
end

-- Quiet while a King Sheep is about to arrive, is fighting, or arrived moments ago.
local function isBossTime(): boolean
	local now = workspace:GetServerTimeNow()
	local state = workspace:GetAttribute(BOSS_STATE_ATTRIBUTE)
	local at = workspace:GetAttribute(BOSS_AT_ATTRIBUTE)
	if state == "Active" or now - lastBossSpawnAt < BOSS_QUIET_SECONDS then
		return true
	end
	return state == "Pending" and type(at) == "number" and at - now < BOSS_QUIET_SECONDS + OFFER_SHOW_SECONDS
end

local function getStarterPackSecondsLeft(player: Player): number
	local firstJoinAt = getNumber(player, "FirstJoinAt")
	if firstJoinAt <= 0 then
		return 0
	end
	return math.max(firstJoinAt + STARTER_PACK_HOURS * 3600 - os.time(), 0)
end

local function getRebirthSheepName(player: Player): string
	local sheepId = player:GetAttribute("RebirthSheepId")
	local info = if type(sheepId) == "string" then SheepData.Sheep[sheepId] else nil
	return if info and type(info.name) == "string" then info.name else "rebirth sheep"
end

--// Offers -----------------------------------------------------------------------------
-- Each returns the offer if it fits the player right now.

local function starterPackOffer(player: Player): Offer?
	if not OfferHandler.canBuyStarterPack(player) then
		return nil
	end
	local item = Items.StarterPack
	return {
		key = item.key,
		title = item.displayName,
		text = item.rewardText or "",
		duration = OFFER_SHOW_SECONDS,
		secondsLeft = getStarterPackSecondsLeft(player),
	}
end

local function luckBoostOffer(player: Player, session: Session, now: number): Offer?
	local stuckSince = session.stuckSince
	if not isSetUp("LuckBoost") or not stuckSince or now - stuckSince < STUCK_SECONDS then
		return nil
	elseif player:GetAttribute(LUCK_BOOST_ENDS_ATTRIBUTE) ~= nil then
		return nil
	end
	local item = Items.LuckBoost
	return {
		key = item.key,
		title = item.displayName,
		text = `Still hunting the {getRebirthSheepName(player)}? {item.multiplier or 1}x Luck for {item.durationMinutes or 0} minutes!`,
		duration = OFFER_SHOW_SECONDS,
	}
end

local function autoShearsOffer(player: Player, session: Session): Offer?
	if not isSetUp("AutoShears") or session.trialActive or session.swings < AUTO_SHEARS_SWINGS then
		return nil
	elseif GamePassService.ownsPass(player, "AutoShears") then
		return nil
	end
	local item = Items.AutoShears
	return {
		key = item.key,
		title = item.displayName,
		text = "That's a lot of clicking! Auto Shears swings for you.",
		duration = OFFER_SHOW_SECONDS,
		trial = getNumber(player, "AutoShearTrialUsed") ~= 1,
	}
end

local function serverLuckOffer(session: Session, now: number): Offer?
	if not isSetUp("ServerLuck") or now - session.startedAt < SERVER_LUCK_MIN_SESSION then
		return nil
	end
	local endsAt = workspace:GetAttribute(SERVER_LUCK_ATTRIBUTE)
	local bossState = workspace:GetAttribute(BOSS_STATE_ATTRIBUTE)
	if type(endsAt) == "number" and endsAt > workspace:GetServerTimeNow() then
		return nil
	elseif #players:GetPlayers() < SERVER_LUCK_MIN_PLAYERS or (bossState ~= nil and bossState ~= "None") then
		return nil
	end
	local item = Items.ServerLuck
	return {
		key = item.key,
		title = item.displayName,
		text = `{item.multiplier or 1}x Luck for everyone in the server for {item.durationMinutes or 0} minutes!`,
		duration = OFFER_SHOW_SECONDS,
	}
end

local function pickOffer(player: Player, session: Session, now: number): Offer?
	local candidates = {
		starterPackOffer(player),
		luckBoostOffer(player, session, now),
		autoShearsOffer(player, session),
		serverLuckOffer(session, now),
	}
	-- Fixed slots, so a nil in the middle doesn't hide the ones after it.
	for index = 1, 4 do
		local offer = candidates[index]
		if offer and not session.suppressed[offer.key] then
			return offer
		end
	end
	return nil
end

local function checkPlayer(player: Player, now: number)
	local session = sessions[player]
	if not session or not PlayerDataHandler.getData(player) then
		return
	end
	if now - session.startedAt < SESSION_GRACE or now - session.lastOfferAt < OFFER_COOLDOWN or isInTutorial(player) then
		return
	end

	local offer = pickOffer(player, session, now)
	if offer then
		session.lastOfferAt = now
		network.fireClient(network.RemoteEvents.ShowOffer, player, offer)
	end
end

--// Auto Shears trial ------------------------------------------------------------------

local function endTrial(player: Player)
	local session = sessions[player]
	if session then
		session.trialActive = false
	end
	if not player.Parent then
		return
	end
	player:SetAttribute(TRIAL_ENDS_ATTRIBUTE, nil)
	if not GamePassService.ownsPass(player, "AutoShears") then
		player:SetAttribute(AUTO_SHEAR_ATTRIBUTE, nil)
		network.fireClient(network.RemoteEvents.ShowAlert, player, "Your Auto Shears trial is over. Get it in the shop!", "info")
	end
end

local function startTrial(player: Player, session: Session)
	if session.trialActive or getNumber(player, "AutoShearTrialUsed") == 1 or GamePassService.ownsPass(player, "AutoShears") then
		return
	end
	PlayerDataHandler.set(player, "AutoShearTrialUsed", 1)
	session.trialActive = true
	player:SetAttribute(TRIAL_ENDS_ATTRIBUTE, workspace:GetServerTimeNow() + TRIAL_SECONDS)
	player:SetAttribute(AUTO_SHEAR_ATTRIBUTE, true)
	network.fireClient(network.RemoteEvents.ShowAlert, player, `Auto Shears free for {TRIAL_SECONDS} seconds! Turn on Auto Shear`, "success")
	task.delay(TRIAL_SECONDS, endTrial, player)
end

--// Remotes ------------------------------------------------------------------------------

-- "Accept" (the client prompts the purchase), "Dismiss" ("Not today") or "Trial"; any answer ends that offer for the session.
local function onResponse(player: Player, key: any, action: any)
	local session = sessions[player]
	if not session or type(key) ~= "string" or not Items[key] then
		return
	end
	session.suppressed[key] = true
	if action == "Trial" and key == "AutoShears" then
		startTrial(player, session)
	end
end

local function onSwing(player: Player)
	local session = sessions[player]
	if not session or session.trialActive then
		return
	end
	local now = os.clock()
	if now - session.lastSwingAt >= SWING_COUNT_GAP then
		session.lastSwingAt = now
		session.swings += 1
	end
end

--// Public API ------------------------------------------------------------------

-- The Starter Pack is for a player's first sessions within STARTER_PACK_HOURS of their first join, once.
function OfferHandler.canBuyStarterPack(player: Player): boolean
	return isSetUp("StarterPack")
		and PlayerDataHandler.getData(player) ~= nil
		and getNumber(player, "StarterPackBought") ~= 1
		and getNumber(player, "SessionCount") <= STARTER_PACK_SESSIONS
		and getStarterPackSecondsLeft(player) > 0
end

--// Lifecycle ---------------------------------------------------------------------

-- Older saves get FirstJoinAt on their first load after this update, so they get the same 72 h window as a new player.
local function onLoaded(player: Player)
	if sessions[player] then
		return
	end
	if getNumber(player, "FirstJoinAt") <= 0 then
		PlayerDataHandler.set(player, "FirstJoinAt", os.time())
	end
	PlayerDataHandler.increment(player, "SessionCount", 1)

	local session: Session = {
		startedAt = os.clock(),
		lastOfferAt = -math.huge,
		suppressed = {},
		swings = 0,
		lastSwingAt = 0,
		stuckSince = nil,
		trialActive = false,
		connections = {},
	}
	sessions[player] = session

	-- Stuck = at max Spawn Luck without the rebirth sheep, continuously (RebirthHandler sets both).
	local function updateStuck()
		local stuck = player:GetAttribute("SpawnLuckMaxed") == true and player:GetAttribute("RebirthSheepFound") == false
		if not stuck then
			session.stuckSince = nil
		elseif not session.stuckSince then
			session.stuckSince = os.clock()
		end
	end
	table.insert(session.connections, player:GetAttributeChangedSignal("SpawnLuckMaxed"):Connect(updateStuck))
	table.insert(session.connections, player:GetAttributeChangedSignal("RebirthSheepFound"):Connect(updateStuck))
	updateStuck()
end

function OfferHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.OfferResponse, onResponse, {
		network.Middleware.RateLimit(RESPONSE_COOLDOWN),
	})
	network.connectEvent(network.RemoteEvents.ShearSwing, onSwing)

	workspace:GetAttributeChangedSignal(BOSS_STATE_ATTRIBUTE):Connect(function()
		if workspace:GetAttribute(BOSS_STATE_ATTRIBUTE) == "Active" then
			lastBossSpawnAt = workspace:GetServerTimeNow()
		end
	end)

	PlayerDataHandler.Loaded:Connect(onLoaded)
	players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			for _, connection in session.connections do
				connection:Disconnect()
			end
		end
		sessions[player] = nil
	end)
	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) then
			task.spawn(onLoaded, player)
		end
	end

	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			if isBossTime() then
				continue
			end
			local now = os.clock()
			for player in sessions do
				checkPlayer(player, now)
			end
		end
	end)
end

return OfferHandler
