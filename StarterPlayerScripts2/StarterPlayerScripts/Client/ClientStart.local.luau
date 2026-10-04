--[[
	Starts the client network and keeps the wool label updated
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

--// Modules
local moduleLoader = require(replicatedStorage:WaitForChild("Source"):WaitForChild("ModuleLoader"))
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
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
