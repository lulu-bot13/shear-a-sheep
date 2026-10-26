--[[
	Saves every player's Rebirths and Wool to OrderedDataStores and shows the top 50 on the Workspace boards, refreshed every minute.
]]--

--// Services
local dataStoreService = game:GetService("DataStoreService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local userService = game:GetService("UserService")

--// Modules
local NumberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Configs
local UPDATE_SECONDS = 60
local PAGE_SIZE = 50
local BOARD_WAIT_SECONDS = 15
local BOARDS_FOLDER = workspace:WaitForChild("Base"):WaitForChild("CenterPlaza"):WaitForChild("Leaderboards")

type Board = {
	modelName: string, -- under BOARDS_FOLDER
	storeName: string,
	displayText: string,
	getValue: (player: Player) -> number?,
}

local function getWool(player: Player): number?
	local inventory = player:FindFirstChild("Inventory")
	local wool = inventory and inventory:FindFirstChild("Wool") :: IntValue?
	return if wool then wool.Value else nil
end

local BOARDS: { Board } = {
	{
		modelName = "Rebirths",
		storeName = "Leaderboard_Rebirths_v1",
		displayText = "Rebirths",
		getValue = function(player)
			return player:GetAttribute("Rebirths") :: number?
		end,
	},
	{
		modelName = "Wool",
		storeName = "Leaderboard_Wool_v1",
		displayText = "Wool",
		getValue = getWool,
	},
}

--// State
local nameCache: { [number]: string } = {}

type BoardState = {
	config: Board,
	store: OrderedDataStore,
	rows: { Frame },
	lastSaved: { [number]: number }, -- userId -> value last written, so unchanged values aren't re-sent
}

-- Looks up any usernames not cached yet in one batched request.
local function cacheNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not nameCache[userId] then
			table.insert(missing, userId)
		end
	end
	if #missing == 0 then
		return
	end

	local success, result = pcall(function()
		return userService:GetUserInfosByUserIdsAsync(missing)
	end)
	if not success then
		warn(`Leaderboards: fetching usernames failed: {result}`)
		return
	end
	for _, info in result do
		nameCache[info.Id] = info.Username
	end
end

local function saveValue(state: BoardState, player: Player)
	local value = state.config.getValue(player)
	if type(value) ~= "number" then
		return
	end
	value = math.floor(value)
	if state.lastSaved[player.UserId] == value then
		return
	end

	local success, err = pcall(function()
		state.store:SetAsync(tostring(player.UserId), value)
	end)
	if success then
		state.lastSaved[player.UserId] = value
	else
		warn(`Leaderboards: saving {player.Name}'s {state.config.storeName} failed: {err}`)
	end
end

local function render(state: BoardState)
	local success, result = pcall(function()
		return state.store:GetSortedAsync(false, PAGE_SIZE):GetCurrentPage()
	end)
	if not success then
		warn(`Leaderboards: reading {state.config.storeName} failed: {result}`)
		return
	end

	local userIds = {}
	for index, entry in result do
		userIds[index] = tonumber(entry.key) :: number
	end
	cacheNames(userIds)

	for index, row in state.rows do
		local entry = result[index]
		row.Visible = entry ~= nil
		if not entry then
			continue
		end

		local userId = userIds[index]
		local headshot = row:FindFirstChild("PlayerHeadshot") :: ImageLabel
		local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel
		local amountLabel = row:FindFirstChild("Amount") :: TextLabel

		headshot.Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150`
		nameLabel.Text = `#{index} {nameCache[userId] or "..."}`
		amountLabel.Text = NumberFormatter:Format(entry.value, 2) or "0"
	end
end

-- Clones the template once per rank so each refresh only updates text.
local function setupBoard(config: Board): BoardState?
	local board = BOARDS_FOLDER:WaitForChild(config.modelName, BOARD_WAIT_SECONDS)
	if not board then
		local names = {}
		for _, child in BOARDS_FOLDER:GetChildren() do
			table.insert(names, child.Name)
		end
		warn(`Leaderboards: no "{config.modelName}" board in {BOARDS_FOLDER:GetFullName()} (found: {table.concat(names, ", ")}).`)
		return nil
	end

	-- Found by name so the board works whether Face is a part holding the SurfaceGui or the SurfaceGui itself.
	local template = board:FindFirstChild("Template", true) :: Frame?
	if not template then
		warn(`Leaderboards: {board:GetFullName()} has no Template row.`)
		return nil
	end
	local container = template.Parent :: GuiObject
	template.Visible = false

	local display = board:FindFirstChild("Display", true) :: TextLabel?
	if display then
		display.Text = config.displayText
	end

	-- Column headings above the rows.
	local info = board:FindFirstChild("Info", true)
	if info then
		local nameHeading = info:FindFirstChild("PlayerName") :: TextLabel?
		local amountHeading = info:FindFirstChild("Amount") :: TextLabel?
		if nameHeading then
			nameHeading.Text = "Name"
		end
		if amountHeading then
			amountHeading.Text = "Amount"
		end
	end
	if container:IsA("ScrollingFrame") then
		container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end

	local success, store = pcall(function()
		return dataStoreService:GetOrderedDataStore(config.storeName)
	end)
	if not success then
		warn(`Leaderboards: DataStores unavailable for {config.storeName} ({store}).`)
		return nil
	end

	local rows = {}
	for rank = 1, PAGE_SIZE do
		local row = template:Clone()
		row.Name = `Rank{rank}`
		row.LayoutOrder = rank
		row.Visible = false
		row.Parent = container
		rows[rank] = row
	end

	return {
		config = config,
		store = store,
		rows = rows,
		lastSaved = {},
	}
end

local states: { BoardState } = {}

-- Final write so a player's score is current even if they leave between refreshes.
players.PlayerRemoving:Connect(function(player)
	for _, state in states do
		task.spawn(function()
			saveValue(state, player)
			state.lastSaved[player.UserId] = nil
		end)
	end
end)

-- Each board runs on its own thread so one missing board can't stall the other.
for _, config in BOARDS do
	task.spawn(function()
		local state = setupBoard(config)
		if not state then
			return
		end
		table.insert(states, state)

		while true do
			for _, player in players:GetPlayers() do
				saveValue(state, player)
			end
			render(state)
			task.wait(UPDATE_SECONDS)
		end
	end)
end
