--[[
	Starts the client network and keeps the Main HUD's wool, luck, Gems, sheep sheared and pen count labels updated.
	Wool, luck and Gems pop with a light green tint when they go up; the sheep sheared count pops a "+N".
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")
local debris = game:GetService("Debris")

--// Modules
local moduleLoader = require(replicatedStorage:WaitForChild("Source"):WaitForChild("ModuleLoader"))
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local backgroundMusic = require(script.Parent.Modules.BackgroundMusic)
require(script.Parent.Modules.Settings) -- first, so the music waits for the saved Music setting

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- StarterGui.Main is left disabled in Studio for working space; turn it on in game, including the copy made on each respawn.
local function enableMainGui(gui: Instance)
	if gui.Name == "Main" and gui:IsA("ScreenGui") then
		gui.Enabled = true
	end
end

playerGui.ChildAdded:Connect(enableMainGui)
for _, gui in playerGui:GetChildren() do
	enableMainGui(gui)
end

backgroundMusic.start()

-- Started first: the wool and luck values below only appear once the player's save has loaded.
network.startClientAsync()
moduleLoader.Init()

--// Instances
local mainGui = playerGui:WaitForChild("Main")
local currencyFrame = mainGui:WaitForChild("CurrencyFrame")
local woolAmountLabel = currencyFrame:WaitForChild("WoolAmount") :: TextLabel
local luckAmountLabel = currencyFrame:WaitForChild("LuckAmount") :: TextLabel
local gemAmountLabel = currencyFrame:WaitForChild("GemsAmount") :: TextLabel
local sheepCountLabel = mainGui:WaitForChild("SheepCount"):WaitForChild("Count") :: TextLabel
local sheepPenCount = mainGui:WaitForChild("SheepPenCount")
local sheepPenCountLabel = (if sheepPenCount:IsA("TextLabel") then sheepPenCount else sheepPenCount:FindFirstChildWhichIsA("TextLabel", true)) :: TextLabel
local inventory = player:WaitForChild("Inventory")
local woolAmountValue = inventory:WaitForChild("Wool") :: IntValue
local luckAmountValue = inventory:WaitForChild("Luck") :: IntValue

--// Configs
local PULSE_SCALE = 1.1
local PULSE_COLOR = Color3.fromRGB(85, 255, 85)
local PULSE_TINT = 0.3 -- how far the text leans towards PULSE_COLOR at the peak
local PULSE_GROW_SECONDS = 0.05
local PULSE_SETTLE_SECONDS = 0.1 -- grow + settle stays under 0.15s, since drops land in quick succession

-- A HUD counter, the colour it settles back to and the last amount it showed.
type Counter = {
	label: TextLabel,
	scale: UIScale,
	color: Color3,
	tweens: { Tween },
	lastShown: number?,
	shadowScale: UIScale?, -- the drop-shadow label's scale, so it pops along with the label
}

local function getScale(label: TextLabel): UIScale
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = label
	end
	return scale :: UIScale
end

local function newCounter(label: TextLabel): Counter
	return { label = label, scale = getScale(label), color = label.TextColor3, tweens = {}, lastShown = nil, shadowScale = nil }
end

local woolCounter = newCounter(woolAmountLabel)
local luckCounter = newCounter(luckAmountLabel)
local gemCounter = newCounter(gemAmountLabel)

-- The drop-shadow copy behind each amount label always shows the label's text and is only visible while the label is.
-- Visible is re-synced when the shadow alone is changed too (ShearShopClient's hideHud keeps WoolAmount but hides ShadowWool).
local function linkShadow(counter: Counter, shadowName: string)
	task.spawn(function()
		local label = counter.label
		local shadow = currencyFrame:WaitForChild(shadowName) :: TextLabel

		local function syncText()
			shadow.Text = label.Text
		end
		local function syncVisible()
			shadow.Visible = label.Visible
		end

		label:GetPropertyChangedSignal("Text"):Connect(syncText)
		label:GetPropertyChangedSignal("Visible"):Connect(syncVisible)
		shadow:GetPropertyChangedSignal("Visible"):Connect(syncVisible)
		syncText()
		syncVisible()
		counter.shadowScale = getScale(shadow)
	end)
end

linkShadow(woolCounter, "ShadowWool")
linkShadow(luckCounter, "ShadowLuck")
linkShadow(gemCounter, "ShadowGems")

-- Pops the counter up with a light green tint and straight back down; a new increase restarts it from wherever it is.
local function pulseCounter(counter: Counter)
	for _, tween in counter.tweens do
		tween:Cancel()
	end

	local growInfo = TweenInfo.new(PULSE_GROW_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local settleInfo = TweenInfo.new(PULSE_SETTLE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local grow = tweenService:Create(counter.scale, growInfo, { Scale = PULSE_SCALE })
	local flash = tweenService:Create(counter.label, growInfo, { TextColor3 = counter.color:Lerp(PULSE_COLOR, PULSE_TINT) })
	local shrink = tweenService:Create(counter.scale, settleInfo, { Scale = 1 })
	local fade = tweenService:Create(counter.label, settleInfo, { TextColor3 = counter.color })
	counter.tweens = { grow, flash, shrink, fade }

	local shadowGrow: Tween?, shadowShrink: Tween? = nil, nil
	if counter.shadowScale then
		shadowGrow = tweenService:Create(counter.shadowScale, growInfo, { Scale = PULSE_SCALE })
		shadowShrink = tweenService:Create(counter.shadowScale, settleInfo, { Scale = 1 })
		table.insert(counter.tweens, shadowGrow)
		table.insert(counter.tweens, shadowShrink)
	end

	grow.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			shrink:Play()
			fade:Play()
			if shadowShrink then
				shadowShrink:Play()
			end
		end
	end)
	grow:Play()
	flash:Play()
	if shadowGrow then
		shadowGrow:Play()
	end
end

-- WoolCollectClient holds back the wool and Luck still flying to the counters, so the numbers climb as they land.
local function getShown(value: IntValue, holdAttribute: string): number
	local held = player:GetAttribute(holdAttribute)
	return math.max(value.Value - (if type(held) == "number" then held else 0), 0)
end

local function showCount(counter: Counter, prefix: string, shown: number)
	counter.label.Text = `{prefix}: {numberFormatter:Format(shown, 1)}`

	-- Skips the first value so loading a save doesn't pulse.
	if counter.lastShown and shown > counter.lastShown then
		pulseCounter(counter)
	end
	counter.lastShown = shown
end

local function updateCounter(counter: Counter, prefix: string, value: IntValue, holdAttribute: string)
	showCount(counter, prefix, getShown(value, holdAttribute))
end

-- Gems are a player attribute (not in Inventory) and never fly to the counter, so there is nothing to hold back.
local function updateGemAmountLabel()
	local gems = player:GetAttribute("Gems")
	showCount(gemCounter, "Gems", if type(gems) == "number" then gems else 0)
end

local function updateWoolAmountLabel()
	updateCounter(woolCounter, "Wool", woolAmountValue, "WoolLabelHold")
end

local function updateLuckAmountLabel()
	updateCounter(luckCounter, "Luck", luckAmountValue, "LuckLabelHold")
end

local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

-- Sits just right of the end of the Count text itself (not the frame), vertically centred on it.
local function getSheepCountPopupPosition(): UDim2
	local labelPosition, labelSize = sheepCountLabel.AbsolutePosition, sheepCountLabel.AbsoluteSize
	local textWidth = sheepCountLabel.TextBounds.X
	local alignment = sheepCountLabel.TextXAlignment
	local textRight = if alignment == Enum.TextXAlignment.Left
		then labelPosition.X + textWidth
		elseif alignment == Enum.TextXAlignment.Right then labelPosition.X + labelSize.X
		else labelPosition.X + (labelSize.X + textWidth) / 2

	local mainPosition = mainGui.AbsolutePosition
	return UDim2.fromOffset(textRight - mainPosition.X + 4, labelPosition.Y + labelSize.Y / 2 - mainPosition.Y)
end

local function showShearedPopup(amount: number)
	local frame = mainGui.SheepCount :: GuiObject
	local target = getSheepCountPopupPosition()

	local popup = Instance.new("TextLabel")
	popup.Name = "ShearedPopup"
	popup.BackgroundTransparency = 1
	popup.AnchorPoint = Vector2.new(0, 0.5)
	popup.Size = UDim2.fromOffset(frame.AbsoluteSize.X * 0.5, sheepCountLabel.AbsoluteSize.Y)
	popup.Position = target + UDim2.fromOffset(0, 12)
	popup.Font = Enum.Font.SourceSansBold
	popup.Text = `+{formatWithCommas(amount)}`
	popup.TextColor3 = Color3.fromRGB(255, 220, 120)
	popup.TextTransparency = 0
	popup.TextScaled = true
	popup.TextXAlignment = Enum.TextXAlignment.Left
	popup.ZIndex = frame.ZIndex + 1

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(60, 40, 15)
	stroke.Thickness = 2
	stroke.Parent = popup

	popup.Parent = mainGui

	tweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target }):Play()
	task.delay(0.6, function()
		local fadeInfo = TweenInfo.new(0.25)
		tweenService:Create(popup, fadeInfo, { TextTransparency = 1 }):Play()
		tweenService:Create(stroke, fadeInfo, { Transparency = 1 }):Play()
	end)
	debris:AddItem(popup, 0.85)
end

local lastSheepCount: number? = nil

local function updateSheepCountLabel()
	local count = player:GetAttribute("SheepShearedCount")
	count = if type(count) == "number" then count else 0
	sheepCountLabel.Text = formatWithCommas(count)

	-- Skips the first value so loading a save doesn't pop up the whole total.
	if lastSheepCount and count > lastSheepCount then
		showShearedPopup(count - lastSheepCount)
	end
	lastSheepCount = count
end

-- Sheep in the player's pen out of their capacity, e.g. 2/20 (set by SheepSpawnHandler).
local function updateSheepPenCountLabel()
	local count = player:GetAttribute("PenCount")
	local maximum = player:GetAttribute("PenMax")
	sheepPenCountLabel.Text = `{if type(count) == "number" then count else 0}/{if type(maximum) == "number" then maximum else 0}`
end

updateWoolAmountLabel()
updateLuckAmountLabel()
updateGemAmountLabel()
updateSheepCountLabel()
updateSheepPenCountLabel()

woolAmountValue.Changed:Connect(updateWoolAmountLabel)
luckAmountValue.Changed:Connect(updateLuckAmountLabel)
player:GetAttributeChangedSignal("Gems"):Connect(updateGemAmountLabel)
player:GetAttributeChangedSignal("SheepShearedCount"):Connect(updateSheepCountLabel)
player:GetAttributeChangedSignal("PenCount"):Connect(updateSheepPenCountLabel)
player:GetAttributeChangedSignal("PenMax"):Connect(updateSheepPenCountLabel)
player:GetAttributeChangedSignal("WoolLabelHold"):Connect(updateWoolAmountLabel)
player:GetAttributeChangedSignal("LuckLabelHold"):Connect(updateLuckAmountLabel)
