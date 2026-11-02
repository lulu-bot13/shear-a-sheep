--!strict

--[[
	Each player's regional price level (1-1000, 1000 = full global price), fetched on join and kept for their session only.
	Gifts only go from a price level to the same or a lower one, so regional prices can't be used to buy cheap for full-price players.

	Location: ServerScriptService.Modules.Controllers.PriceLevelService
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")

--// Configs
local FETCH_ATTEMPTS = 3
local FETCH_RETRY_SECONDS = 2
local STUDIO_FALLBACK_LEVEL = 1000 -- Studio only, when the lookup fails, so gifting can still be tested; live games fail closed

--// State
local levels: { [Player]: number } = {}
local fetching: { [Player]: boolean } = {}

local PriceLevelService = {}

-- The API has returned both { { UserId, PriceLevel } } and { [userId string]: level }, so either is read.
local function readLevel(result: any, userId: number): number?
	if type(result) ~= "table" then
		return nil
	end
	local keyed = result[tostring(userId)] or result[userId]
	if type(keyed) == "number" then
		return keyed
	end
	for _, info in result do
		if type(info) == "table" and tonumber(info.UserId) == userId and type(info.PriceLevel) == "number" then
			return info.PriceLevel
		end
	end
	return nil
end

local function fetchLevel(player: Player): number?
	for attempt = 1, FETCH_ATTEMPTS do
		local success, result = pcall(marketplaceService.GetUsersPriceLevelsAsync, marketplaceService, { player.UserId })
		local level = if success then readLevel(result, player.UserId) else nil
		if level then
			return level
		end
		if attempt < FETCH_ATTEMPTS then
			task.wait(FETCH_RETRY_SECONDS)
		else
			warn(`[PriceLevelService] couldn't fetch {player.Name}'s price level: {if success then "no PriceLevel" else result}`)
		end
	end
	return if runService:IsStudio() then STUDIO_FALLBACK_LEVEL else nil
end

--// Public API ------------------------------------------------------------------

-- The cached price level, or nil if it isn't known yet. Never yields, so receipt handlers can use it.
function PriceLevelService.get(player: Player): number?
	return levels[player]
end

-- The price level, fetched now if it isn't cached yet; nil if it can't be fetched. Yields.
function PriceLevelService.getAsync(player: Player): number?
	while fetching[player] do
		task.wait()
	end
	if levels[player] or not player.Parent then
		return levels[player]
	end

	fetching[player] = true
	local level = fetchLevel(player)
	fetching[player] = nil
	if level and player.Parent then
		levels[player] = level
	end
	return levels[player]
end

-- True if the gifter's price level is the same as or higher than the recipient's. Unknown levels are never allowed.
function PriceLevelService.canGift(gifter: Player, recipient: Player): boolean
	local gifterLevel, recipientLevel = levels[gifter], levels[recipient]
	return gifterLevel ~= nil and recipientLevel ~= nil and gifterLevel >= recipientLevel
end

-- canGift, fetching either level first if it isn't cached yet. Yields.
function PriceLevelService.canGiftAsync(gifter: Player, recipient: Player): boolean
	PriceLevelService.getAsync(gifter)
	PriceLevelService.getAsync(recipient)
	return PriceLevelService.canGift(gifter, recipient)
end

--// Lifecycle ---------------------------------------------------------------------

function PriceLevelService.Start()
	players.PlayerAdded:Connect(PriceLevelService.getAsync)
	players.PlayerRemoving:Connect(function(player: Player)
		levels[player] = nil
	end)
	for _, player in players:GetPlayers() do
		task.spawn(PriceLevelService.getAsync, player)
	end
end

return PriceLevelService
