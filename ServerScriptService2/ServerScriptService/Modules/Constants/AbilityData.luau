--!strict

--[[
	Every ability's duration, cooldown, speed boost and spin-hitbox stats.
	Location: ServerScriptService.Modules.Constants.AbilityData
]]--

export type AbilityInfo = {
	id: string, -- matches the Animation's name in ReplicatedStorage.Assets.Animations.Abilities
	duration: number, -- seconds the ability lasts
	cooldown: number, -- seconds from the ability ending until it can be used again
	speedMultiplier: number, -- walk speed is multiplied by this while active
	hitInterval: number, -- seconds between hits on every sheep in range
	rangeMultiplier: number, -- times the equipped shear's range
	damageMultiplier: number, -- times the equipped shear's damage, per hit
}

local abilityData = {}

abilityData.DefaultAbilityId = "Spin"

abilityData.Abilities = {
	Spin = {
		id = "Spin",
		duration = 3,
		cooldown = 10,
		speedMultiplier = 1.75,
		hitInterval = 0.1,
		rangeMultiplier = 1.5,
		damageMultiplier = 1,
	},
} :: { [string]: AbilityInfo }

function abilityData.get(id: any): AbilityInfo?
	return if type(id) == "string" then abilityData.Abilities[id] else nil
end

return abilityData
