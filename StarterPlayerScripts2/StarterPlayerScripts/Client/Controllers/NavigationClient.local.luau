--// Services

--// Player Vars
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = playerGui:WaitForChild("Main")
local plotButton = mainGui:FindFirstChild("ToPlot")
local toShopButton = mainGui:FindFirstChild("ToShop")

local network = require(game.ReplicatedStorage.Shared:WaitForChild("Utils"):WaitForChild("Network"))

--// Variables
plotButton.Activated:Connect(function()
    network.fireServer("Teleport", "plot")
end)

toShopButton.Activated:Connect(function()
    network.fireServer("Teleport", "plaza")
end)