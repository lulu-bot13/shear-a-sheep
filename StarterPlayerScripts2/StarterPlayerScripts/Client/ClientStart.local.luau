--[[
	Starts the client network and keeps the wool label updated
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

--// Modules
local moduleLoader = require(replicatedStorage:WaitForChild("Source"):WaitForChild("ModuleLoader"))
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local inventory = player:WaitForChild("Inventory")
local woolAmountValue = inventory:WaitForChild("Wool") :: IntValue
local woolAmountLabel = playerGui:WaitForChild("Main").WoolAmount

-- WoolCollectClient holds back the wool still flying to the counter, so the number climbs as it lands.
local function updateWoolAmountLabel()
	local held = player:GetAttribute("WoolLabelHold")
	local shown = math.max(woolAmountValue.Value - (if type(held) == "number" then held else 0), 0)
	woolAmountLabel.Text = `Wool: {numberFormatter:Format(shown, 1)}`
end
-- If the entry script needs to do something after loading (optional):
moduleLoader.GameReadySignal:Once(function()

	-- Update wool backpack UI
	updateWoolAmountLabel()
end)

woolAmountValue.Changed:Connect(updateWoolAmountLabel)
player:GetAttributeChangedSignal("WoolLabelHold"):Connect(updateWoolAmountLabel)

network.startClientAsync()
moduleLoader.Init()
