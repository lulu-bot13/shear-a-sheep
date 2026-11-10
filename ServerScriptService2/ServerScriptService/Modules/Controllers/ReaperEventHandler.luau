--!strict

--[[
	Night event: some Nights a King Reaper rises in every farm and summons Small Reapers until it is sheared (announced) or the Night ends.
	/reaper starts it now (admins, or anyone in Studio).

	Location: ServerScriptService.Modules.Controllers.ReaperEventHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepSpawnHandler = require(script.Parent.SheepSpawnHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Configs
local EVENT_CHANCE = 0.35 -- chance a Night brings the Reapers
local MIN_START_DELAY = 15 -- seconds into the Night before the King rises
local MAX_START_DELAY = 45
local MINION_INTERVAL = 8 -- seconds between Small Reapers while the King is on the farm
local MAX_MINIONS = 4 -- Small Reapers on one farm at once
local KING_TYPE = "KingReaper"
local MINION_TYPE = "SmallReaper"
local SCHEDULE_SOURCE = "ReaperRaid" -- WeatherHandler's next-event countdown
local EVENT_NAME = "Reaper Raid"

type Spawned = { sheep: Model, id: number }

--// State
local kings: { [Player]: Spawned } = {}
local round = 0 -- bumped at every Night's start and end, so raids from an earlier Night stop
local random = Random.new()

local ReaperEventHandler = {}

-- True while this spawn is still on the farm (rising out of its pit or walking about), not sheared, removed or pooled.
local function isOnFarm(spawned: Spawned): boolean
	local sheep = spawned.sheep
	return sheep:GetAttribute("id") == spawned.id
		and (SheepHandler.getSheep(spawned.id) == sheep or sheep:GetAttribute("Rising") == true)
end

local function spawnReaper(player: Player, sheepType: string): Spawned?
	local sheep = SheepSpawnHandler.spawnForced(player, { sheepType = sheepType, size = "Normal", noMutation = true })
	local id = sheep and sheep:GetAttribute("id")
	return if sheep and type(id) == "number" then { sheep = sheep, id = id } else nil
end

-- Only the plot's owner can shear their King, so shearing it bare is credited to them.
local function watchKing(player: Player, king: Spawned): RBXScriptConnection
	local connection: RBXScriptConnection
	connection = king.sheep:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		local health = king.sheep:GetAttribute("ShearHealth")
		if king.sheep:GetAttribute("id") ~= king.id or type(health) ~= "number" or health > 0 then
			return
		end
		connection:Disconnect()
		if player.Parent then
			AnnouncementHandler.reaperDefeated(player)
		end
	end)
	return connection
end

-- The King rises, then a Small Reaper joins it every MINION_INTERVAL (up to MAX_MINIONS) until it's gone or the Night ends.
local function runRaid(player: Player, raidRound: number)
	local king = spawnReaper(player, KING_TYPE)
	if not king then
		return
	end
	kings[player] = king
	local defeatConnection = watchKing(player, king)

	local minions: { Spawned } = {}
	while raidRound == round and kings[player] == king and isOnFarm(king) do
		task.wait(MINION_INTERVAL)
		for index = #minions, 1, -1 do
			if not isOnFarm(minions[index]) then
				table.remove(minions, index)
			end
		end
		local minion = if raidRound == round and kings[player] == king and isOnFarm(king) and #minions < MAX_MINIONS
			then spawnReaper(player, MINION_TYPE)
			else nil
		if minion then
			table.insert(minions, minion)
		end
	end

	defeatConnection:Disconnect()
	if kings[player] == king then
		kings[player] = nil
	end
end

local function startRaid()
	WeatherHandler.setScheduled(SCHEDULE_SOURCE, nil, nil)
	local raidRound = round
	for _, player in players:GetPlayers() do
		if not kings[player] then
			task.spawn(runRaid, player, raidRound)
		end
	end
	AnnouncementHandler.reaperRaid()
end

-- A King still on a farm when the Night ends leaves it; its Small Reapers stay to be sheared.
local function endRaid()
	for player, king in kings do
		if SheepHandler.getSheep(king.id) == king.sheep then
			SheepHandler.removeSheep(king.id)
		end
		kings[player] = nil
	end
end

local function onHalloweenChanged(halloween: boolean)
	round += 1
	WeatherHandler.setScheduled(SCHEDULE_SOURCE, nil, nil)
	if not halloween then
		endRaid()
		return
	end
	if random:NextNumber() >= EVENT_CHANCE then
		return
	end

	local nightRound = round
	local startDelay = random:NextNumber(MIN_START_DELAY, MAX_START_DELAY)
	WeatherHandler.setScheduled(SCHEDULE_SOURCE, EVENT_NAME, workspace:GetServerTimeNow() + startDelay)
	task.delay(startDelay, function()
		if nightRound == round then
			startRaid()
		end
	end)
end

local function onCommand(speaker: Player)
	if not WeatherHandler.isHalloween() then
		WeatherHandler.setWeather(WeatherData.Halloween)
		round += 1 -- cancels the Night's own rolled start, so the raid isn't announced twice
	end
	startRaid()
	print(`ReaperEventHandler: {speaker.Name} started the Reaper raid.`)
end

--// Lifecycle -----------------------------------------------------------------------

function ReaperEventHandler.Start()
	WeatherHandler.HalloweenChanged:Connect(onHalloweenChanged)
	AdminCommands.register("ReaperCommand", "/reaper", "/reaperraid", onCommand)
	players.PlayerRemoving:Connect(function(player: Player)
		kings[player] = nil
	end)
end

return ReaperEventHandler
