--!strict

--[[
	Gives each player the title their lifetime sheep sheared has earned (TitleData) and mirrors it to the
	"Title" and "TitleColor" player attributes; TitleChanged fires when a player earns a new one.

	Location: ServerScriptService.Modules.Controllers.TitleHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local TitleData = require(script.Parent.Parent.Constants.TitleData)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

--// Configs
local TITLE_ATTRIBUTE = "Title"
local COLOR_ATTRIBUTE = "TitleColor"

--// State
local titleIndex: { [Player]: number } = {}

local TitleHandler = {}

TitleHandler.TitleChanged = Signal.new() -- (player, title: TitleInfo, previous: TitleInfo?)

local function getSheepSheared(player: Player): number
	local value = PlayerDataHandler.get(player, "SheepShearedCount")
	return if type(value) == "number" then value else 0
end

-- Works out the player's title and mirrors it if it changed.
local function refresh(player: Player)
	local index = TitleData.getIndex(getSheepSheared(player))
	local previousIndex = titleIndex[player]
	if index == previousIndex then
		return
	end

	titleIndex[player] = index
	local title = TitleData.Titles[index]
	player:SetAttribute(TITLE_ATTRIBUTE, title.name)
	player:SetAttribute(COLOR_ATTRIBUTE, title.color)

	TitleHandler.TitleChanged:Fire(player, title, if previousIndex then TitleData.Titles[previousIndex] else nil)
end

--// Public API ------------------------------------------------------------------

function TitleHandler.getTitle(player: Player): TitleData.TitleInfo
	return TitleData.getTitle(getSheepSheared(player))
end

-- The next title and how many more sheep it needs; nil once the last title is earned.
function TitleHandler.getNextTitle(player: Player): (TitleData.TitleInfo?, number?)
	local sheared = getSheepSheared(player)
	local nextTitle = TitleData.getNextTitle(sheared)
	return nextTitle, if nextTitle then nextTitle.sheepRequired - sheared else nil
end

--// Lifecycle ---------------------------------------------------------------------

function TitleHandler.Start()
	PlayerDataHandler.Loaded:Connect(refresh)
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "SheepShearedCount" then
			refresh(player)
		end
	end)

	players.PlayerRemoving:Connect(function(player: Player)
		titleIndex[player] = nil
	end)

	for _, player in players:GetPlayers() do
		if PlayerDataHandler.getData(player) then
			refresh(player)
		end
	end
end

return TitleHandler
