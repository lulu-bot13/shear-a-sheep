--[[
	Server-wide announcements from AnnouncementHandler: a coloured chat line for rare best finds, rebirths, Prestiges and gifts.
	Rare best finds also pop up a metal plaque at the top of the screen, one at a time.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AnnouncementClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")
local textChatService = game:GetService("TextChatService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Sounds
local uiSounds = soundService:FindFirstChild("UISounds")
local bestFindSound = if uiSounds then uiSounds:FindFirstChild("UnlockedSheep") :: Sound? else nil

--// Configs
local CHANNEL_WAIT_SECONDS = 10
local SOFT_WHITE = "#E6E6E6" -- the plain words between the highlighted ones
local NAME_COLOR = "#FFFFFF"
local REBIRTH_FROM_COLOR = "#8FD3FF"
local REBIRTH_TO_COLOR = "#B79CFF"
local PRESTIGE_NAME_COLOR = "#FFD54A"
local PRESTIGE_NUMBER_COLOR = "#FFB300"
local GIFT_NAME_COLOR = "#FF8AD8"
local GIFT_ITEM_COLOR = "#7CF0FF"
local ROBUX_COLOR = "#3DDC84"
local ROBUX_GLYPH = "\u{E002}"
local ARROW = "-&gt;" -- escaped, since it sits inside rich text

local MAX_QUEUED = 5 -- the oldest waiting plaque is dropped past this
local POP_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 4
local START_SCALE = 0.4
local PANEL_POSITION = UDim2.fromScale(0.5, 0.1)
local PANEL_EXIT_POSITION = UDim2.new(0.5, 0, 0.1, -40)
local PANEL_SIZE = UDim2.fromScale(0.36, 0.14)
local PANEL_ASPECT = 4.2
local PANEL_MIN_SIZE = Vector2.new(280, 66) -- keeps it readable on small phones
local PLATE_TOP_COLOR = Color3.fromRGB(214, 214, 214)
local PLATE_BOTTOM_COLOR = Color3.fromRGB(180, 180, 180)
local BORDER_COLOR = Color3.fromRGB(42, 42, 42)
local BORDER_THICKNESS = 4
local SCREW_COLOR = Color3.fromRGB(58, 58, 58)
local SCREW_HIGHLIGHT_COLOR = Color3.fromRGB(122, 122, 122)
local SCREW_SIZE = 0.13 -- of the plaque's height
local SCREW_INSET = Vector2.new(0.018, 0.1)
local TEXT_FONT = Enum.Font.FredokaOne

type Announcement = {
	kind: "BestFind",
	userName: string,
	sheepName: string,
	sheepColor: Color3,
	oddsText: string,
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
}

type BestFind = {
	userName: string,
	sheepName: string,
	sheepColor: Color3,
	oddsText: string,
}

--// State
local channel: TextChannel? = nil
local queue: { BestFind } = {}
local playing = false

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BestFindAnnouncement"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

--// Chat ------------------------------------------------------------------------------

-- Usernames and item names go into rich text, so their markup characters are escaped.
local function escape(text: string): string
	return (
		text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
	)
end

local function paint(text: string, color: string, bold: boolean?): string
	local painted = `<font color="{color}">{text}</font>`
	return if bold then `<b>{painted}</b>` else painted
end

local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

-- RBXSystem when it exists, otherwise RBXGeneral; nil under legacy chat.
local function getChannel(): TextChannel?
	if channel then
		return channel
	end

	local channels = textChatService:WaitForChild("TextChannels", CHANNEL_WAIT_SECONDS)
	local found = channels and (channels:FindFirstChild("RBXSystem") or channels:WaitForChild("RBXGeneral", CHANNEL_WAIT_SECONDS))
	if found and found:IsA("TextChannel") then
		channel = found
	end
	return channel
end

local function getChatLine(announcement: Announcement): string
	local userName = escape(announcement.userName)

	if announcement.kind == "BestFind" then
		local sheepColor = `#{announcement.sheepColor:ToHex()}`
		return `{paint(userName, NAME_COLOR, true)} {paint("discovered their new best find:", SOFT_WHITE)} `
			.. `{paint(escape(announcement.sheepName), sheepColor, true)} {paint(`({escape(announcement.oddsText)})`, sheepColor)}`
	elseif announcement.kind == "Rebirth" then
		return `{paint(userName, NAME_COLOR, true)} {paint("has rebirthed", SOFT_WHITE)} `
			.. `{paint(`[{formatWithCommas(announcement.previous)}]`, REBIRTH_FROM_COLOR, true)} {paint(ARROW, SOFT_WHITE)} `
			.. paint(`[{formatWithCommas(announcement.new)}]`, REBIRTH_TO_COLOR, true)
	elseif announcement.kind == "Prestige" then
		return `{paint(userName, PRESTIGE_NAME_COLOR, true)} {paint("has prestiged", PRESTIGE_NAME_COLOR)} `
			.. `{paint(`[{formatWithCommas(announcement.previous)}]`, PRESTIGE_NUMBER_COLOR, true)} {paint(ARROW, PRESTIGE_NAME_COLOR)} `
			.. paint(`[{formatWithCommas(announcement.new)}]`, PRESTIGE_NUMBER_COLOR, true)
	else
		return `{paint(userName, GIFT_NAME_COLOR, true)} {paint("gifted", SOFT_WHITE)} `
			.. `{paint(escape(announcement.itemName), GIFT_ITEM_COLOR, true)} `
			.. `{paint(`({ROBUX_GLYPH}{formatWithCommas(announcement.robuxCost)})`, ROBUX_COLOR, true)} `
			.. `{paint("to", SOFT_WHITE)} {paint(escape(announcement.recipientName), GIFT_NAME_COLOR, true)}`
	end
end

--// Best find plaque ----------------------------------------------------------------

local function addCorner(parent: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function addTextStroke(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Parent = label
end

local function newLabel(name: string, text: string, color: Color3, size: UDim2, position: UDim2, parent: GuiObject): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = TEXT_FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true -- long usernames wrap instead of shrinking to one tiny line
	label.Parent = parent
	return label
end

-- A dark screw head with a lighter glint, tucked into one corner (`corner` is 0 or 1 on each axis).
local function addScrew(panel: Frame, corner: Vector2)
	local screw = Instance.new("Frame")
	screw.Name = "Screw"
	screw.AnchorPoint = corner
	screw.Position = UDim2.fromScale(
		if corner.X == 0 then SCREW_INSET.X else 1 - SCREW_INSET.X,
		if corner.Y == 0 then SCREW_INSET.Y else 1 - SCREW_INSET.Y
	)
	screw.Size = UDim2.fromScale(SCREW_SIZE, SCREW_SIZE)
	screw.SizeConstraint = Enum.SizeConstraint.RelativeYY
	screw.BackgroundColor3 = SCREW_COLOR
	screw.BorderSizePixel = 0
	addCorner(screw, UDim.new(1, 0))
	screw.Parent = panel

	local glint = Instance.new("Frame")
	glint.Name = "Glint"
	glint.Position = UDim2.fromScale(0.2, 0.2)
	glint.Size = UDim2.fromScale(0.4, 0.4)
	glint.BackgroundColor3 = SCREW_HIGHLIGHT_COLOR
	glint.BorderSizePixel = 0
	addCorner(glint, UDim.new(1, 0))
	glint.Parent = screw
end

local function buildPanel(find: BestFind): (Frame, UIScale)
	local panel = Instance.new("Frame")
	panel.Name = "BestFind"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = PANEL_POSITION
	panel.Size = PANEL_SIZE
	panel.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient gives the plate its colour
	panel.BorderSizePixel = 0
	addCorner(panel, UDim.new(0, 10))

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(PLATE_TOP_COLOR, PLATE_BOTTOM_COLOR)
	gradient.Rotation = 90
	gradient.Parent = panel

	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = BORDER_COLOR
	border.Thickness = BORDER_THICKNESS
	border.Parent = panel

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = PANEL_ASPECT
	aspect.Parent = panel

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = PANEL_MIN_SIZE
	sizeConstraint.Parent = panel

	local scale = Instance.new("UIScale")
	scale.Scale = START_SCALE
	scale.Parent = panel

	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		addScrew(panel, corner)
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(0.86, 0.78)
	content.BackgroundTransparency = 1
	content.Parent = panel

	local header = newLabel("Header", `{find.userName} discovered their new best find:`, Color3.new(1, 1, 1),
		UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0), content)
	addTextStroke(header, 2)

	local sheepLine = newLabel("Sheep", `{find.sheepName} ({find.oddsText})`, find.sheepColor,
		UDim2.fromScale(1, 0.58), UDim2.fromScale(0, 0.42), content)
	addTextStroke(sheepLine, 2.5)

	return panel, scale
end

-- Slides the plaque up while everything in it fades out.
local function slideOut(panel: Frame): Tween
	local fadeTargets: { [Instance]: { [string]: number } } = { [panel] = { BackgroundTransparency = 1 } }
	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("TextLabel") then
			fadeTargets[descendant] = { TextTransparency = 1 }
		elseif descendant:IsA("Frame") then
			fadeTargets[descendant] = { BackgroundTransparency = 1 }
		elseif descendant:IsA("UIStroke") then
			fadeTargets[descendant] = { Transparency = 1 }
		end
	end
	for instance, goal in fadeTargets do
		tweenService:Create(instance, SLIDE_OUT, goal):Play()
	end

	local slide = tweenService:Create(panel, SLIDE_OUT, { Position = PANEL_EXIT_POSITION })
	slide:Play()
	return slide
end

local function play(find: BestFind)
	local panel, scale = buildPanel(find)
	panel.Parent = screenGui
	-- The finder already hears their own unlock sound.
	if bestFindSound and find.userName ~= player.Name then
		bestFindSound:Play()
	end

	tweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
	task.wait(POP_IN.Time + HOLD_SECONDS)
	slideOut(panel).Completed:Wait()
	panel:Destroy()
end

local function playQueue()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		play(table.remove(queue, 1) :: BestFind)
	end
	playing = false
end

--// Setup -------------------------------------------------------------------------------

local function onAnnouncement(announcement: Announcement)
	if type(announcement) ~= "table" then
		return
	end

	if announcement.kind == "BestFind" then
		if #queue >= MAX_QUEUED then
			table.remove(queue, 1)
		end
		table.insert(queue, {
			userName = announcement.userName,
			sheepName = announcement.sheepName,
			sheepColor = announcement.sheepColor,
			oddsText = announcement.oddsText,
		})
		task.spawn(playQueue)
	end

	local textChannel = getChannel()
	if textChannel then
		textChannel:DisplaySystemMessage(getChatLine(announcement))
	end
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ServerAnnouncement, onAnnouncement)
