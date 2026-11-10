--!strict

--[[
	Pen fence styles by progression: each tier's model in ServerStorage.PenStyles and the rebirths or Prestiges that unlock it.
	Location: ServerScriptService.Modules.Constants.PenStyleData
]]--

export type Tier = {
	template: string, -- model name in ServerStorage.PenStyles (built over the TemplatePlot's fence, same posts and rails)
	minRebirths: number?,
	minPrestiges: number?,
}

local penStyleData = {}

penStyleData.FolderName = "PenStyles"
penStyleData.FenceName = "PlotFence1" -- the TemplatePlot's fence model; a style's copy replaces it under this name

-- Tier 1 is also the look of unclaimed plots. The highest tier whose minRebirths or minPrestiges is reached wins.
penStyleData.Tiers = {
	{ template = "Tier1", minRebirths = 0 }, -- plain wood
	{ template = "Tier2", minRebirths = 1 }, -- painted picket with red post caps
	{ template = "Tier3", minRebirths = 3 }, -- stone pillars with lanterns
	{ template = "Tier4", minRebirths = 6 }, -- marble columns with gold rails
	{ template = "Tier5", minPrestiges = 1 }, -- glass and crystal with neon accents
} :: { Tier }

-- The index in Tiers a player with these rebirths and Prestiges has reached.
function penStyleData.getTier(rebirths: number, prestiges: number): number
	local current = 1
	for index, tier in penStyleData.Tiers do
		local byRebirths = tier.minRebirths ~= nil and rebirths >= tier.minRebirths
		local byPrestiges = tier.minPrestiges ~= nil and prestiges >= tier.minPrestiges
		if byRebirths or byPrestiges then
			current = index
		end
	end
	return current
end

return penStyleData
