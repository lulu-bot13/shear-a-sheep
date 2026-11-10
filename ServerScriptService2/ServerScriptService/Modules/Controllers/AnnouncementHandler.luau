--!strict

--[[
	Server-wide announcements: best finds, Legendary+ ability rolls, rebirths, Prestiges, gifts, Server Luck, Reapers and the King Sheep.
	Only names and numbers are sent; AnnouncementClient builds the chat lines and the best-find panel.

	Location: ServerScriptService.Modules.Controllers.AnnouncementHandler
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local AbilityData = require(script.Parent.Parent.Constants.AbilityData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)

--// Configs
local MIN_BEST_FIND_ODDS = 1000 -- only best finds at base odds of 1 in this or rarer are announced (Legendary and up)
local ANNOUNCED_ABILITY_RARITIES = { Legendary = true, Mythic = true }

export type Announcement = {
	kind: "BestFind",
	userName: string,
	sheepName: string,
	sheepColor: Color3,
	oddsText: string, -- e.g. "1 in 2.1k"
} | {
	kind: "AbilityRoll",
	userName: string,
	abilityName: string,
	rarity: string,
	rarityColor: Color3,
} | {
	kind: "Rebirth" | "Prestige",
	userName: string,
	previous: number,
	new: number,
} | {
	kind: "Gift",
	userName: string,
	itemName: string,
	robuxCost: number,
	recipientName: string,
} | {
	kind: "ServerLuck",
	userName: string,
	multiplier: number,
	minutes: number,
} | {
	kind: "ReaperRaid" | "WorldBossEscaped",
} | {
	kind: "WorldBossPending",
	seconds: number, -- until it arrives
} | {
	kind: "WorldBossSpawn",
	seconds: number?, -- to shear it before it escapes
	introSeconds: number?, -- the arrival cutscene, before the fight starts
} | {
	kind: "ReaperDefeated",
	userName: string,
} | {
	kind: "WorldBossDefeated",
	topUserName: string?, -- the top contributor, nil if they left
	topDisplayName: string?,
	shearers: number?, -- players rewarded
}

local AnnouncementHandler = {}

local function announce(announcement: Announcement)
	network.fireAllClients(network.RemoteEvents.ServerAnnouncement, announcement)
end

--// Public API ------------------------------------------------------------------

-- Announces a new best find, but only when the sheep is rare enough (MIN_BEST_FIND_ODDS at base odds).
function AnnouncementHandler.bestFind(player: Player, sheepType: string)
	local info = SheepData.Sheep[sheepType]
	local odds = SheepData.getOdds(sheepType, 0, 0, 0)
	if not info or not odds or odds < MIN_BEST_FIND_ODDS then
		return
	end

	announce({
		kind = "BestFind",
		userName = player.Name,
		sheepName = info.name,
		sheepColor = info.color,
		oddsText = `1 in {numberFormatter:Format(odds, 1) or odds}`,
	})
end

-- Announces an Ability Shack roll, but only a Legendary or Mythic one.
function AnnouncementHandler.abilityRoll(player: Player, abilityId: string)
	local ability = AbilityData.get(abilityId)
	if not ability or not ANNOUNCED_ABILITY_RARITIES[ability.rarity] then
		return
	end

	announce({
		kind = "AbilityRoll",
		userName = player.Name,
		abilityName = ability.name,
		rarity = ability.rarity,
		rarityColor = SheepData.RarityColors[ability.rarity] or SheepData.RarityColors.Common,
	})
end

function AnnouncementHandler.rebirth(player: Player, previous: number, new: number)
	if new > previous then
		announce({ kind = "Rebirth", userName = player.Name, previous = previous, new = new })
	end
end

function AnnouncementHandler.prestige(player: Player, previous: number, new: number)
	if new > previous then
		announce({ kind = "Prestige", userName = player.Name, previous = previous, new = new })
	end
end

-- The Night event's King Reaper has risen in every farm.
function AnnouncementHandler.reaperRaid()
	announce({ kind = "ReaperRaid" })
end

-- The player sheared their King Reaper bare: a chat line for the server and a toast for them.
function AnnouncementHandler.reaperDefeated(player: Player)
	announce({ kind = "ReaperDefeated", userName = player.Name })
	network.fireClient(network.RemoteEvents.ShowAlert, player, "You defeated the King Reaper!", "success")
end

-- The King Sheep world boss: warned 30 s ahead, arrived, defeated (naming the top contributor) or escaped.
function AnnouncementHandler.worldBossPending(seconds: number)
	announce({ kind = "WorldBossPending", seconds = math.ceil(seconds) })
end

function AnnouncementHandler.worldBossSpawn(seconds: number?, introSeconds: number?)
	announce({ kind = "WorldBossSpawn", seconds = seconds, introSeconds = introSeconds })
end

function AnnouncementHandler.worldBossDefeated(topPlayer: Player?, shearers: number?)
	announce({
		kind = "WorldBossDefeated",
		topUserName = if topPlayer then topPlayer.Name else nil,
		topDisplayName = if topPlayer then topPlayer.DisplayName else nil,
		shearers = shearers,
	})
end

function AnnouncementHandler.worldBossEscaped()
	announce({ kind = "WorldBossEscaped" })
end

-- Called by GiftService once a gift purchase is granted; the recipient may have left by then, so it can be just their name.
function AnnouncementHandler.gift(gifter: Player, itemName: string, robuxCost: number, recipient: Player | string)
	announce({
		kind = "Gift",
		userName = gifter.Name,
		itemName = itemName,
		robuxCost = math.max(math.floor(robuxCost), 0),
		recipientName = if typeof(recipient) == "Instance" then recipient.Name else recipient,
	})
end

-- Someone bought Server Luck: everyone here gets the boost.
function AnnouncementHandler.serverLuck(player: Player, multiplier: number, minutes: number)
	announce({ kind = "ServerLuck", userName = player.Name, multiplier = multiplier, minutes = minutes })
end

return AnnouncementHandler
