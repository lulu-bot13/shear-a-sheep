--// Services
local players = game:GetService("Players")

local function onPlayerAdded(player: Player)
    print(`Player {player.Name} has joined the game!`)
    
    -- Setup temporary data
    local woolAmount = Instance.new("IntValue")
    woolAmount.Name = "WoolAmount"
    woolAmount.Value = 0
    woolAmount.Parent = player

    local maxSpace = Instance.new("IntValue")
    maxSpace.Name = "MaxSpace"
    maxSpace.Value = 10
    maxSpace.Parent = player

    local currentSheepId = Instance.new("IntValue")
    currentSheepId.Name = "CurrentSheepId"
    currentSheepId.Parent = player

end

players.PlayerAdded:Connect(onPlayerAdded)