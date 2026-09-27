--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps

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

local function getChance(sheepName: string, data: { chance: number }, chances: { [string]: number }?): number
	return if chances and chances[sheepName] then chances[sheepName] else data.chance
end

local function getRandomSheep(chances: { [string]: number }?)
    local totalChance = 0
    for sheepName, data in SheepData do
        totalChance += getChance(sheepName, data, chances)
    end

    local randomValue = math.random(1, totalChance)
    local cumulativeChance = 0

    for sheepName, data in SheepData do
        cumulativeChance += getChance(sheepName, data, chances)
        if randomValue <= cumulativeChance then
            return sheepName
        end
    end

    return nil
end

--[[
    Adds a "Shear" ProximityPrompt to the sheep's HumanoidRootPart, making
    it selectable by players. Called once the sheep has finished walking
    into its pen -- sheep are not shearable while still travelling to it.
]]
function SheepHandler.makeShearable(sheepModel: Model, id: number)
	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.ActionText = "Shear"
	proximityPrompt.ObjectText = sheepModel.Name
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.MaxActivationDistance = 10
	proximityPrompt.Parent = humanoidRootPart

	proximityPrompt:SetAttribute("SheepName", sheepModel.Name)
	proximityPrompt:SetAttribute("Id", id)
end

--[[
    Clones a random sheep species (weighted by SheepData chance), sets its
    gameplay attributes, and places it at the given world position. Does
    NOT add a ProximityPrompt -- callers that walk the sheep somewhere
    first (see PenHandler) should call SheepHandler.makeShearable once it
    arrives. Returns the spawned Model and its unique id, or (nil, nil) if
    the chosen species has no valid model/data.
]]
function SheepHandler.spawnSheep(position: Vector3, chances: { [string]: number }?): (Model?, number?)
	local randomSheepName = getRandomSheep(chances)
	local sheepModel = sheepModels:FindFirstChild(randomSheepName)
	if not sheepModel or not sheepModel:IsA("Model") then
		warn(`Sheep with name '{randomSheepName}' is not a valid model.`)
		return nil, nil
	end

	local data = SheepData[sheepModel.Name]
	if not data then
		warn(`No Data found for Sheep with the name: '{sheepModel.Name}'`)
		return nil, nil
	end

	sheepModel = sheepModel:Clone()
	collectionService:AddTag(sheepModel, "Sheep")
	sheepModel.Parent = workspace.Base.Sheeps

	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		sheepModel:Destroy()
		return nil, nil
	end

	nextSheepId += 1
	local id = nextSheepId
	sheepById[id] = sheepModel

	local shearHealthUI = humanoidRootPart:FindFirstChild("Health")
	local healthText = shearHealthUI and shearHealthUI:FindFirstChild("TextLabel")
	if healthText then
		healthText.Text = tostring(data.ShearHealth) .. " / " .. tostring(data.ShearHealth)
	end

	-- Set the data
	sheepModel:SetAttribute("id", id)
	sheepModel:SetAttribute("ShearHealth", data.ShearHealth)
	sheepModel:SetAttribute("MaxShearHealth", data.ShearHealth)
	sheepModel:SetAttribute("WoolAmount", data.WoolAmount)

	humanoidRootPart.CFrame = CFrame.new(position)

	return sheepModel, id
end

return SheepHandler