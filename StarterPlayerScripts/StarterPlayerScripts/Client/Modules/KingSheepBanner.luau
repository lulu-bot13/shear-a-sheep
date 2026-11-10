--!strict

--[[
	The King Sheep's on-screen announcements: an animated royal ribbon for its warning, arrival, defeat and escape.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.KingSheepBanner
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Modules
local cutscene = require(script.Parent.KingSheepCutscene)
local rewardPopup = require(script.Parent.KingSheepRewardPopup)

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

--// Configs
local DISPLAY_ORDER = 150 -- over the best-find plaque (100), under owner banners (200) and the cutscene (250)
local AT_ATTRIBUTE = "WorldBossAt" -- WorldBossHandler: when the Pending King arrives
local CUTSCENE_WAIT = 8 -- seconds a banner waits for a cutscene to finish before showing anyway
local CUTSCENE_SETTLE = 0.15 -- seconds an arrival/defeat banner gives its cutscene to start first
local POPUP_SETTLE = 0.4 -- after the cutscene, time for the reward popup to open
local POPUP_WAIT = 25 -- the most a defeat banner waits behind an open reward popup
local TICK_SECONDS = 0.2
local TEXT_FONT = Enum.Font.FredokaOne
local INK = Color3.fromRGB(34, 14, 2)
local SOFT_WHITE = Color3.fromRGB(240, 236, 250)
local GOLD = Color3.fromRGB(255, 208, 70)
local GOLD_LIGHT = Color3.fromRGB(255, 246, 200)
local POP = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local QUICK_OUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BANNER_POSITION = UDim2.fromScale(0.5, 0.2)
local BANNER_EXIT_POSITION = UDim2.fromScale(0.5, 0.14)

export type Kind = "Pending" | "Spawn" | "Defeated" | "Escaped"

export type Info = {
	seconds: number?, -- Pending: until it arrives; Spawn: to shear it
	topName: string?, -- Defeated: the top shearer
	shearers: number?, -- Defeated: players rewarded
}

type Theme = {
	kicker: string,
	title: string,
	top: Color3,
	bottom: Color3,
	accent: Color3,
	titleTop: Color3,
	titleBottom: Color3,
	hold: number,
	sound: string?,
	waitForCutscene: boolean,
}

local THEMES: { [Kind]: Theme } = {
	Pending = {
		kicker = "W A R N I N G",
		title = "THE KING SHEEP APPROACHES!",
		top = Color3.fromRGB(156, 32, 30),
		bottom = Color3.fromRGB(62, 10, 16),
		accent = Color3.fromRGB(255, 100, 74),
		titleTop = Color3.fromRGB(255, 244, 180),
		titleBottom = Color3.fromRGB(255, 142, 60),
		hold = 6,
		sound = "Alert",
		waitForCutscene = false,
	},
	Spawn = {
		kicker = "W O R L D   B O S S",
		title = "THE KING SHEEP HAS ARRIVED!",
		top = Color3.fromRGB(100, 48, 162),
		bottom = Color3.fromRGB(36, 14, 68),
		accent = GOLD,
		titleTop = GOLD_LIGHT,
		titleBottom = GOLD,
		hold = 5,
		sound = "Alert",
		waitForCutscene = true,
	},
	Defeated = {
		kicker = "V I C T O R Y",
		title = "THE KING SHEEP IS DEFEATED!",
		top = Color3.fromRGB(184, 126, 22),
		bottom = Color3.fromRGB(88, 48, 6),
		accent = Color3.fromRGB(255, 238, 160),
		titleTop = Color3.fromRGB(255, 255, 255),
		titleBottom = Color3.fromRGB(255, 224, 110),
		hold = 5.5,
		sound = "Rebirthed",
		waitForCutscene = true,
	},
	Escaped = {
		kicker = "T O O   S L O W",
		title = "THE KING SHEEP ESCAPED...",
		top = Color3.fromRGB(66, 70, 90),
		bottom = Color3.fromRGB(24, 26, 36),
		accent = Color3.fromRGB(255, 159, 67),
		titleTop = Color3.fromRGB(236, 236, 246),
		titleBottom = Color3.fromRGB(160, 166, 188),
		hold = 4.5,
		sound = nil,
		waitForCutscene = false,
	},
}

--// State
local token = 0
local currentBanner: Frame? = nil

local KingSheepBanner = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KingSheepBanner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

--// Helpers ------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = tweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function newFrame(name: string, parent: Instance, color: Color3, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.ZIndex = zIndex
	frame.Parent = parent
	return frame
end

local function newLabel(name: string, parent: Instance, text: string, color: Color3, zIndex: number, strokeThickness: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = TEXT_FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.ZIndex = zIndex
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = strokeThickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return label
end

local function addCorner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function getSubtitle(kind: Kind, info: Info): string
	if kind == "Pending" then
		local at = workspace:GetAttribute(AT_ATTRIBUTE)
		local left = if type(at) == "number" then at - workspace:GetServerTimeNow() else info.seconds or 30
		return `Arrives at the plaza in {formatTime(left)}!`
	elseif kind == "Spawn" then
		return if info.seconds
			then `Shear it together at the plaza! {formatTime(info.seconds)} before it escapes`
			else "Shear it together at the plaza before it escapes!"
	elseif kind == "Defeated" then
		local shearers = if info.shearers and info.shearers > 0 then `  |  {info.shearers} shearer{if info.shearers == 1 then "" else "s"} rewarded` else ""
		return if info.topName then `Top shearer: {info.topName}{shearers}` else `The flock wins!{shearers}`
	end
	return "It will be back... be ready!"
end

-- Fades every piece of the banner out (or quickly, when another banner is taking its place).
local function hide(banner: Frame, info: TweenInfo)
	for _, descendant in banner:GetDescendants() do
		if descendant:IsA("TextLabel") then
			tween(descendant, info, { TextTransparency = 1 })
		elseif descendant:IsA("Frame") then
			tween(descendant, info, { BackgroundTransparency = 1 })
		elseif descendant:IsA("UIStroke") then
			tween(descendant, info, { Transparency = 1 })
		end
	end
	tween(banner, info, { Position = BANNER_EXIT_POSITION })
	task.delay(info.Time + 0.05, function()
		banner:Destroy()
	end)
end

--// Building ---------------------------------------------------------------------------

local function build(theme: Theme): (Frame, UIScale, TextLabel, TextLabel, Frame, UIStroke)
	local banner = Instance.new("Frame")
	banner.Name = "KingSheepBanner"
	banner.BackgroundTransparency = 1
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = BANNER_POSITION
	banner.Size = UDim2.fromScale(0.5, 0.16)
	banner.Parent = screenGui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 4.4
	aspect.Parent = banner
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(330, 75)
	sizeConstraint.MaxSize = Vector2.new(780, 177)
	sizeConstraint.Parent = banner
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = banner

	-- Ribbon tails tucked behind each end.
	for index, x in { -0.035, 1.035 } do
		local tail = newFrame(`Tail{index}`, banner, theme.bottom, 1)
		tail.AnchorPoint = Vector2.new(0.5, 0.5)
		tail.Position = UDim2.fromScale(x, 0.62)
		tail.Size = UDim2.fromScale(0.11, 0.66)
		addCorner(tail, UDim.new(0.15, 0))
		local tailStroke = Instance.new("UIStroke")
		tailStroke.Color = theme.accent
		tailStroke.Thickness = 2
		tailStroke.Transparency = 0.4
		tailStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tailStroke.Parent = tail
	end

	local plate = newFrame("Plate", banner, Color3.new(1, 1, 1), 2)
	plate.Size = UDim2.fromScale(1, 1)
	addCorner(plate, UDim.new(0.2, 0))
	local plateGradient = Instance.new("UIGradient")
	plateGradient.Color = ColorSequence.new(theme.top, theme.bottom)
	plateGradient.Rotation = 90
	plateGradient.Parent = plate
	local border = Instance.new("UIStroke")
	border.Color = Color3.new(1, 1, 1)
	border.Thickness = 3
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = plate
	local borderGradient = Instance.new("UIGradient")
	borderGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, theme.accent),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, theme.accent),
	})
	borderGradient.Parent = border
	tween(borderGradient, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })

	-- A soft gloss on the top half.
	local gloss = newFrame("Gloss", banner, Color3.new(1, 1, 1), 3)
	gloss.Size = UDim2.fromScale(1, 0.48)
	gloss.BackgroundTransparency = 0.82
	addCorner(gloss, UDim.new(0.4, 0))
	local glossGradient = Instance.new("UIGradient")
	glossGradient.Rotation = 90
	glossGradient.Transparency = NumberSequence.new(0, 1)
	glossGradient.Parent = gloss

	-- A bright band that sweeps across now and then.
	local shine = newFrame("Shine", banner, Color3.new(1, 1, 1), 4)
	shine.Size = UDim2.fromScale(1, 1)
	shine.BackgroundTransparency = 0.35
	addCorner(shine, UDim.new(0.2, 0))
	local shineGradient = Instance.new("UIGradient")
	shineGradient.Rotation = 20
	shineGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	shineGradient.Offset = Vector2.new(-1, 0)
	shineGradient.Parent = shine
	tween(shineGradient, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.8), { Offset = Vector2.new(1, 0) })

	-- A white flash over everything as it lands.
	local flash = newFrame("Flash", banner, Color3.new(1, 1, 1), 8)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 0.15
	addCorner(flash, UDim.new(0.2, 0))

	-- Spinning gems at each end.
	for index, x in { 0.065, 0.935 } do
		local gem = newFrame(`Gem{index}`, banner, theme.accent, 5)
		gem.AnchorPoint = Vector2.new(0.5, 0.5)
		gem.Position = UDim2.fromScale(x, 0.5)
		gem.Size = UDim2.fromScale(0.3, 0.3)
		gem.SizeConstraint = Enum.SizeConstraint.RelativeYY
		gem.Rotation = 45
		local gemStroke = Instance.new("UIStroke")
		gemStroke.Color = INK
		gemStroke.Thickness = 2
		gemStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		gemStroke.Parent = gem
		local core = newFrame("Core", gem, Color3.new(1, 1, 1), 6)
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Position = UDim2.fromScale(0.5, 0.5)
		core.Size = UDim2.fromScale(0.4, 0.4)
		core.BackgroundTransparency = 0.2
		tween(gem, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			Rotation = if index == 1 then 405 else -315,
		})
	end

	local kicker = newLabel("Kicker", banner, theme.kicker, theme.accent, 6, 2)
	kicker.Position = UDim2.fromScale(0.5, 0.17)
	kicker.Size = UDim2.fromScale(0.42, 0.2)

	local titleLabel = newLabel("Title", banner, theme.title, Color3.new(1, 1, 1), 6, 3)
	titleLabel.Position = UDim2.fromScale(0.5, 0.5)
	titleLabel.Size = UDim2.fromScale(0.78, 0.42)
	titleLabel.MaxVisibleGraphemes = 0
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Color = ColorSequence.new(theme.titleTop, theme.titleBottom)
	titleGradient.Rotation = 90
	titleGradient.Parent = titleLabel

	local subtitle = newLabel("Subtitle", banner, "", SOFT_WHITE, 6, 2)
	subtitle.Position = UDim2.fromScale(0.5, 0.83)
	subtitle.Size = UDim2.fromScale(0.72, 0.2)

	return banner, scale, titleLabel, subtitle, flash, border
