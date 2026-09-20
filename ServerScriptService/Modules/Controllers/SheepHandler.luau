--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)

--// References
local sheepModels = replicatedStorage.SheepModels
local sheepSpawnArea = workspace:WaitForChild("Base"):FindFirstChild("SheepSpawnArea")

local sheeps  = collectionService:GetTagged("Sheep")

--// Configurations
local sheepSpawnCount = 10

local SheepHandler = {}

local function getRandomSheep()
    local totalChance = 0
    for _, data in pairs(SheepData) do
        totalChance += data.chance
    end

    local randomValue = math.random(1, totalChance)
    local cumulativeChance = 0

    for sheepName, data in pairs(SheepData) do
        cumulativeChance += data.chance
        if randomValue <= cumulativeChance then
            return sheepName
        end
    end

    return nil
end

function SheepHandler:_InitSheeps()

    for i = 1, sheepSpawnCount do
        local randomSheepName = getRandomSheep()
        local sheepModel = sheepModels:FindFirstChild(randomSheepName)
        if sheepModel:IsA("Model") then 
            warn(`Sheep model with name '{sheepModel}' is not a valid model.`)
            continue
        end
        sheepModel = sheepModel:Clone()
        collectionService:AddTag(sheepModel, "Sheep")
        sheepModel.Parent = workspace.Base.Sheeps

		local data = SheepData[sheepModel.Name]
		if not data then
			warn(`No Data found for Sheep with the name: '{sheepModel.Name}'`)
			continue
		end

		local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart")
		if not humanoidRootPart then
			continue
		end

		local shearHealthUI = humanoidRootPart:FindFirstChild("Health")
		local healthText = shearHealthUI and shearHealthUI:FindFirstChild("TextLabel")
		if healthText then
			healthText.Text = tostring(data.ShearHealth) .. " / " .. tostring(data.ShearHealth)
		end

		-- Set the data
		sheepModel:SetAttribute("id", data.id)
		sheepModel:SetAttribute("ShearHealth", data.ShearHealth)
		sheepModel:SetAttribute("MaxShearHealth", data.ShearHealth)
		sheepModel:SetAttribute("WoolAmount", data.WoolAmount)
        
		-- Setting the position
		local randomPosition = Vector3.new(
			math.random(
				sheepSpawnArea.Position.X - sheepSpawnArea.Size.X / 2,
				sheepSpawnArea.Position.X + sheepSpawnArea.Size.X / 2
			),
			sheepSpawnArea.Position.Y + humanoidRootPart.Size.Y / 2,
			math.random(
				sheepSpawnArea.Position.Z - sheepSpawnArea.Size.Z / 2,
				sheepSpawnArea.Position.Z + sheepSpawnArea.Size.Z / 2
			)
		)
		humanoidRootPart.CFrame = CFrame.new(randomPosition)
    end
end

return SheepHandler