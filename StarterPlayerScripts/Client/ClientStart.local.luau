local replicatedStorage = game:GetService("ReplicatedStorage")

local sourceFolder = replicatedStorage:WaitForChild("Source")
local moduleLoader = require(sourceFolder.ModuleLoader)
local network = require(replicatedStorage.Shared.Utils.Network)

local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local inventory = player:WaitForChild("Inventory")
local woolAmountValue = inventory:WaitForChild("Wool") :: IntValue
local woolAmountLabel = playerGui:WaitForChild("Main").WoolAmount

local function updateWoolAmountLabel()
	woolAmountLabel.Text = `Wool: {woolAmountValue.Value}`
end
-- If the entry script needs to do something after loading (optional):
moduleLoader.GameReadySignal:Once(function()

	-- Update wool backpack UI
	updateWoolAmountLabel()
end)

woolAmountValue.Changed:Connect(updateWoolAmountLabel)

network.startClientAsync()
moduleLoader.Init()
