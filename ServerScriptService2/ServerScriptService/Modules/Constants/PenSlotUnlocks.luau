--!strict

--[[
	What each rebirth unlocks on a player's plot.

	Each row applies from its `rebirths` count onwards, until a later row replaces it.
	slots:  how many pen slots the player can use in total
	builds: names of models in the plot that fade in and plop into place (they stay afterwards)

	Location: ServerScriptService.Modules.Constants.PenSlotUnlocks
]]--

export type Unlock = {
	rebirths: number,
	slots: number,
	builds: { string },
}

local UNLOCKS: { Unlock } = {
	{ rebirths = 0, slots = 2, builds = {} },
	{ rebirths = 1, slots = 3, builds = {} },
	{ rebirths = 2, slots = 4, builds = {} },
	{ rebirths = 3, slots = 5, builds = {} },
	{ rebirths = 4, slots = 6, builds = {} },
}

-- Rebirths needed to unlock each slot number, built once from UNLOCKS.
local unlockRebirthBySlot: { [number]: number } = {}
for _, unlock in UNLOCKS do
	for slot = 1, unlock.slots do
		if not unlockRebirthBySlot[slot] or unlock.rebirths < unlockRebirthBySlot[slot] then
			unlockRebirthBySlot[slot] = unlock.rebirths
		end
	end
end

local PenSlotUnlocks = {}

-- Rebirths a player needs before this slot can be used; nil if no rebirth ever unlocks it.
function PenSlotUnlocks.getUnlockRebirth(slotNumber: number): number?
	return unlockRebirthBySlot[slotNumber]
end

function PenSlotUnlocks.getSlotLimit(rebirths: number): number
	local slots = 0
	for _, unlock in UNLOCKS do
		if rebirths >= unlock.rebirths then
			slots = unlock.slots
		end
	end
	return slots
end

function PenSlotUnlocks.getMaxSlots(): number
	return UNLOCKS[#UNLOCKS].slots
end

-- Every build named in the table, mapped to whether this many rebirths has unlocked it.
function PenSlotUnlocks.getBuildStates(rebirths: number): { [string]: boolean }
	local states = {}
	for _, unlock in UNLOCKS do
		for _, build in unlock.builds do
			states[build] = rebirths >= unlock.rebirths
		end
	end
	return states
end

return PenSlotUnlocks
