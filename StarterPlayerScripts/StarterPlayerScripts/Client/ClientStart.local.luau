--[[
	Starts the client network and keeps the Main HUD's wool, luck and sheep sheared labels updated.
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

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

-- WoolCollectClient holds back the wool still flying to the counter, so the number climbs as it lands.
local function updateWoolAmountLabel()
	local held = player:GetAttribute("WoolLabelHold")
	local shown = math.max(woolAmountValue.Value - (if type(held) == "number" then held else 0), 0)
	woolAmountLabel.Text = `Wool: {numberFormatter:Format(shown, 1)}`
end

local function updateLuckAmountLabel()
	luckAmountLabel.Text = `Luck: {numberFormatter:Format(luckAmountValue.Value, 1)}`
end

-- 32932 -> "32,932"
local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^(-?),", "%1"))
end

local function updateSheepCountLabel()
	local count = player:GetAttribute("SheepShearedCount")
	sheepCountLabel.Text = formatWithCommas(if type(count) == "number" then count else 0)
end

updateWoolAmountLabel()
updateLuckAmountLabel()
updateSheepCountLabel()

woolAmountValue.Changed:Connect(updateWoolAmountLabel)
luckAmountValue.Changed:Connect(updateLuckAmountLabel)
player:GetAttributeChangedSignal("SheepShearedCount"):Connect(updateSheepCountLabel)
player:GetAttributeChangedSignal("WoolLabelHold"):Connect(updateWoolAmountLabel)
