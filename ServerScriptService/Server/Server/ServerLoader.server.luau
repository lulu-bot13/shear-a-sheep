--[[
	Starts the server network and initializes the module loader
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local moduleLoader = require(replicatedStorage.Source.ModuleLoader)
local network = require(replicatedStorage.Shared.Utils.Network)

moduleLoader.GameReadySignal:Once(function()
	print(`{script.Name} acknoledges game is fully loaded!`)
end)

network.startServer()
moduleLoader.Init()
