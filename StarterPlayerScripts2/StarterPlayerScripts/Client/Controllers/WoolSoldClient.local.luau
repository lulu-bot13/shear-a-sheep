--[[
	Small popup that shows how much money the player just got when they sell their wool.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.WoolSoldClient
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local playerGui = players.LocalPlayer:WaitForChild("PlayerGui")

--// Style
local FONT = Enum.Font.SourceSansBold
local GOLD = Color3.fromRGB(255, 176, 32)
local GREEN = Color3.fromRGB(110, 255, 130)
local PANEL_COLOR = Color3.fromRGB(16, 17, 24)
local SUBTEXT_COLOR = Color3.fromRGB(200, 202, 212)
local BLACK = Color3.new(0, 0, 0)

local POP_IN = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HOLD_SECONDS = 1.6

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WoolSoldGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 9
screenGui.Parent = playerGui

local currentPopup: Frame? = nil
local popupToken = 0

-- Comma-groups a number (e.g. 32000 -> "32,000").
local function formatNumber(amount: number): string
	local digits = tostring(math.floor(math.abs(amount)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return grouped
end

-- Shortens a wool amount (e.g. 123200 -> "123.2k").
local function formatWool(amount: number): string
	return numberFormatter:Format(math.abs(amount), 1) or "0"
end

local function addTextStroke(label: TextLabel, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BLACK
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local function showPopup(woolAmount: number, cash: number)
	-- A new sale replaces any popup that's still showing.
	if currentPopup then
		currentPopup:Destroy()
	end
	popupToken += 1
	local token = popupToken

	local card = Instance.new("Frame")
	card.Name = "SoldCard"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.3)
	card.Size = UDim2.fromOffset(230, 76)
	card.BackgroundColor3 = PANEL_COLOR
	card.Parent = screenGui
	currentPopup = card

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = card

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = card

	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "Money"
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Position = UDim2.fromOffset(0, 6)
	moneyLabel.Size = UDim2.new(1, 0, 0, 44)
	moneyLabel.Font = FONT
	moneyLabel.TextSize = 40
	moneyLabel.TextColor3 = GREEN
	moneyLabel.Text = `+${formatNumber(cash)}`
	moneyLabel.Parent = card
	addTextStroke(moneyLabel, 2.5)

	local soldLabel = Instance.new("TextLabel")
	soldLabel.Name = "Sold"
	soldLabel.BackgroundTransparency = 1
	soldLabel.Position = UDim2.fromOffset(0, 48)
	soldLabel.Size = UDim2.new(1, 0, 0, 22)
	soldLabel.Font = FONT
	soldLabel.TextSize = 20
	soldLabel.TextColor3 = SUBTEXT_COLOR
	soldLabel.Text = `Sold {formatWool(woolAmount)} wool`
	soldLabel.Parent = card
	addTextStroke(soldLabel, 2)

	tweenService:Create(scale, POP_IN, { Scale = 1 }):Play()

	task.delay(HOLD_SECONDS, function()
		if token ~= popupToken or not card.Parent then
			return
		end

		tweenService:Create(card, FADE_OUT, {
			Position = UDim2.fromScale(0.5, 0.27),
			BackgroundTransparency = 1,
		}):Play()
		tweenService:Create(stroke, FADE_OUT, { Transparency = 1 }):Play()
		tweenService:Create(moneyLabel, FADE_OUT, { TextTransparency = 1 }):Play()
		tweenService:Create(soldLabel, FADE_OUT, { TextTransparency = 1 }):Play()
		for _, label in { moneyLabel, soldLabel } do
			local textStroke = label:FindFirstChildOfClass("UIStroke")
			if textStroke then
				tweenService:Create(textStroke, FADE_OUT, { Transparency = 1 }):Play()
			end
		end

		task.wait(FADE_OUT.Time)
		if token == popupToken then
			currentPopup = nil
		end
		card:Destroy()
	end)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.WoolSold, function(woolAmount: number, cash: number)
	showPopup(woolAmount, cash)
end)
