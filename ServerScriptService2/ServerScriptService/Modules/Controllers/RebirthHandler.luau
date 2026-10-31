--!strict

--[[
	Rebirth rules: spend wool for a luck-factor boost; nothing else on the farm is reset.
	Rebirths last until the next Prestige. Costs and the luck boost live in RebirthData.

	Location: ServerScriptService.Modules.Controllers.RebirthHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local Analytics = require(script.Parent.Analytics)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local LEADERSTATS_WAIT_SECONDS = 15

export type State = {
	rebirths: number,
	prestiges: number,
	maxRebirths: number,
	maxed: boolean,
	wool: number,
	woolCost: number,
	canRebirth: boolean,
	luck: number, -- Luck right now
	luckFactor: number, -- the odds multiplier right now
	nextLuckFactor: number, -- the odds multiplier after the next rebirth (same as luckFactor when maxed)

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

local RebirthHandler = {}

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
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
	local woolCost = RebirthData.getWoolCost(rebirths)
	local wool = getNumber(player, "Wool")
	local luck = getNumber(player, "Luck")

	local selected = RebirthHandler.parseAmount(amount)
	local rebirthsLeft = RebirthData.MAX_REBIRTHS - rebirths
	local amountCount, amountCost
	if selected == "max" then
		amountCount, amountCost = RebirthData.getMaxAffordable(rebirths, wool)
	else
		amountCount = math.min(selected, rebirthsLeft)
		amountCost = RebirthData.getTotalWoolCost(rebirths, amountCount) or 0
	end
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
		canRebirth = woolCost ~= nil and wool >= woolCost,
		luck = luck,
		luckFactor = SheepData.getLuckFactor(luck, rebirths, prestiges),
		nextLuckFactor = SheepData.getLuckFactor(luck, rebirths + 1, prestiges),

		amount = selected,
		amountCount = amountCount,
		amountCost = amountCost,
		amountCanRebirth = amountCount > 0 and wool >= amountCost,
		amountLuckFactor = SheepData.getLuckFactor(luck, rebirths + previewCount, prestiges),
	}
end

--[[
	Tries to rebirth the player `amount` times at once (clamped to the rebirths left). Returns true and the
	number done on success, or false plus a reason the client can show ("Busy", "MaxRebirths" or "NotReady").
	A fixed amount is all or nothing. Everything is checked here, on the server.
]]
function RebirthHandler.rebirth(player: Player, amount: Amount?): (boolean, string?, number?)
	if rebirthing[player] or not PlayerDataHandler.getData(player) then
		return false, "Busy", nil
	end

	local state = RebirthHandler.getState(player, amount)
	if state.maxed then
		return false, "MaxRebirths", nil
	end
	if not state.amountCanRebirth then
		return false, "NotReady", nil
	end

	rebirthing[player] = true

	-- The rebirths are counted first, so a problem while paying can never cost the player wool for nothing.
	PlayerDataHandler.set(player, "Rebirths", state.rebirths + state.amountCount)

	local success, err = pcall(function()
		PlayerDataHandler.set(player, "Wool", getNumber(player, "Wool") - state.amountCost)
	end)
	if not success then
		warn(`RebirthHandler: taking {player.Name}'s rebirth cost failed: {err}`)
	end

	rebirthing[player] = nil
	AnnouncementHandler.rebirth(player, state.rebirths, state.rebirths + state.amountCount)
	Analytics.rebirthed(player, state.rebirths + state.amountCount, state.amountCount, state.amountCost)
	return true, nil, state.amountCount
end

--// Lifecycle ---------------------------------------------------------------------

-- Mirrors Rebirths as a leaderstat once the leaderstats folder exists.
local function onPlayerAdded(player: Player)
	if not PlayerDataHandler.waitForData(player) then
		return
	end

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
	end)

	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return RebirthHandler
