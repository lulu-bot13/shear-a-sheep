--!strict

--[[
	Server-wide announcements: tells every client about a rare best find, a rebirth, a Prestige, a gift or Server Luck.
	Only names and numbers are sent; AnnouncementClient builds the chat lines and the best-find panel.

	Location: ServerScriptService.Modules.Controllers.AnnouncementHandler
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local SheepData = require(script.Parent.Parent.Constants.SheepData)

--// Configs
local MIN_BEST_FIND_ODDS = 1000 -- only best finds at base odds of 1 in this or rarer are announced (Legendary and up)

export type Announcement = {
	kind: "BestFind",
	userName: string,
	sheepName: string,
	sheepColor: Color3,
	oddsText: string, -- e.g. "1 in 2.1k"
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
	kind: "ReaperRaid",
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
