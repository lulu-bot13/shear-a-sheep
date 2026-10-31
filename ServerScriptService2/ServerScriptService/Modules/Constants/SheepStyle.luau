--!strict

--[[
	Text colour, outline and font for the name labels over sheep, picked by the sheep's mood (one per rarity).
	Location: ServerScriptService.Modules.Constants.SheepStyle
]]--

export type MoodStyle = {
	TextColor: Color3,
	StrokeColor: Color3,
	Font: Font,
}

local FONT_FAMILY = "rbxasset://fonts/families/GothamSSm.json"
local BOLD = Font.new(FONT_FAMILY, Enum.FontWeight.Bold)
local HEAVY = Font.new(FONT_FAMILY, Enum.FontWeight.Heavy)
local templateLabel = game:GetService("ReplicatedStorage").Assets.UI.SheepHUD:FindFirstChild("NameLabel", true) :: TextLabel?
local TEMPLATE_FONT = if templateLabel then templateLabel.FontFace else Font.fromEnum(Enum.Font.GothamBold)

local sheepStyle = {}

sheepStyle.Moods = {
	Classic = { TextColor = Color3.fromRGB(255, 255, 255), StrokeColor = Color3.fromRGB(0, 0, 0), Font = TEMPLATE_FONT },
	Calm = { TextColor = Color3.fromRGB(240, 242, 245), StrokeColor = Color3.fromRGB(55, 65, 81), Font = BOLD },
	Cheerful = { TextColor = Color3.fromRGB(187, 247, 208), StrokeColor = Color3.fromRGB(20, 83, 45), Font = BOLD },
	Curious = { TextColor = Color3.fromRGB(191, 219, 254), StrokeColor = Color3.fromRGB(30, 58, 138), Font = BOLD },
	Proud = { TextColor = Color3.fromRGB(233, 213, 255), StrokeColor = Color3.fromRGB(88, 28, 135), Font = HEAVY },
	Majestic = { TextColor = Color3.fromRGB(253, 224, 71), StrokeColor = Color3.fromRGB(124, 45, 18), Font = HEAVY },
	Fierce = { TextColor = Color3.fromRGB(254, 205, 211), StrokeColor = Color3.fromRGB(136, 19, 55), Font = HEAVY },
} :: { [string]: MoodStyle }

sheepStyle.MoodByRarity = {
	Common = "Classic",
	Uncommon = "Cheerful",
	Rare = "Curious",
	Epic = "Proud",
	Legendary = "Majestic",
	Mythic = "Fierce",
	Boss = "Fierce",
}

local DEFAULT_MOOD = "Calm"

-- Babies always get the Classic look, whatever their rarity.
function sheepStyle.getMood(rarity: string, baby: boolean?): string
	if baby then
		return "Classic"
	end
	return sheepStyle.MoodByRarity[rarity] or DEFAULT_MOOD
end

-- Styles the label (and its UIStroke, if it has one) for the mood; unknown moods get the Calm look.
function sheepStyle.apply(label: TextLabel, mood: string)
	local style = sheepStyle.Moods[mood] or sheepStyle.Moods[DEFAULT_MOOD]
	label.TextColor3 = style.TextColor
	label.FontFace = style.Font
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = style.StrokeColor
	end
end

return sheepStyle
