--!strict

--[[
	Mutations rolled on every spawn: name prefix and colour, wool and Luck multipliers, and the VFX in Assets.VFX.Mutations.
	Location: ServerScriptService.Modules.Constants.MutationData
]]--

export type MutationInfo = {
	id: string, -- also the name prefix and the VFX folder/attachment in Assets.VFX.Mutations
	chance: number, -- 1 in this many spawns
	wool: number, -- WoolAmount multiplier
	luck: number, -- LuckAmount multiplier
	color: Color3, -- prefix colour on the unlock popup
	rainbowName: boolean?, -- the whole name cycles through the rainbow (MutationClient animates it)
	tailAttachments: { string }?, -- attachments moved to the sheep's tail instead of its middle
}

local mutationData = {}

-- Rolled rarest first, so the odds below are each mutation's own chance.
mutationData.Mutations = {
	{ id = "Galaxy",  chance = 400, wool = 2,    luck = 1.5,  color = Color3.fromRGB(167, 139, 250) },
	{ id = "Haunted", chance = 120, wool = 1.35, luck = 1.65, color = Color3.fromRGB(134, 239, 172) },
	{ id = "Rainbow", chance = 60,  wool = 1.4,  luck = 1.15, color = Color3.fromRGB(255, 255, 255), rainbowName = true,
		tailAttachments = { "RainbowTrailTop", "RainbowTrailBottom" } },
	{ id = "Shiny",   chance = 20,  wool = 1.25, luck = 1,    color = Color3.fromRGB(253, 230, 138) },
} :: { MutationInfo }

mutationData.Attribute = "Mutation"
mutationData.VfxAttribute = "MutationVFX" -- marks the cloned VFX so they come off when the model is pooled
mutationData.RainbowGradientTag = "RainbowName" -- MutationClient animates every UIGradient with this tag

local byId: { [string]: MutationInfo } = {}
for _, mutation in mutationData.Mutations do
	byId[mutation.id] = mutation
end

function mutationData.get(id: any): MutationInfo?
	return if type(id) == "string" then byId[id] else nil
end

-- A mutation, or nil for a plain sheep.
function mutationData.roll(random: Random): MutationInfo?
	for _, mutation in mutationData.Mutations do
		if random:NextInteger(1, mutation.chance) == 1 then
			return mutation
		end
	end
	return nil
end

return mutationData
