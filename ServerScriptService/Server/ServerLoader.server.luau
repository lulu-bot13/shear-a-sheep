local replicatedStorage = game:GetService("ReplicatedStorage")

local moduleLoader = require(replicatedStorage.Source.ModuleLoader)

moduleLoader.GameReadySignal:Once(function()
    print(`{script.Name} acknoledges game is fully loaded!`)
end)

moduleLoader.Init()