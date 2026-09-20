local replicatedStorage = game:GetService("ReplicatedStorage")

local sourceFolder = replicatedStorage:WaitForChild("Source")
local moduleLoader = require(sourceFolder.ModuleLoader)

local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local woolAmountValue = player:WaitForChild("WoolAmount")
local woolAmountLabel = playerGui:WaitForChild("Main").WoolAmount

local function updateWoolAmountLabel()
    woolAmountLabel.Text = `Wool: {woolAmountValue.Value}`
end
-- If the entry script needs to do something after loading (optional):
moduleLoader.GameReadySignal:Once(function()

    -- Update wool backpack UI    
    updateWoolAmountLabel()
end)

player:GetAttributeChangedSignal("WoolAmount"):Connect(updateWoolAmountLabel)

moduleLoader.Init()
