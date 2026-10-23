--!strict

--[[
	Gives each player the title their lifetime sheep sheared has earned and mirrors it to the "Title" and
	"TitleColor" player attributes, which PlayerHUD shows on their head. Titles are earned, not equipped.

	Location: ServerScriptService.Modules.Controllers.TitleHandler
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)

export type TitleInfo = {
	name: string, -- text shown on the PlayerHUD Title label
	sheepRequired: number, -- lifetime sheep sheared to earn it
	color: Color3,
}

--// Configs
local TITLE_ATTRIBUTE = "Title"
local COLOR_ATTRIBUTE = "TitleColor"

-- Lowest first; the first entry must need 0 so every player has a title.
local TITLES: { TitleInfo } = {
	{ name = "Fresh Farmhand",     sheepRequired = 0,     color = Color3.fromRGB(200, 200, 200) },
	{ name = "Wool Gatherer",      sheepRequired = 10,    color = Color3.fromRGB(170, 220, 170) },
	{ name = "Apprentice Shearer", sheepRequired = 25,    color = Color3.fromRGB(120, 200, 120) },
	{ name = "Fleece Handler",     sheepRequired = 100,   color = Color3.fromRGB(90, 170, 255) },
	{ name = "Skilled Shearer",    sheepRequired = 300,   color = Color3.fromRGB(60, 120, 255) },
	{ name = "Master Shearer",     sheepRequired = 750,   color = Color3.fromRGB(170, 90, 255) },
	{ name = "Wool Baron",         sheepRequired = 1500,  color = Color3.fromRGB(200, 60, 230) },
	{ name = "Fleece Lord",        sheepRequired = 3000,  color = Color3.fromRGB(255, 150, 40) },
	{ name = "Sheep Whisperer",    sheepRequired = 6000,  color = Color3.fromRGB(255, 110, 40) },
	{ name = "Legendary Shearer",  sheepRequired = 12000, color = Color3.fromRGB(255, 70, 70) },
	{ name = "Wool Tycoon",        sheepRequired = 25000, color = Color3.fromRGB(255, 40, 110) },
	{ name = "Shear God",          sheepRequired = 50000, color = Color3.fromRGB(255, 215, 60) },
}

--// State
local titleIndex: { [Player]: number } = {}

local TitleHandler = {}

TitleHandler.TitleChanged = Signal.new() -- (player, title: TitleInfo, previous: TitleInfo?)

local function getSheepSheared(player: Player): number
	local value = PlayerDataHandler.get(player, "SheepShearedCount")
	return if type(value) == "number" then value else 0
end

-- Index into TITLES of the highest title this many sheep sheared has earned.
local function getIndex(sheepSheared: number): number
	local index = 1
	for i, info in TITLES do
		if sheepSheared >= info.sheepRequired then
			index = i
		else
			break
		end
	end
	return index
end

-- Works out the player's title and mirrors it if it changed.
local function refresh(player: Player)
	local index = getIndex(getSheepSheared(player))
	local previousIndex = titleIndex[player]
	if index == previousIndex then
		return
	end

	titleIndex[player] = index
	local title = TITLES[index]
	player:SetAttribute(TITLE_ATTRIBUTE, title.name)
	player:SetAttribute(COLOR_ATTRIBUTE, title.color)

	TitleHandler.TitleChanged:Fire(player, title, if previousIndex then TITLES[previousIndex] else nil)
end

--// Public API ------------------------------------------------------------------

-- Every title, lowest first.
function TitleHandler.getTitles(): { TitleInfo }
	return table.clone(TITLES)
end

function TitleHandler.getTitle(player: Player): TitleInfo
	return TITLES[getIndex(getSheepSheared(player))]
end

-- The next title and how many more sheep it needs; nil once the last title is earned.
function TitleHandler.getNextTitle(player: Player): (TitleInfo?, number?)
	local sheared = getSheepSheared(player)
	local nextTitle = TITLES[getIndex(sheared) + 1]
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
