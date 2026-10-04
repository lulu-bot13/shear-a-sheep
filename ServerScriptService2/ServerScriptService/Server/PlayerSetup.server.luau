--// Services
local players = game:GetService("Players")
local physicsService = game:GetService("PhysicsService")

--// Modules
local InventoryHandler = require(game.ServerScriptService.Modules.Controllers.InventoryHandler)

-- Pens every player starts with in their inventory (template names in ReplicatedStorage.Assets.Models.Pens).
-- Placeholder until pens can be earned or bought; set to {} to start empty.
local STARTER_PENS = { Oak_Pen = 2, Stone_Pen = 1 }

-- Sheep stay collidable with the ground but not with players, so they never block or bump them.
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

-- Puts a character's parts in the "Players" collision group; reconnected on every CharacterAdded.
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

-- Hides the floating name/health tag above a character's head.
local function hideHumanoidName(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function onPlayerAdded(player: Player)
    print(`Player {player.Name} has joined the game!`)

    InventoryHandler.setupPlayer(player)
    InventoryHandler.addItem(player, "Wool", 0)
    for penType, amount in STARTER_PENS do
        InventoryHandler.addPen(player, penType, amount)
    end

    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local money = Instance.new("IntValue")
    money.Name = "Money"
    money.Value = 1000
    money.Parent = leaderstats

    local currentSheepId = Instance.new("IntValue")
    currentSheepId.Name = "CurrentSheepId"
    currentSheepId.Parent = player

    if player.Character then
        assignPlayerCollisionGroup(player.Character)
        task.spawn(hideHumanoidName, player.Character)
    end
    player.CharacterAdded:Connect(assignPlayerCollisionGroup)
    player.CharacterAdded:Connect(function(character: Model)
        task.spawn(hideHumanoidName, character)
    end)

end

players.PlayerAdded:Connect(onPlayerAdded)

-- Players who joined before this script connected.
for _, player in players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
