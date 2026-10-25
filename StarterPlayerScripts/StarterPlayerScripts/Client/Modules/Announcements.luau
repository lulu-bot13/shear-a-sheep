--[[
	Pops in the announcement labels built in Studio under StarterGui.Alerts (rebirth ready, rebirthed, new title) and fades them out.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Announcements
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Configs
local SHOW_SECONDS = 2.5
local POP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_START_SCALE = 0.3

-- Fixed stacking order inside Alerts.Main.
local LAYOUT_ORDERS = {
	RebirthAlert = 1,
	TitleAlert = 2,
}

export type Name = "RebirthAlert" | "TitleAlert" | "Rebirthed"

type Entry = {
	label: TextLabel,
	scale: UIScale,
	stroke: UIStroke?,
	shadow: Instance?, -- the UIShadow, only when it has a Transparency to fade
	textTransparency: number,
	strokeTransparency: number,
	shadowTransparency: number,
	token: number,
	tweens: { Tween },
}

local Announcements = {}

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")
local alertsGui = playerGui:WaitForChild("Alerts") :: ScreenGui
alertsGui.ResetOnSpawn = false -- keep this copy (and the labels found below) across respawns
local mainFrame = alertsGui:WaitForChild("Main") :: Frame

--// State
local entries: { [Name]: Entry } = {}

--// Helpers ---------------------------------------------------------------------

local function getShadowTransparency(shadow: Instance): number?
	local ok, value = pcall(function()
		return (shadow :: any).Transparency
	end)
	return if ok and type(value) == "number" then value else nil
end

local function makeEntry(label: TextLabel): Entry
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end

	local stroke = label:FindFirstChildOfClass("UIStroke")
	local shadow = label:FindFirstChild("UIShadow")
	local shadowTransparency = if shadow then getShadowTransparency(shadow) else nil

	return {
		label = label,
		scale = scale :: UIScale,
		stroke = stroke,
		shadow = if shadowTransparency then shadow else nil,
		textTransparency = label.TextTransparency,
		strokeTransparency = if stroke then stroke.Transparency else 0,
		shadowTransparency = shadowTransparency or 0,
		token = 0,
		tweens = {},
	}
end

local function getEntry(name: Name): Entry
	local entry = entries[name]
	if not entry then
		local parent = if LAYOUT_ORDERS[name] then mainFrame else alertsGui
		local label = parent:WaitForChild(name) :: TextLabel
		if LAYOUT_ORDERS[name] then
			label.LayoutOrder = LAYOUT_ORDERS[name]
		end
		entry = makeEntry(label)
		entries[name] = entry
	end
	return entry
end

local function play(entry: Entry, instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = tweenService:Create(instance, info, goal)
	table.insert(entry.tweens, tween)
	tween:Play()
	return tween
end

-- Stops any running tweens and puts the label back to how Studio built it.
local function reset(entry: Entry)
	for _, tween in entry.tweens do
		tween:Cancel()
	end
	table.clear(entry.tweens)

	entry.label.TextTransparency = entry.textTransparency
	if entry.stroke then
		entry.stroke.Transparency = entry.strokeTransparency
	end
	if entry.shadow then
		(entry.shadow :: any).Transparency = entry.shadowTransparency
	end
end

--// Public API ------------------------------------------------------------------

-- Shows the label with this text for a few seconds; showing it again while it's up restarts it.
function Announcements.show(name: Name, text: string, richText: boolean?)
	local entry = getEntry(name)
	entry.token += 1
	local token = entry.token

	reset(entry)
	entry.label.RichText = richText == true
	entry.label.Text = text
	entry.label.Visible = true
	entry.scale.Scale = POP_START_SCALE
	play(entry, entry.scale, POP_TWEEN, { Scale = 1 })

	task.delay(SHOW_SECONDS, function()
		if token ~= entry.token then
			return
		end
		if entry.stroke then
			play(entry, entry.stroke, FADE_TWEEN, { Transparency = 1 })
		end
		if entry.shadow then
			play(entry, entry.shadow, FADE_TWEEN, { Transparency = 1 })
		end
		local fade = play(entry, entry.label, FADE_TWEEN, { TextTransparency = 1 })
		fade.Completed:Once(function(playbackState: Enum.PlaybackState)
			if token ~= entry.token or playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			entry.label.Visible = false
			reset(entry)
		end)
	end)
end

return Announcements
