--!strict

--[[
	Turns each player's saved podium sheep into Wool, Luck and Respawn multipliers, shows each podium sheep's stats on a
	pooled billboard and pays the podium wool trickle. Totals are mirrored to PodiumWool/PodiumLuck/PodiumRespawn attributes.
	Location: ServerScriptService.Modules.Controllers.PodiumBonusHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local PodiumData = require(script.Parent.Parent.Constants.PodiumData)
local ObjectPool = require(script.Parent.Parent.Utils.ObjectPool)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local STATS_POOL = "PodiumStats"
local STATS_NAME = "PodiumStats"
local ROW_HEIGHT = 1.3 -- studs per stat row
local BILLBOARD_WIDTH = 5 -- studs
local BELOW_FEET = 0.4 -- studs between the sheep's feet and the top of the billboard
local MAX_DISTANCE = 80
local TEXT_FONT = Enum.Font.FredokaOne
local TRICKLE_SECONDS = 10 -- paid in chunks so the HUD wool counter doesn't pulse every second

--// State
local totals: { [Player]: PodiumData.Bonus } = {}
local trickleCarry: { [Player]: number } = {} -- wool earned but not yet a whole number

local PodiumBonusHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getSaved(player: Player): { [string]: any }
	local saved = PlayerDataHandler.get(player, "PodiumSheep")
	return if type(saved) == "table" then saved else {}
end

local function getTotals(player: Player): PodiumData.Bonus
	return totals[player] or PodiumData.emptyBonus()
end

--// Stats billboard -------------------------------------------------------------------

-- One row per stat (icon, then "x1.2" in the stat's colour), stacked by a UIListLayout; rows are hidden when unused.
local function createStatsBillboard(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = STATS_NAME
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE
	billboard.LightInfluence = 0

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = billboard

	for order, stat: PodiumData.Stat in PodiumData.StatOrder do
		local row = Instance.new("Frame")
		row.Name = stat
		row.LayoutOrder = order
		row.BackgroundTransparency = 1

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.SortOrder = Enum.SortOrder.LayoutOrder
		rowList.Padding = UDim.new(0.04, 0)
		rowList.Parent = row

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.LayoutOrder = 1
		icon.Size = UDim2.fromScale(1, 1)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.BackgroundTransparency = 1
		icon.Image = PodiumData.StatIcons[stat]
		icon.Parent = row

		local amount = Instance.new("TextLabel")
		amount.Name = "Amount"
		amount.LayoutOrder = 2
		amount.Size = UDim2.fromScale(2.2, 1)
		amount.SizeConstraint = Enum.SizeConstraint.RelativeYY
		amount.BackgroundTransparency = 1
		amount.Font = TEXT_FONT
		amount.TextScaled = true
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.TextColor3 = PodiumData.StatColors[stat]

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = amount

		amount.Parent = row
		row.Parent = billboard
	end
	return billboard
end

local function getRoot(sheep: Model): BasePart?
	local root = sheep:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Puts the stats billboard on the podium sheep's HumanoidRootPart, just under its feet so it never covers its name card.
function PodiumBonusHandler.showStats(sheep: Model, saved: any)
	local root = getRoot(sheep)
	if not root then
		return
	end
	PodiumBonusHandler.hideStats(sheep)

	local bonus = PodiumData.getBonus(saved)
	local billboard = (ObjectPool.acquire(STATS_POOL, STATS_POOL) or createStatsBillboard()) :: BillboardGui
	local rows = 0
	for _, stat in PodiumData.StatOrder do
		if bonus[stat] > 0 then
			rows += 1
		end
	end
	if rows == 0 then
		ObjectPool.release(STATS_POOL, STATS_POOL, billboard)
		return
	end

	for _, stat in PodiumData.StatOrder do
		local row = billboard:FindFirstChild(stat) :: Frame
		local amount = row:FindFirstChild("Amount") :: TextLabel
		row.Visible = bonus[stat] > 0
		row.Size = UDim2.fromScale(1, 1 / rows)
		amount.Text = PodiumData.formatMultiplier(bonus[stat])
	end

	local height = ROW_HEIGHT * rows
	local boxCFrame, boxSize = sheep:GetBoundingBox()
	local feetBelowRoot = root.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	billboard.Size = UDim2.fromScale(BILLBOARD_WIDTH, height)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, -feetBelowRoot - BELOW_FEET - height / 2, 0)
	billboard.Adornee = root
	billboard.Parent = root
end

-- Sends the sheep's stats billboard back to the pool (safe to call when it has none).
function PodiumBonusHandler.hideStats(sheep: Model)
	local root = getRoot(sheep)
	local billboard = root and root:FindFirstChild(STATS_NAME)
	if billboard and billboard:IsA("BillboardGui") then
		billboard.Adornee = nil :: any -- the type definitions don't allow nil, but the engine does
		ObjectPool.release(STATS_POOL, STATS_POOL, billboard)
	end
end

--// Totals ----------------------------------------------------------------------------

local function refresh(player: Player)
	local bonus = PodiumData.getTotals(getSaved(player))
	totals[player] = bonus
	player:SetAttribute("PodiumWool", bonus.Wool)
	player:SetAttribute("PodiumLuck", bonus.Luck)
	player:SetAttribute("PodiumRespawn", bonus.Respawn)
end

-- Pays every online player TrickleFactor of each podium sheep's wool per second (every TRICKLE_SECONDS), carrying the fractions over.
local function payTrickle()
	for player in totals do
		local wool = 0
		for _, saved in getSaved(player) do
			if type(saved) == "table" and type(saved.wool) == "number" then
				wool += saved.wool
			end
		end

		local earned = (trickleCarry[player] or 0) + wool * PodiumData.TrickleFactor * TRICKLE_SECONDS
		local whole = math.floor(earned)
		trickleCarry[player] = earned - whole
		if whole > 0 then
			PlayerDataHandler.increment(player, "Wool", whole)
		end
	end
end

--// Public API ------------------------------------------------------------------------

-- Multiplies wool from shearing.
function PodiumBonusHandler.getWoolMultiplier(player: Player): number
	return 1 + getTotals(player).Wool
end

-- Multiplies the spawn roll's luck factor (like the weather's).
function PodiumBonusHandler.getLuckMultiplier(player: Player): number
	return 1 + getTotals(player).Luck
end

-- Multiplies the seconds between sheep refills.
function PodiumBonusHandler.getRespawnMultiplier(player: Player): number
	return 1 - getTotals(player).Respawn
end

--// Lifecycle -----------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if PlayerDataHandler.waitForData(player) and player.Parent then
		refresh(player)
	end
end

function PodiumBonusHandler.Start()
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "PodiumSheep" and player.Parent then
			refresh(player)
		end
	end)
	players.PlayerRemoving:Connect(function(player: Player)
		totals[player] = nil
		trickleCarry[player] = nil
	end)
	players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(function()
		while true do
			task.wait(TRICKLE_SECONDS)
			payTrickle()
		end
	end)
end

return PodiumBonusHandler
