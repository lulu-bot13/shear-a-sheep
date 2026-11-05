--!strict

--[[
	/announce <message> chat command: filters the owner's message and shows it as a banner with their headshot in every server.
	Other servers get it through MessagingService; GlobalAnnouncementClient builds the banner.

	Location: ServerScriptService.Modules.Controllers.GlobalAnnouncementHandler
]]--

--// Services
local messagingService = game:GetService("MessagingService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local textService = game:GetService("TextService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)

--// Configs
local PRIMARY_ALIAS = "/announce"
local SECONDARY_ALIAS = "/ga"
local TOPIC = "GlobalAnnouncement"
local MAX_LENGTH = 200 -- characters; also keeps the MessagingService payload well under its 1KB limit
local COOLDOWN_SECONDS = 5
local SUBSCRIBE_ATTEMPTS = 5
local SUBSCRIBE_RETRY_SECONDS = 10

-- Checked top to bottom; the first role a speaker has is the title on their banner. Add a role here to let it announce
-- (its `has` check must also pass AdminCommands.isAdmin, since only admins can trigger the command).
local ROLES: { { title: string, color: string, has: (Player) -> boolean } } = {
	{ title = "Owner", color = "#FFC83C", has = AdminCommands.isOwner },
}

export type GlobalAnnouncement = {
	userId: number,
	userName: string,
	title: string,
	titleColor: string, -- hex, so it survives MessagingService's JSON
	text: string,
}

type Envelope = {
	serverId: string,
	announcement: GlobalAnnouncement,
}

local GlobalAnnouncementHandler = {}

--// State
local lastSentAt: { [number]: number } = {}

--// Helpers ---------------------------------------------------------------------

local function getRole(player: Player)
	for _, role in ROLES do
		if role.has(player) then
			return role
		end
	end
	return nil
end

-- Cuts at a character boundary so a multi-byte character is never split.
local function truncate(text: string): string
	local cutAt = utf8.offset(text, MAX_LENGTH + 1)
	return if cutAt then string.sub(text, 1, cutAt - 1) else text
end

local function filter(speaker: Player, text: string): string?
	local success, result = pcall(function()
		local filtered = textService:FilterStringAsync(text, speaker.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not success then
		warn(`GlobalAnnouncementHandler: couldn't filter the message: {result}`)
		return nil
	end
	return result
end

local function isValid(announcement: any): boolean
	return type(announcement) == "table"
		and type(announcement.userId) == "number"
		and type(announcement.userName) == "string"
		and type(announcement.title) == "string"
		and type(announcement.titleColor) == "string"
		and type(announcement.text) == "string"
end

local function showHere(announcement: GlobalAnnouncement)
	network.fireAllClients(network.RemoteEvents.GlobalAnnouncement, announcement)
end

local function onMessage(message: { Data: any, Sent: number })
	local envelope = message.Data
	if type(envelope) ~= "table" or envelope.serverId == game.JobId or not isValid(envelope.announcement) then
		return -- this server already showed its own announcement
	end
	showHere(envelope.announcement)
end

local function subscribe()
	for _ = 1, SUBSCRIBE_ATTEMPTS do
		local success, result = pcall(messagingService.SubscribeAsync, messagingService, TOPIC, onMessage)
		if success then
			return
		end
		warn(`GlobalAnnouncementHandler: couldn't subscribe, retrying: {result}`)
		task.wait(SUBSCRIBE_RETRY_SECONDS)
	end
	warn("GlobalAnnouncementHandler: gave up subscribing; this server won't see other servers' announcements.")
end

--// Public API ------------------------------------------------------------------

-- Shows `text` from `speaker` in every server; false if they have no announcing role, are on cooldown, or it's empty.
function GlobalAnnouncementHandler.send(speaker: Player, text: string): boolean
	local role = getRole(speaker)
	if not role then
		return false
	end

	local now = os.clock()
	if now - (lastSentAt[speaker.UserId] or -math.huge) < COOLDOWN_SECONDS then
		warn(`GlobalAnnouncementHandler: wait {COOLDOWN_SECONDS}s between announcements.`)
		return false
	end

	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if trimmed == "" then
		return false
	end
	local filtered = filter(speaker, truncate(trimmed))
	if not filtered then
		return false
	end
	lastSentAt[speaker.UserId] = now

	local announcement: GlobalAnnouncement = {
		userId = speaker.UserId,
		userName = speaker.Name,
		title = role.title,
		titleColor = role.color,
		text = filtered,
	}
	showHere(announcement)

	task.spawn(function()
		local envelope: Envelope = { serverId = game.JobId, announcement = announcement }
		local success, result = pcall(messagingService.PublishAsync, messagingService, TOPIC, envelope)
		if not success then
			warn(`GlobalAnnouncementHandler: shown in this server only, couldn't reach the others: {result}`)
		end
	end)
	return true
end

local function onTriggered(speaker: Player, message: string)
	local text = string.match(message, "^%S+%s+(.+)$")
	if not text then
		warn(`GlobalAnnouncementHandler: usage is {PRIMARY_ALIAS} <message>`)
		return
	end
	GlobalAnnouncementHandler.send(speaker, text)
end

--// Lifecycle -----------------------------------------------------------------------

function GlobalAnnouncementHandler.Start()
	AdminCommands.register("GlobalAnnouncementCommand", PRIMARY_ALIAS, SECONDARY_ALIAS, onTriggered)
	task.spawn(subscribe)
end

return GlobalAnnouncementHandler
