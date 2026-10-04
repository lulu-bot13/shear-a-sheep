local players = game:GetService("Players")

local base = workspace:FindFirstChild("Base")

--// Modules
local network = require(game.ReplicatedStorage.Shared:FindFirstChild("Utils"):FindFirstChild("Network"))
local moduleLoader = require(game.ReplicatedStorage:FindFirstChild("Source"):FindFirstChild("ModuleLoader"))

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.Teleport, function(player: Player, destination: string)
    if not player or not destination then return end

    local plotName = player:GetAttribute("PlotName")
    local plot = workspace.Base.Plots:FindFirstChild(plotName)
    if not plot then return end

    local character = player.Character or player.CharacterAdded:Wait()

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    -- Teleporting
    local spawnArea = if destination == "plot" then plot:FindFirstChild("SpawnArea") else base:FindFirstChild("CenterPlaza"):FindFirstChild("SpawnArea")
    if not spawnArea then
        warn(`Spawn area not found: {spawnArea.Name}`)
        return
    end

    character:PivotTo(spawnArea.CFrame * CFrame.new(0,2,0))
end)

players.PlayerAdded:Connect(function(player: Player)
    
    

end)