end

--// Public API ------------------------------------------------------------------

-- Shows the banner for `kind`, replacing any King Sheep banner already up; arrival and defeat wait out a cutscene first.
function KingSheepBanner.show(kind: Kind, info: Info)
	local theme = THEMES[kind]
	if not theme then
		return
	end
	token += 1
	local myToken = token

	task.spawn(function()
		if theme.waitForCutscene then
			task.wait(CUTSCENE_SETTLE) -- its cutscene arrives on another remote
			if cutscene.isPlaying() then
				cutscene.waitUntilDone(CUTSCENE_WAIT)
				task.wait(POPUP_SETTLE)
			end
			-- A participant reads their reward first; the banner follows once it's claimed.
			local giveUpAt = os.clock() + POPUP_WAIT
			while rewardPopup.isOpen() and os.clock() < giveUpAt and token == myToken do
				task.wait(TICK_SECONDS)
			end
		end
		if token ~= myToken then
			return
		end
		local previous = currentBanner
		if previous and previous.Parent then
			hide(previous, QUICK_OUT)
		end

		local banner, scale, titleLabel, subtitle, flash, border = build(theme)
		currentBanner = banner
		subtitle.Text = getSubtitle(kind, info)
		banner.Rotation = -5

		tween(scale, POP, { Scale = 1 })
		tween(banner, POP, { Rotation = 0 })
		tween(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
		local reveal = Instance.new("NumberValue")
		reveal.Changed:Connect(function(value: number)
			titleLabel.MaxVisibleGraphemes = math.floor(value + 0.5)
		end)
		local typing = tween(reveal, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.12), {
			Value = utf8.len(theme.title) or #theme.title,
		})
		typing.Completed:Once(function()
			titleLabel.MaxVisibleGraphemes = -1
			reveal:Destroy()
		end)
		if kind == "Pending" then
			tween(border, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
		end
		if theme.sound then
			cutscene.playSound("UISounds", theme.sound)
		end

		local hideAt = os.clock() + POP.Time + theme.hold
		while os.clock() < hideAt and token == myToken and banner.Parent do
			if kind == "Pending" then
				subtitle.Text = getSubtitle(kind, info)
			end
			task.wait(TICK_SECONDS)
		end
		if token == myToken and banner.Parent then
			hide(banner, OUT)
			currentBanner = nil
		end
	end)
end

return KingSheepBanner
