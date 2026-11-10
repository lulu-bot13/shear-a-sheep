--!strict

--[[
	The King Sheep reward popup: a dimmed, blurred screen and a royal card that counts up the server's exact numbers row by row.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.KingSheepRewardPopup
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local IconIds = require(replicatedStorage.Shared.Constants.IconIds)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local cutscene = require(script.Parent.KingSheepCutscene)
local settings = require(script.Parent.Settings)

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

--// Configs
local DISPLAY_ORDER = 300 -- over the cutscene bars (250) and every announcement
local AUTO_CLOSE_SECONDS = 15 -- after the last row lands
local BLUR_SIZE = 16
local DIM_TRANSPARENCY = 0.35
local RAYS_IMAGE = "rbxassetid://1164713030" -- the shine behind the Daily Rewards' day 7
local SHINE_TAG = "RotatingShine" -- ShineRotate spins it
local SHINE_SPEED_ATTRIBUTE = "ShineSpeed"
local FIRST_ROW_DELAY = 0.9
local ROW_STAGGER = 0.45
local COUNT_SECONDS = 0.8
local CONFETTI_PIECES = 46
local TEXT_FONT = Enum.Font.FredokaOne

local CARD_TOP = Color3.fromRGB(88, 44, 148)
local CARD_BOTTOM = Color3.fromRGB(34, 16, 64)
local GOLD = Color3.fromRGB(255, 208, 70)
local GOLD_LIGHT = Color3.fromRGB(255, 244, 196)
local GOLD_DARK = Color3.fromRGB(190, 118, 16)
local INK = Color3.fromRGB(40, 18, 4)
local SOFT_WHITE = Color3.fromRGB(236, 230, 255)
local WOOL_COLOR = Color3.fromRGB(255, 255, 255)
local LUCK_COLOR = Color3.fromRGB(110, 240, 140)
local GEM_COLOR = Color3.fromRGB(120, 220, 255)
local CLAIM_TOP = Color3.fromRGB(110, 230, 90)
local CLAIM_BOTTOM = Color3.fromRGB(38, 160, 52)
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 208, 70),
	Color3.fromRGB(255, 110, 180),
	Color3.fromRGB(110, 210, 255),
	Color3.fromRGB(130, 240, 140),
	Color3.fromRGB(255, 255, 255),
}

local POP = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local ROW_POP = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CLOSE = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In)

-- The exact numbers WorldBossHandler granted (its Reward type).
export type Reward = {
	damage: number,
	share: number,
	rank: number,
	shearers: number,
	wool: number,
	luck: number,
	gems: number,
	woolBonus: number,
	luckBonus: number,
	sheepName: string?,
	mutation: string?,
	mutationColor: Color3?,
}

type Row = {
	icon: string?,
	iconAspect: number?,
	name: string,
	value: number?, -- counted up; nil for a text-only row
	text: string?,
	color: Color3,
	bonus: number?,
	sound: string,
}

--// State
local current: { close: () -> () }? = nil
local random = Random.new()

local KingSheepRewardPopup = {}

--// Helpers ------------------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local created = tweenService:Create(instance, info, goal)
	created:Play()
	return created
end

local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

local function formatShort(value: number): string
	return if value < 1000 then formatWithCommas(value) else tostring(numberFormatter:Format(value, 1) or formatWithCommas(value))
end

