--[[
	Starts the client network and keeps the Main HUD's wool, luck and sheep sheared labels updated.
	Pops a "+N" next to the sheep sheared count whenever it goes up.
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

backgroundMusic.start()

-- Started first: the wool and luck values below only appear once the player's save has loaded.
network.startClientAsync()
moduleLoader.Init()

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Main")
local woolAmountLabel = mainGui:WaitForChild("WoolAmount") :: TextLabel
local luckAmountLabel = mainGui:WaitForChild("LuckAmount") :: TextLabel
local sheepCountLabel = mainGui:WaitForChild("SheepCount"):WaitForChild("Count") :: TextLabel
local inventory = player:WaitForChild("Inventory")
local woolAmountValue = inventory:WaitForChild("Wool") :: IntValue
local luckAmountValue = inventory:WaitForChild("Luck") :: IntValue

-- WoolCollectClient holds back the wool and Luck still flying to the counters, so the numbers climb as they land.
local function getShown(value: IntValue, holdAttribute: string): number
	local held = player:GetAttribute(holdAttribute)
	return math.max(value.Value - (if type(held) == "number" then held else 0), 0)
end

local function updateWoolAmountLabel()
	woolAmountLabel.Text = `Wool: {numberFormatter:Format(getShown(woolAmountValue, "WoolLabelHold"), 1)}`
end

local function updateLuckAmountLabel()
	luckAmountLabel.Text = `Luck: {numberFormatter:Format(getShown(luckAmountValue, "LuckLabelHold"), 1)}`
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

updateWoolAmountLabel()
updateLuckAmountLabel()
updateSheepCountLabel()

woolAmountValue.Changed:Connect(updateWoolAmountLabel)
luckAmountValue.Changed:Connect(updateLuckAmountLabel)
player:GetAttributeChangedSignal("SheepShearedCount"):Connect(updateSheepCountLabel)
player:GetAttributeChangedSignal("WoolLabelHold"):Connect(updateWoolAmountLabel)
player:GetAttributeChangedSignal("LuckLabelHold"):Connect(updateLuckAmountLabel)
