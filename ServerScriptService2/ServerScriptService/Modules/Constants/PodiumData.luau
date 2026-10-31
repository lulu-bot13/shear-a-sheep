--!strict

--[[
	Passive bonuses from sheep standing on podiums: rarity sets the size, mutation picks the stat(s), size tier scales it.
	Location: ServerScriptService.Modules.Constants.PodiumData
]]--

local MutationData = require(script.Parent.MutationData)
local SheepData = require(script.Parent.SheepData)
local SheepSizeData = require(script.Parent.SheepSizeData)

export type Stat = "Wool" | "Luck" | "Respawn"
export type Bonus = { Wool: number, Luck: number, Respawn: number } -- 0.2 = +20%, 1 = +100%

local podiumData = {}

podiumData.RarityBonus = {
	Common = 0.02,
	Uncommon = 0.04,
	Rare = 0.07,
	Epic = 0.12,
	Legendary = 0.2,
	Mythic = 0.35,
} :: { [string]: number }

-- Share of the base bonus each stat gets; mutations not listed boost Wool.
podiumData.MutationStats = {
	Haunted = { Luck = 1 },
	Rainbow = { Respawn = 1 },
	Galaxy = { Wool = 0.6, Luck = 0.6, Respawn = 0.6 },
} :: { [string]: { [Stat]: number } }
podiumData.DefaultStats = { Wool = 1 } :: { [Stat]: number }

podiumData.MutationFactor = { Shiny = 1.25 } :: { [string]: number }
podiumData.SizeFactor = { Tiny = 0.75, Normal = 1, Huge = 1.5 } :: { [string]: number }

-- Totals across every podium never go past these (Respawn takes this fraction off the refill interval).
podiumData.Caps = { Wool = 1, Luck = 0.5, Respawn = 0.4 } :: Bonus

-- Every podium sheep earns this fraction of its WoolAmount each second while its owner is online.
podiumData.TrickleFactor = 1 / 60

-- Stat rows on a podium sheep's billboard, top to bottom.
local statOrder: { Stat } = { "Wool", "Luck", "Respawn" }
local statColors: { [Stat]: Color3 } = {
	Wool = Color3.fromRGB(255, 236, 179),
	Luck = Color3.fromRGB(134, 239, 172),
	Respawn = Color3.fromRGB(125, 211, 252),
}
local statIcons: { [Stat]: string } = {
	Wool = "rbxassetid://112199646421676", -- same as WoolData.WoolIconImage
	Luck = "rbxassetid://86611651520562",
	Respawn = "rbxassetid://75508274630013", -- the Faster Respawn upgrade's icon
}
podiumData.StatOrder = statOrder
podiumData.StatColors = statColors
podiumData.StatIcons = statIcons

function podiumData.emptyBonus(): Bonus
	return { Wool = 0, Luck = 0, Respawn = 0 }
end
local emptyBonus = podiumData.emptyBonus

-- The bonus one saved podium sheep (SheepHandler.SavedSheep) gives; all zero when it can't be read.
function podiumData.getBonus(saved: any): Bonus
	local bonus = emptyBonus()
	local info = if type(saved) == "table" then SheepData.Sheep[saved.type] else nil
	local size = if info then SheepSizeData.get(saved.size) else nil
	if not info or not size then
		return bonus
	end

	local mutation = MutationData.get(saved.mutation)
	local mutationId = if mutation then mutation.id else ""
	local base = (podiumData.RarityBonus[info.rarity] or 0)
		* (podiumData.SizeFactor[size.id] or 1)
		* (podiumData.MutationFactor[mutationId] or 1)

	for stat, share in podiumData.MutationStats[mutationId] or podiumData.DefaultStats do
		bonus[stat] = base * share
	end
	return bonus
end

-- Every podium's bonus added up and capped.
function podiumData.getTotals(podiumSheep: any): Bonus
	local totals = emptyBonus()
	if type(podiumSheep) ~= "table" then
		return totals
	end

	for _, saved in podiumSheep do
		local bonus = podiumData.getBonus(saved)
		totals.Wool += bonus.Wool
		totals.Luck += bonus.Luck
		totals.Respawn += bonus.Respawn
	end
	totals.Wool = math.min(totals.Wool, podiumData.Caps.Wool)
	totals.Luck = math.min(totals.Luck, podiumData.Caps.Luck)
	totals.Respawn = math.min(totals.Respawn, podiumData.Caps.Respawn)
	return totals
end

-- A bonus as its multiplier text, e.g. 0.2 -> "x1.2".
function podiumData.formatMultiplier(bonus: number): string
	local text = string.format("%.2f", 1 + bonus):gsub("0+$", ""):gsub("%.$", "")
	return `x{text}`
end

return podiumData
