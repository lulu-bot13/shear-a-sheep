--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepSpawnArea = workspace:WaitForChild("Base"):FindFirstChild("SheepSpawnArea")

--// Configurations
local sheepSpawnCount = 10

local sheepById: { [number]: Model } = {}
local nextSheepId = 0

local SheepHandler = {}

--[[
    Returns the sheep Model registered under the given id, or nil if no
    such sheep is currently active.
]]
function SheepHandler.getSheep(id: number): Model?
	return sheepById[id]
end

--[[
    Removes the sheep registered under the given id from the registry and
    destroys its Model.
]]
function SheepHandler.removeSheep(id: number)
	local sheep = sheepById[id]
	if not sheep then
		return
	end

	sheepById[id] = nil
	sheep:Destroy()
end

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

local function _setupProximityPrompt(humanoidRootPart: BasePart, data: {sheepName: string, id: number})

	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.ActionText = "Shear"
	proximityPrompt.ObjectText = data.sheepName
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.MaxActivationDistance = 10
	proximityPrompt.Parent = humanoidRootPart

	proximityPrompt:SetAttribute("SheepName", data.sheepName)
	proximityPrompt:SetAttribute("Id", data.id)
end

function SheepHandler.Start()
    for _ = 1, sheepSpawnCount do
        local randomSheepName = getRandomSheep()
        local sheepModel = sheepModels:FindFirstChild(randomSheepName)
        if not sheepModel:IsA("Model") then 
            warn(`Sheep with name '{sheepModel}' is not a valid model.`)
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

		nextSheepId += 1
		local id = nextSheepId
		sheepById[id] = sheepModel

		_setupProximityPrompt(humanoidRootPart, {sheepName = sheepModel.Name, id = id})

		local shearHealthUI = humanoidRootPart:FindFirstChild("Health")
		local healthText = shearHealthUI and shearHealthUI:FindFirstChild("TextLabel")
		if healthText then
			healthText.Text = tostring(data.shearHealth) .. " / " .. tostring(data.shearHealth)
		end

		-- Set the data
		sheepModel:SetAttribute("id", id)
		sheepModel:SetAttribute("ShearHealth", data.shearHealth)
		sheepModel:SetAttribute("MaxShearHealth", data.shearHealth)
		sheepModel:SetAttribute("WoolAmount", data.woolAmount)
        
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