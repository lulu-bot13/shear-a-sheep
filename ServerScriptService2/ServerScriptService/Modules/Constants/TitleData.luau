--!strict

--[[
	Every title a player can earn from lifetime sheep sheared, and the lookups for the current and next one.

	Location: ServerScriptService.Modules.Constants.TitleData
]]--

export type TitleInfo = {
	name: string, -- placeholder text shown to players
	sheepRequired: number, -- lifetime sheep sheared to earn it
	color: Color3,
}

local titleData = {}

-- Lowest first; the first entry must need 0 so every player has a title.
titleData.Titles = {
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
} :: { TitleInfo }

-- Index into Titles of the highest title this many sheep sheared has earned.
function titleData.getIndex(sheepSheared: number): number
	local index = 1
	for i, info in titleData.Titles do
		if sheepSheared >= info.sheepRequired then
			index = i
		else
			break
		end
	end
	return index
end

function titleData.getTitle(sheepSheared: number): TitleInfo
	return titleData.Titles[titleData.getIndex(sheepSheared)]
end

-- The next title to work towards, or nil once the last one is earned.
function titleData.getNextTitle(sheepSheared: number): TitleInfo?
	return titleData.Titles[titleData.getIndex(sheepSheared) + 1]
end

return titleData
