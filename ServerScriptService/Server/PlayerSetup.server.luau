--// Services
local players = game:GetService("Players")

--// Modules
local InventoryHandler = require(game.ServerScriptService.Modules.Controllers.InventoryHandler)

local function onPlayerAdded(player: Player)
    print(`Player {player.Name} has joined the game!`)

    InventoryHandler.setupPlayer(player)
    InventoryHandler.addItem(player, "Wool", 0)

    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local money = Instance.new("IntValue")
    money.Name = "Money"
    money.Value = 0
    money.Parent = leaderstats

    local currentSheepId = Instance.new("IntValue")
    currentSheepId.Name = "CurrentSheepId"
    currentSheepId.Parent = player

end

players.PlayerAdded:Connect(onPlayerAdded)