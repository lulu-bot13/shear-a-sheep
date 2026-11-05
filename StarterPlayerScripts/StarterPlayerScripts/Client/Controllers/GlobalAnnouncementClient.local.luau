--[[
	Banners from GlobalAnnouncementHandler: headshot, username and "Owner: message" at the very top of the screen, above every other announcement.
	They play one at a time and are copied into chat; the Server Announcements setting can't hide them.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.GlobalAnnouncementClient
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
local announceSound = if uiSounds then uiSounds:FindFirstChild("UnlockedSheep") :: Sound? else nil

--// Configs
local DISPLAY_ORDER = 200 -- above the best-find plaque (100) and the Alerts labels
local MAX_QUEUED = 5
local CHANNEL_WAIT_SECONDS = 10
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MIN_HOLD_SECONDS = 4
local MAX_HOLD_SECONDS = 10
local READ_CHARS_PER_SECOND = 15 -- longer messages stay up longer
local START_SCALE = 0.4

local PANEL_POSITION = UDim2.new(0.5, 0, 0, 8)
local PANEL_EXIT_POSITION = UDim2.new(0.5, 0, 0, -40)
local PANEL_SIZE = UDim2.fromScale(0.42, 0.14)
local PANEL_ASPECT = 4.6
local PANEL_MIN_SIZE = Vector2.new(300, 66) -- keeps it readable on small phones
local PLATE_TOP_COLOR = Color3.fromRGB(48, 44, 58)
local PLATE_BOTTOM_COLOR = Color3.fromRGB(24, 22, 30)
local BORDER_THICKNESS = 3
local AVATAR_SIZE = 0.8 -- of the banner's height
local AVATAR_INSET = 0.025
local TEXT_LEFT = 0.215 -- just right of the avatar
local NAME_MAX_TEXT_SIZE = 26
local MESSAGE_MAX_TEXT_SIZE = 34
local TEXT_FONT = Enum.Font.FredokaOne
local SOFT_WHITE = "#E6E6E6"
local NAME_COLOR = "#FFFFFF"

type GlobalAnnouncement = {
	userId: number,
	userName: string,
	title: string,
	titleColor: string,
	text: string,
}

--// State
local channel: TextChannel? = nil
local headshots: { [number]: string } = {}
local queue: { GlobalAnnouncement } = {}
local playing = false

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GlobalAnnouncement"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false -- sits just under the Roblox top bar
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

--// Helpers ---------------------------------------------------------------------

-- Usernames and messages go into rich text, so their markup characters are escaped.
local function escape(text: string): string
	return (
		text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;")
	)
end

local function paint(text: string, color: string, bold: boolean?): string
	local painted = `<font color="{color}">{text}</font>`
	return if bold then `<b>{painted}</b>` else painted
end

local function getHeadshot(userId: number): string?
	if not headshots[userId] then
		local success, result = pcall(players.GetUserThumbnailAsync, players, userId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		if success then
			headshots[userId] = result
		else
			warn(`GlobalAnnouncementClient: couldn't load headshot for {userId}: {result}`)
		end
	end
	return headshots[userId]
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

--// Banner ----------------------------------------------------------------------

local function addCorner(parent: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number, border: boolean?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	if border then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	stroke.Parent = parent
end

local function newLabel(name: string, size: UDim2, position: UDim2, maxTextSize: number, parent: GuiObject): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = TEXT_FONT
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextWrapped = true
	label.RichText = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	addStroke(label, Color3.new(0, 0, 0), 2)
	label.Parent = parent

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MaxTextSize = maxTextSize
	textSize.Parent = label
	return label
end

local function buildPanel(announcement: GlobalAnnouncement): (Frame, UIScale)
	local titleColor = Color3.fromHex(announcement.titleColor)

	local panel = Instance.new("Frame")
	panel.Name = "Banner"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = PANEL_POSITION
	panel.Size = PANEL_SIZE
	panel.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient gives the plate its colour
	panel.BorderSizePixel = 0
	addCorner(panel, UDim.new(0, 12))
	addStroke(panel, titleColor, BORDER_THICKNESS, true)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(PLATE_TOP_COLOR, PLATE_BOTTOM_COLOR)
	gradient.Rotation = 90
	gradient.Parent = panel

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = PANEL_ASPECT
	aspect.Parent = panel

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = PANEL_MIN_SIZE
	sizeConstraint.Parent = panel

	local scale = Instance.new("UIScale")
	scale.Scale = START_SCALE
	scale.Parent = panel

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.fromScale(AVATAR_INSET, 0.5)
	avatar.Size = UDim2.fromScale(AVATAR_SIZE, AVATAR_SIZE)
	avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
	avatar.BackgroundColor3 = PLATE_TOP_COLOR
	avatar.Image = headshots[announcement.userId] or ""
	addCorner(avatar, UDim.new(1, 0))
	addStroke(avatar, titleColor, 2, true)
	avatar.Parent = panel

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0, 0.5)
	content.Position = UDim2.fromScale(TEXT_LEFT, 0.5)
	content.Size = UDim2.fromScale(0.96 - TEXT_LEFT, 0.8)
	content.BackgroundTransparency = 1
	content.Parent = panel

	newLabel("Name", UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0), NAME_MAX_TEXT_SIZE, content).Text =
		paint(escape(announcement.userName), NAME_COLOR, true)

	newLabel("Message", UDim2.fromScale(1, 0.62), UDim2.fromScale(0, 0.38), MESSAGE_MAX_TEXT_SIZE, content).Text =
		`{paint(`{escape(announcement.title)}:`, announcement.titleColor, true)} {paint(escape(announcement.text), SOFT_WHITE)}`

	return panel, scale
end

-- Slides the banner up while everything in it fades out.
local function slideOut(panel: Frame): Tween
	local fadeTargets: { [Instance]: { [string]: number } } = { [panel] = { BackgroundTransparency = 1 } }
	for _, descendant in panel:GetDescendants() do
		if descendant:IsA("TextLabel") then
			fadeTargets[descendant] = { TextTransparency = 1 }
		elseif descendant:IsA("ImageLabel") then
			fadeTargets[descendant] = { ImageTransparency = 1, BackgroundTransparency = 1 }
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

local function play(announcement: GlobalAnnouncement)
	getHeadshot(announcement.userId)
	local panel, scale = buildPanel(announcement)
	panel.Parent = screenGui
	if announceSound then
		announceSound:Play()
	end

	local length = utf8.len(announcement.text) or #announcement.text
	local hold = math.clamp(length / READ_CHARS_PER_SECOND, MIN_HOLD_SECONDS, MAX_HOLD_SECONDS)
	tweenService:Create(scale, POP_IN, { Scale = 1 }):Play()
	task.wait(POP_IN.Time + hold)
	slideOut(panel).Completed:Wait()
	panel:Destroy()
end

local function playQueue()
	if playing then
		return
	end
	playing = true
	while #queue > 0 do
		play(table.remove(queue, 1) :: GlobalAnnouncement)
	end
	playing = false
end

--// Setup -------------------------------------------------------------------------------

local function onAnnouncement(announcement: GlobalAnnouncement)
	if type(announcement) ~= "table" or type(announcement.text) ~= "string" then
		return
	end

	if #queue >= MAX_QUEUED then
		table.remove(queue, 1)
	end
	table.insert(queue, announcement)
	task.spawn(playQueue)

	local textChannel = getChannel()
	if textChannel then
		textChannel:DisplaySystemMessage(
			`{paint(`[{escape(announcement.title)}]`, announcement.titleColor, true)} `
				.. `{paint(escape(announcement.userName), NAME_COLOR, true)}{paint(":", SOFT_WHITE)} `
				.. paint(escape(announcement.text), SOFT_WHITE)
		)
	end
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.GlobalAnnouncement, onAnnouncement)