local function addCorner(parent: Instance, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number, border: boolean?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	if border then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	stroke.Parent = parent
	return stroke
end

local function addGradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

local function newFrame(name: string, parent: Instance, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.Parent = parent
	return frame
end

local function newLabel(name: string, parent: Instance, text: string, color: Color3, strokeThickness: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = TEXT_FONT
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = parent
	if strokeThickness then
		addStroke(label, INK, strokeThickness)
	end
	return label
end

local function place(guiObject: GuiObject, anchor: Vector2, position: UDim2, size: UDim2)
	guiObject.AnchorPoint = anchor
	guiObject.Position = position
	guiObject.Size = size
end

local function addScale(parent: Instance, scale: number): UIScale
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = parent
	return uiScale
end

-- Counts a label from 0 to `target`, writing each step with `format`.
local function countUp(label: TextLabel, target: number, seconds: number, format: (number) -> string)
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(shown: number)
		label.Text = format(shown)
	end)
	local counting = tween(value, TweenInfo.new(seconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = target })
	counting.Completed:Once(function()
		label.Text = format(target)
		value:Destroy()
	end)
end

-- Little diamonds that fly out of `parent`'s middle and fade.
local function sparkle(parent: GuiObject, color: Color3, count: number)
	for index = 1, settings.effectCount(count) do
		local angle = (index / count) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local distance = random:NextNumber(0.7, 1.15)
		local spark = newFrame("Spark", parent, color)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromScale(0.5, 0.5)
		spark.Size = UDim2.fromScale(0.16, 0.16)
		spark.SizeConstraint = Enum.SizeConstraint.RelativeYY
		spark.Rotation = 45
		spark.ZIndex = parent.ZIndex + 2
		tween(spark, TweenInfo.new(random:NextNumber(0.45, 0.65), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * distance, 0.5 + math.sin(angle) * distance),
			Size = UDim2.fromScale(0, 0),
			BackgroundTransparency = 0.4,
			Rotation = 45 + random:NextNumber(-90, 90),
		})
		debris:AddItem(spark, 0.7)
	end
end

-- Paper confetti drifting down the whole screen.
local function rainConfetti(parent: Instance)
	for _ = 1, settings.effectCount(CONFETTI_PIECES) do
		local piece = newFrame("Confetti", parent, CONFETTI_COLORS[random:NextInteger(1, #CONFETTI_COLORS)])
		local startX = random:NextNumber(0.02, 0.98)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(startX, random:NextNumber(-0.25, -0.03))
		piece.Size = UDim2.fromScale(random:NextNumber(0.008, 0.014), random:NextNumber(0.016, 0.026))
		piece.SizeConstraint = Enum.SizeConstraint.RelativeYY
		piece.Rotation = random:NextNumber(0, 360)
		piece.ZIndex = 2
		local seconds = random:NextNumber(1.8, 3)
		tween(piece, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(startX + random:NextNumber(-0.12, 0.12), 1.1),
			Rotation = piece.Rotation + random:NextNumber(-540, 540),
		})
		debris:AddItem(piece, seconds)
	end
end

--// Building ---------------------------------------------------------------------------

local function buildStat(parent: Instance, order: number, caption: string): TextLabel
	local box = newFrame(caption, parent, Color3.new(0, 0, 0), 0.6)
	place(box, Vector2.new(0, 0), UDim2.fromScale((order - 1) * 0.34, 0), UDim2.fromScale(0.32, 1))
	addCorner(box, UDim.new(0.2, 0))
	addStroke(box, GOLD, 1.5, true).Transparency = 0.5

	local captionLabel = newLabel("Caption", box, caption, Color3.fromRGB(200, 180, 255))
	place(captionLabel, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.08), UDim2.fromScale(0.86, 0.3))

	local value = newLabel("Value", box, "0", Color3.new(1, 1, 1), 2)
	place(value, Vector2.new(0.5, 1), UDim2.fromScale(0.5, 0.92), UDim2.fromScale(0.88, 0.52))
	return value
end

local function buildRow(parent: Instance, index: number, row: Row): (Frame, UIScale, TextLabel, GuiObject)
	local frame = newFrame(row.name, parent, Color3.new(0, 0, 0), 0.5)
	place(frame, Vector2.new(0.5, 0), UDim2.fromScale(0.5, (index - 1) * 0.255), UDim2.fromScale(1, 0.22))
	frame.ZIndex = 3
	addCorner(frame, UDim.new(0.25, 0))
	addStroke(frame, row.color, 1.5, true).Transparency = 0.45
	local scale = addScale(frame, 0)

	local iconHolder: GuiObject
	if row.icon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = row.icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 4
		place(icon, Vector2.new(0, 0.5), UDim2.fromScale(0.03, 0.5), UDim2.fromScale(0.82, 0.82))
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.Parent = frame
		iconHolder = icon
	else
		local badge = newFrame("Icon", frame, row.color)
		place(badge, Vector2.new(0, 0.5), UDim2.fromScale(0.03, 0.5), UDim2.fromScale(0.74, 0.74))
		badge.SizeConstraint = Enum.SizeConstraint.RelativeYY
		badge.ZIndex = 4
		addCorner(badge, UDim.new(1, 0))
		addStroke(badge, Color3.new(1, 1, 1), 2, true)
		local newText = newLabel("New", badge, "NEW", Color3.new(1, 1, 1), 1.5)
		place(newText, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.5))
		newText.ZIndex = 5
		iconHolder = badge
	end

	local name = newLabel("Name", frame, row.name, SOFT_WHITE, 1.5)
	name.TextXAlignment = Enum.TextXAlignment.Left
	place(name, Vector2.new(0, 0.5), UDim2.fromScale(0.2, if row.bonus then 0.36 else 0.5), UDim2.fromScale(0.34, 0.42))
	name.ZIndex = 4

	if row.bonus then
		local bonus = newLabel("Bonus", frame, `{string.format("x%.1f", row.bonus)} BONUS`, GOLD, 1)
		bonus.TextXAlignment = Enum.TextXAlignment.Left
		place(bonus, Vector2.new(0, 0.5), UDim2.fromScale(0.2, 0.72), UDim2.fromScale(0.3, 0.28))
		bonus.ZIndex = 4
	end

	local amount = newLabel("Amount", frame, if row.value then "+0" else (row.text or ""), row.color, 2.5)
	amount.TextXAlignment = Enum.TextXAlignment.Right
	place(amount, Vector2.new(1, 0.5), UDim2.fromScale(0.96, 0.5), UDim2.fromScale(if row.value then 0.44 else 0.62, 0.62))
	amount.ZIndex = 4
	return frame, scale, amount, iconHolder
end

local function getRows(reward: Reward): { Row }
	local rows: { Row } = {
		{
			icon = IconIds.Wool,
			name = "WOOL",
			value = reward.wool,
			color = WOOL_COLOR,
			bonus = if reward.woolBonus > 1.05 then reward.woolBonus else nil,
			sound = "Cash",
		},
		{
			icon = IconIds.Luck,
			name = "LUCK",
			value = reward.luck,
			color = LUCK_COLOR,
			bonus = if reward.luckBonus > 1.05 then reward.luckBonus else nil,
			sound = "LuckClaimed",
		},
		{ icon = IconIds.Gem, name = "GEMS", value = reward.gems, color = GEM_COLOR, sound = "DiamondPickup" },
	}
	if reward.sheepName then
		table.insert(rows, {
			name = "NEW SHEEP",
			text = reward.sheepName,
			color = reward.mutationColor or GOLD,
			sound = "UnlockedSheep",
		})
	end
	return rows
end

--// Public API ------------------------------------------------------------------

function KingSheepRewardPopup.isOpen(): boolean
	return current ~= nil
end

-- Closes the popup if one is open.
function KingSheepRewardPopup.close()
	if current then
		current.close()
	end
end

function KingSheepRewardPopup.show(reward: Reward)
	KingSheepRewardPopup.close()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "KingSheepReward"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = DISPLAY_ORDER
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Dims and blurs the world; it also soaks up clicks so nothing behind it gets them.
	local backdrop = newFrame("Backdrop", screenGui, Color3.new(0, 0, 0), 1)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Active = true
	tween(backdrop, FADE_IN, { BackgroundTransparency = DIM_TRANSPARENCY })

	local camera = workspace.CurrentCamera
	local blur = Instance.new("BlurEffect")
	blur.Name = "KingSheepRewardBlur"
	blur.Size = 0
	blur.Parent = camera
	tween(blur, FADE_IN, { Size = BLUR_SIZE })

	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	place(rays, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.48), UDim2.fromScale(1.25, 1.25))
	rays.SizeConstraint = Enum.SizeConstraint.RelativeYY
	rays.ZIndex = 1
	rays.Parent = screenGui
	local raysScale = addScale(rays, 0.2)
	local rayImages: { ImageLabel } = {}
	for index, speed in { 16, -11 } do
		local image = Instance.new("ImageLabel")
		image.Name = `Shine{index}`
		image.BackgroundTransparency = 1
		image.Image = RAYS_IMAGE
		image.ImageColor3 = GOLD
		image.ImageTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.ZIndex = 1
		image:SetAttribute(SHINE_SPEED_ATTRIBUTE, speed)
		image.Parent = rays
		collectionService:AddTag(image, SHINE_TAG)
		tween(image, FADE_IN, { ImageTransparency = if index == 1 then 0.35 else 0.65 })
		table.insert(rayImages, image)
	end
	tween(raysScale, POP, { Scale = 1 })

	-- The card itself.
	local card = newFrame("Card", screenGui, Color3.new(1, 1, 1))
	place(card, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.36, 0.66))
	card.ZIndex = 3
	addCorner(card, UDim.new(0.06, 0))
	addGradient(card, CARD_TOP, CARD_BOTTOM)
	local border = addStroke(card, Color3.new(1, 1, 1), 4, true)
	local borderGradient = Instance.new("UIGradient")
	borderGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD_DARK),
		ColorSequenceKeypoint.new(0.25, GOLD),
		ColorSequenceKeypoint.new(0.5, GOLD_LIGHT),
		ColorSequenceKeypoint.new(0.75, GOLD),
		ColorSequenceKeypoint.new(1, GOLD_DARK),
	})
	borderGradient.Parent = border
	tween(borderGradient, TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 0.8
	aspect.Parent = card
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(290, 362)
	sizeConstraint.MaxSize = Vector2.new(470, 588)
	sizeConstraint.Parent = card
	local cardScale = addScale(card, 0.3)
	card.Rotation = -7
	tween(cardScale, POP, { Scale = 1 })
	tween(card, POP, { Rotation = 0 })

	-- The gold ribbon across the top edge with the title on it.
	local ribbon = newFrame("Ribbon", card, Color3.new(1, 1, 1))
	place(ribbon, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.02), UDim2.fromScale(1.1, 0.15))
	ribbon.ZIndex = 5
	addCorner(ribbon, UDim.new(0.3, 0))
	addGradient(ribbon, GOLD_LIGHT, GOLD_DARK)
	addStroke(ribbon, INK, 3, true)
	local titleLabel = newLabel("Title", ribbon, "KING SHEEP DEFEATED!", Color3.new(1, 1, 1), 3)
	place(titleLabel, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.7))
	titleLabel.ZIndex = 6
	local titleShine = Instance.new("UIGradient")
	titleShine.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, GOLD_LIGHT),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	titleShine.Offset = Vector2.new(-1, 0)
	titleShine.Parent = titleLabel
	tween(titleShine, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.6), { Offset = Vector2.new(1, 0) })

	-- Rank badge: a gold "TOP SHEARER!" for first place, otherwise the place out of everyone rewarded.
	local isTop = reward.rank == 1
	local badge = newFrame("Badge", card, if isTop then GOLD else Color3.fromRGB(60, 34, 100))
	place(badge, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.155), UDim2.fromScale(0.56, 0.065))
	badge.ZIndex = 4
	addCorner(badge, UDim.new(1, 0))
	addStroke(badge, if isTop then INK else GOLD, 2, true)
	local badgeText = newLabel("Text", badge, if isTop then "TOP SHEARER!" else `RANK #{reward.rank} OF {reward.shearers}`,
		if isTop then INK else GOLD)
	place(badgeText, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.86, 0.72))
	badgeText.ZIndex = 5
	local badgeScale = addScale(badge, 0)
	tween(badgeScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.35), { Scale = 1 })

	-- Damage, share and rank, counted up.
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	place(stats, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.21), UDim2.fromScale(0.88, 0.12))
	stats.ZIndex = 4
	stats.Parent = card
	local damageValue = buildStat(stats, 1, "DAMAGE")
	local shareValue = buildStat(stats, 2, "SHARE")
	local rankValue = buildStat(stats, 3, "RANK")
	rankValue.Text = `#{reward.rank}/{reward.shearers}`
	task.delay(0.45, function()
		countUp(damageValue, reward.damage, COUNT_SECONDS, formatShort)
		countUp(shareValue, reward.share * 100, COUNT_SECONDS, function(value: number): string
			return string.format("%.1f%%", value)
		end)
	end)

	local divider = newLabel("Rewards", card, "-  REWARDS  -", GOLD, 1.5)
	place(divider, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.355), UDim2.fromScale(0.5, 0.045))
	divider.ZIndex = 4

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	place(list, Vector2.new(0.5, 0), UDim2.fromScale(0.5, 0.415), UDim2.fromScale(0.88, 0.42))
	list.ZIndex = 3
	list.Parent = card

	local claim = Instance.new("TextButton")
	claim.Name = "Claim"
	claim.BackgroundColor3 = Color3.new(1, 1, 1)
	claim.AutoButtonColor = true
	claim.Font = TEXT_FONT
	claim.Text = "CLAIM!"
	claim.TextScaled = true
	claim.TextColor3 = Color3.new(1, 1, 1)
	claim.Visible = false
	claim.ZIndex = 5
	place(claim, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.92), UDim2.fromScale(0.5, 0.095))
	claim.Parent = card
	addCorner(claim, UDim.new(0.3, 0))
	addGradient(claim, CLAIM_TOP, CLAIM_BOTTOM)
	addStroke(claim, INK, 3, true)
	local claimText = Instance.new("UIStroke")
	claimText.Color = Color3.fromRGB(16, 70, 20)
	claimText.Thickness = 2.5
	claimText.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	claimText.Parent = claim
	local claimPadding = Instance.new("UIPadding")
	claimPadding.PaddingTop = UDim.new(0.16, 0)
	claimPadding.PaddingBottom = UDim.new(0.16, 0)
	claimPadding.Parent = claim
	local claimScale = addScale(claim, 0)

	cutscene.playSound("UISounds", "Prestige", 1, 0.9)
	task.delay(0.35, function()
		if screenGui.Parent then
			sparkle(card, GOLD, 14)
			rainConfetti(screenGui)
		end
	end)

	-- Closing: everything shrinks and fades, the blur lifts, then the gui goes.
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if current and current.close == close then
			current = nil
		end
		tween(cardScale, CLOSE, { Scale = 0 })
		tween(raysScale, CLOSE, { Scale = 0 })
		tween(backdrop, CLOSE, { BackgroundTransparency = 1 })
		tween(blur, CLOSE, { Size = 0 })
		for _, image in rayImages do
			tween(image, CLOSE, { ImageTransparency = 1 })
		end
		task.delay(CLOSE.Time + 0.05, function()
			screenGui:Destroy()
			blur:Destroy()
		end)
	end
	current = { close = close }

	claim.Activated:Connect(function()
		cutscene.playSound("UISounds", "Click")
		close()
	end)

	-- The rows pop in one after another, each counting up to its exact number with a burst and its own sound.
	local rows = getRows(reward)
	for index, row in rows do
		task.delay(FIRST_ROW_DELAY + (index - 1) * ROW_STAGGER, function()
			if closed then
				return
			end
			local frame, scale, amount, icon = buildRow(list, index, row)
			frame.Position += UDim2.fromOffset(40, 0)
			tween(frame, ROW_POP, { Position = frame.Position - UDim2.fromOffset(40, 0) })
			tween(scale, ROW_POP, { Scale = 1 })
			cutscene.playSound("UISounds", "Pop", 1 + (index - 1) * 0.08)

			local function land()
				if closed then
					return
				end
				cutscene.playSound("UISounds", row.sound)
				sparkle(icon, row.color, 10)
				local amountScale = addScale(amount, 1.35)
				tween(amountScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
				local iconScale = addScale(icon, 1.3)
				tween(iconScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			end

			local value = row.value
			if value then
				countUp(amount, value, COUNT_SECONDS, function(shown: number): string
					return `+{formatShort(shown)}`
				end)
				task.delay(COUNT_SECONDS, land)
			else
				task.delay(0.15, land)
			end
		end)
	end

	local doneAt = FIRST_ROW_DELAY + (#rows - 1) * ROW_STAGGER + COUNT_SECONDS + 0.2
	task.delay(doneAt, function()
		if closed then
			return
		end
		claim.Visible = true
		tween(claimScale, ROW_POP, { Scale = 1 }).Completed:Once(function()
			if not closed then
				tween(claimScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 })
			end
		end)
	end)
	task.delay(doneAt + AUTO_CLOSE_SECONDS, close)
end

return KingSheepRewardPopup
