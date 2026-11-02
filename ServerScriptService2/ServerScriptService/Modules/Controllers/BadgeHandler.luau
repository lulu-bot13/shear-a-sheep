--!strict

--[[
	Shear A Sheep's badges: Welcome on join, plus milestones on lifetime sheep sheared, the first rebirth and the first Prestige.
	BadgeAwarder does the awarding (once per session, ids still 0 skipped, checked on load and as each stat goes up).

	Location: ServerScriptService.Modules.Controllers.BadgeHandler
]]--

--// Modules
local BadgeAwarder = require(script.Parent.BadgeAwarder)

--// Configs
local TRUE_SHEARER_AMOUNT = 1000 -- lifetime sheep sheared for the True Shearer badge

local BadgeHandler = {}

BadgeHandler.Welcome = {
	alertText = "Welcome to Shear A Sheep",
	reward = {
		badge = 1296446897730551, -- PUT BADGE ID HERE (Welcome)
	},
}

-- Keyed by the PlayerDataHandler number each one watches.
BadgeHandler.Milestones = {
	SheepShearedCount = {
		[1] = {
			amount = TRUE_SHEARER_AMOUNT,
			alertText = "True Shearer",
			reward = {
				badge = 2384105509137077, -- PUT BADGE ID HERE (True Shearer)
			},
		},
	},
	Rebirths = {
		[1] = {
			amount = 1,
			alertText = "Rebirthed",
			reward = {
				badge = 367547750632448, -- PUT BADGE ID HERE (Rebirthed)
			},
		},
	},
	Prestiges = {
		[1] = {
			amount = 1,
			alertText = "Prestiged",
			reward = {
				badge = 3654679425481588, -- PUT BADGE ID HERE (Prestiged)
			},
		},
	},
} :: { [string]: { BadgeAwarder.Milestone } }

function BadgeHandler:_awardBadge(player: Player, badgeId: number): boolean
	return BadgeAwarder:_awardBadge(player, badgeId)
end

function BadgeHandler:_HasBadge(player: Player, badgeId: number): boolean
	return BadgeAwarder:_HasBadge(player, badgeId)
end

function BadgeHandler.CheckForMilestones(player: Player, statKey: string, value: number)
	BadgeAwarder.checkMilestones(player, BadgeHandler.Milestones[statKey] or {}, value)
end

--// Lifecycle ---------------------------------------------------------------------

function BadgeHandler.Setup()
	BadgeAwarder.awardOnLoad(BadgeHandler.Welcome)
	for statKey, milestones in BadgeHandler.Milestones do
		BadgeAwarder.trackStat(statKey, milestones)
	end
end

return BadgeHandler
