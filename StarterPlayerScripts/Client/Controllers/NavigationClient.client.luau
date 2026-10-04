--// Services

--// Player Vars
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = playerGui:WaitForChild("Main")
local plotButton = mainGui:FindFirstChild("ToPlot")
local toPlazaButton = mainGui:FindFirstChild("ToPlaza")

local network = require(game.ReplicatedStorage.Shared:WaitForChild("Utils"):WaitForChild("Network"))

--// Variables
plotButton.Activated:Connect(function()
    network.fireServer("Teleport", "plot")
end)

toPlazaButton.Activated:Connect(function()
    network.fireServer("Teleport", "plaza")
end)