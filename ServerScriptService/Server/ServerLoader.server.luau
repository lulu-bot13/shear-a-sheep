local replicatedStorage = game:GetService("ReplicatedStorage")

local moduleLoader = require(replicatedStorage.Source.ModuleLoader)
local network = require(replicatedStorage.Shared.Utils.Network)

moduleLoader.GameReadySignal:Once(function()
    print(`{script.Name} acknoledges game is fully loaded!`)
end)

network.startServer()
moduleLoader.Init()