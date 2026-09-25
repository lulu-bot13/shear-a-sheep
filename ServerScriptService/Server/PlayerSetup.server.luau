--// Services
local players = game:GetService("Players")
local physicsService = game:GetService("PhysicsService")

--// Modules
local InventoryHandler = require(game.ServerScriptService.Modules.Controllers.InventoryHandler)

--[[
    Sheep parts live in the "Sheep" collision group (set directly on
    ReplicatedStorage.Assets.Models.Sheeps.Basic) and stay fully collidable
    with the ground/props. Player characters go in "Players" below. Making
    that one pair non-collidable is what keeps sheep from blocking or
    bumping players, without touching CanCollide (which sheep still need
    for normal ground collision) and without needing any runtime toggling.
]]
local function setupCollisionGroups()
	pcall(function()
		physicsService:RegisterCollisionGroup("Sheep")
	end)
	pcall(function()
		physicsService:RegisterCollisionGroup("Players")
	end)
	physicsService:CollisionGroupSetCollidable("Sheep", "Players", false)
end

setupCollisionGroups()

--[[
    Puts every part of a player's character into the "Players" collision
    group so it's exempt from sheep collision. Reconnected on every
    CharacterAdded since a fresh character is a new set of Instances.
]]
local function assignPlayerCollisionGroup(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end

	character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end)
end

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

    if player.Character then
        assignPlayerCollisionGroup(player.Character)
    end
    player.CharacterAdded:Connect(assignPlayerCollisionGroup)

end

players.PlayerAdded:Connect(onPlayerAdded)