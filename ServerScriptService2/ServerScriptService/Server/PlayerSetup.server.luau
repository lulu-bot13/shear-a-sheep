--[[
	Sets up each joining player: the leaderstats folder, the Sheep/Players collision groups and a hidden name tag.

	Location: ServerScriptService.Server.PlayerSetup
]]--

--// Services
local players = game:GetService("Players")
local physicsService = game:GetService("PhysicsService")

-- Sheep stay collidable with the ground but not with players or each other, so none end up standing on another.
local function setupCollisionGroups()
	pcall(function()
		physicsService:RegisterCollisionGroup("Sheep")
	end)
	pcall(function()
		physicsService:RegisterCollisionGroup("Players")
	end)
	physicsService:CollisionGroupSetCollidable("Sheep", "Players", false)
	physicsService:CollisionGroupSetCollidable("Sheep", "Sheep", false)
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

local function onCharacterAdded(character: Model)
	assignPlayerCollisionGroup(character)
	task.spawn(hideHumanoidName, character)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

players.PlayerAdded:Connect(onPlayerAdded)

-- Players who joined before this script connected.
for _, player in players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
