--!strict

--[[
	Game pass ownership: a player owns a pass if UserOwnsGamePassAsync says so (checked once on join, then cached) or it was gifted to them (GiftedPasses).
	Purchases count straight away from PromptGamePassPurchaseFinished; onPassOwned callbacks fire on join, on purchase and on gift.

	Location: ServerScriptService.Modules.Controllers.GamePassService
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")

--// Modules
local Wiring = require(script.Parent.MonetizationWiring)

--// Configs
local GIFTED_KEY = "GiftedPasses" -- save key: { [pass key]: true } for passes another player gifted
local CHECK_ATTEMPTS = 3
local CHECK_RETRY_SECONDS = 2
local PASS_ATTRIBUTE_PREFIX = "Pass" -- player attribute Pass<key> = true once owned (bought or gifted), for every client to show

export type Source = "Owned" | "Purchased" | "Gifted" -- Owned = already had it when they joined

--// State
local config, store = Wiring.config, Wiring.store
local apiOwned: { [Player]: { [string]: boolean } } = {}
local notified: { [Player]: { [string]: boolean } } = {} -- passes whose onPassOwned callbacks already ran this session
local callbacks: { [string]: { (Player, Source) -> () } } = {}
local changedCallbacks: { (Player, string) -> () } = {}

local GamePassService = {}

local function isGifted(player: Player, key: string): boolean
	local gifted = store.get(player, GIFTED_KEY)
	return type(gifted) == "table" and gifted[key] == true
end

local function notify(player: Player, key: string, source: Source)
	local done = notified[player]
	if not done or done[key] or not GamePassService.ownsPass(player, key) then
		return
	end
	done[key] = true
	player:SetAttribute(PASS_ATTRIBUTE_PREFIX .. key, true)

	for _, callback in callbacks[key] or {} do
		task.spawn(callback, player, source)
	end
	for _, callback in changedCallbacks do
		task.spawn(callback, player, key)
	end
end

local function checkOwnership(player: Player, item: Wiring.Item): boolean
	for attempt = 1, CHECK_ATTEMPTS do
		local success, owns = pcall(marketplaceService.UserOwnsGamePassAsync, marketplaceService, player.UserId, item.id)
		if success then
			return owns == true
		end
		if attempt < CHECK_ATTEMPTS then
			task.wait(CHECK_RETRY_SECONDS)
		else
			warn(`GamePassService: checking {player.Name}'s {item.key} pass failed: {owns}`)
		end
	end
	return false
end

--// Public API ------------------------------------------------------------------

-- Never yields: before the join check finishes only gifted passes count.
function GamePassService.ownsPass(player: Player, key: string): boolean
	local owned = apiOwned[player]
	return (owned ~= nil and owned[key] == true) or isGifted(player, key)
end

-- Every pass key the player owns, as a set.
function GamePassService.getOwnedPasses(player: Player): { [string]: boolean }
	local owned = {}
	for key, item in config.Items do
		if item.kind == "GamePass" and GamePassService.ownsPass(player, key) then
			owned[key] = true
		end
	end
	return owned
end

-- Runs `callback(player, source)` once per session for each player who owns the pass, including those already in game.
function GamePassService.onPassOwned(key: string, callback: (Player, Source) -> ())
	callbacks[key] = callbacks[key] or {}
	table.insert(callbacks[key], callback)

	for player, done in notified do
		if done[key] then
			task.spawn(callback, player, "Owned")
		end
	end
end

-- Runs `callback(player, key)` whenever a player newly owns any pass.
function GamePassService.onChanged(callback: (Player, string) -> ())
	table.insert(changedCallbacks, callback)
end

-- Saves the pass as gifted to the player (must have their data loaded); true once it's in their save.
function GamePassService.grantGiftedPass(player: Player, key: string): boolean
	local gifted = store.get(player, GIFTED_KEY)
	if type(gifted) ~= "table" then
		return false
	end

	local newGifted = table.clone(gifted)
	newGifted[key] = true
	store.set(player, GIFTED_KEY, newGifted)
	notify(player, key, "Gifted")
	return true
end

--// Lifecycle ---------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Set up before the save loads, so a purchase made meanwhile still counts.
	apiOwned[player] = apiOwned[player] or {}
	notified[player] = notified[player] or {}
	if not store.waitForData(player) then
		return
	end

	for key, item in config.Items do
		if item.kind ~= "GamePass" then
			continue
		end
		if isGifted(player, key) then
			notify(player, key, "Owned")
		elseif item.id ~= 0 then
			task.spawn(function()
				if checkOwnership(player, item) and apiOwned[player] then
					apiOwned[player][key] = true
					notify(player, key, "Owned")
				end
			end)
		end
	end
end

function GamePassService.Setup()
	marketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		local item = config.findByPassId(gamePassId)
		if not purchased or not item or not apiOwned[player] then
			return
		end
		apiOwned[player][item.key] = true
		notify(player, item.key, "Purchased")
	end)

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player: Player)
		apiOwned[player] = nil
		notified[player] = nil
	end)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return GamePassService
