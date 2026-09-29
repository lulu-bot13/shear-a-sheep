--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)
local ObjectPool = require(game.ServerScriptService.Modules.Utils.ObjectPool)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepHudTemplate = replicatedStorage.Assets.UI.SheepHUD :: BillboardGui

--// Object pool keys
local SHEEP_POOL = "SheepModel" -- keyed by sheepType name, since meshes differ per sheepType
local HUD_POOL = "SheepHUD"
local HUD_KEY = "SheepHUD"

local sheepById: { [number]: Model } = {}
local nextSheepId = 0

local SheepHandler = {}

--[[
	Only the actual sheepType entries in SheepData carry a numeric `chance`
	field (helper tables like RarityColors/UpgradeMultipliers and helper
	functions live alongside them in the same module and must be skipped).
]]--
local function isSheepTypeEntry(data: any): boolean
	return type(data) == "table" and type(data.chance) == "number"
end

--[[
    Returns the sheep Model registered under the given id, or nil if no
    such sheep is currently active.
]]
function SheepHandler.getSheep(id: number): Model?
	return sheepById[id]
end

local function resetSheepForPool(sheep: Model)

	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = 0
	end

	local root = sheep:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local hud = root:FindFirstChild("SheepHUD")
		if hud and hud:IsA("BillboardGui") then
			hud.Adornee = nil
			ObjectPool.release(HUD_POOL, HUD_KEY, hud)
		end

		root.Anchored = true
	end
end

--[[
    Removes the sheep registered under the given id from the registry and
    returns its Model to the object pool for reuse (destroyed only if it
    has no known sheepType, which shouldn't normally happen).
]]
function SheepHandler.removeSheep(id: number)
	local sheep = sheepById[id]
	if not sheep then
		return
	end

	sheepById[id] = nil

	local sheepType = sheep:GetAttribute("SheepType")
	if type(sheepType) == "string" then
		ObjectPool.release(SHEEP_POOL, sheepType, sheep, resetSheepForPool(sheep))
	else
		sheep:Destroy()
	end
end

local function getChance(sheepName: string, data: { chance: number }, chances: { [string]: number }?): number
	return if chances and chances[sheepName] then chances[sheepName] else data.chance
end

local function getRandomSheep(chances: { [string]: number }?)
    local totalChance = 0
    for sheepName, data in SheepData do
        if isSheepTypeEntry(data) then
            totalChance += getChance(sheepName, data, chances)
        end
    end

    if totalChance <= 0 then
        return nil
    end

    -- Weights aren't guaranteed to be whole numbers once a pen's upgrade
    -- multipliers are applied, so roll with a float instead of math.random(int, int).
    local randomValue = math.random() * totalChance
    local cumulativeChance = 0

    for sheepName, data in SheepData do
        if isSheepTypeEntry(data) then
            cumulativeChance += getChance(sheepName, data, chances)
            if randomValue <= cumulativeChance then
                return sheepName
            end
        end
    end

    return nil
end

local function acquireHud(): BillboardGui
	local hud = ObjectPool.acquire(HUD_POOL, HUD_KEY)
	if not hud then
		hud = sheepHudTemplate:Clone()
	end
	return hud :: BillboardGui
end

-- Fills in and (re)parents a SheepHUD billboard under the sheep's HumanoidRootPart.
local function attachHud(humanoidRootPart: BasePart, data, oddsText: string)
	local hud = acquireHud()

	local card = hud:FindFirstChild("Card")
	local nameLabel = card and card:FindFirstChild("NameLabel") :: TextLabel?
	local rarityPill = card and card:FindFirstChild("RarityPill")
	local rarityLabel = rarityPill and rarityPill:FindFirstChild("RarityLabel") :: TextLabel?
	local oddsLabel = card and card:FindFirstChild("OddsLabel") :: TextLabel?

	if nameLabel then
		nameLabel.Text = data.name
	end
	if rarityLabel then
		rarityLabel.Text = data.rarity
	end
	if rarityPill and rarityPill:IsA("Frame") then
		rarityPill.BackgroundColor3 = data.color
	end
	if oddsLabel then
		oddsLabel.Text = oddsText
	end

	hud.Name = "SheepHUD"
	hud.Adornee = humanoidRootPart
	hud.Parent = humanoidRootPart
end

--[[
    Clones a sheep and sets it's data

	@param position The position for the sheep
	@param chances Chance for the rarity UI
	@return Model, number The sheep and it's unique id
]]
function SheepHandler.spawnSheep(position: Vector3, chances: { [string]: number }?): (Model?, number?)
	local randomSheepName = getRandomSheep(chances)
	local data = randomSheepName and SheepData[randomSheepName]
	if not randomSheepName or not data then
		warn(`No Data found for Sheep with the name: '{tostring(randomSheepName)}'`)
		return nil, nil
	end

	local sheepModel = ObjectPool.acquire(SHEEP_POOL, randomSheepName)
	if not sheepModel then
		local template = sheepModels:FindFirstChild(randomSheepName)
		if not template or not template:IsA("Model") then
			warn(`Sheep with name '{randomSheepName}' is not a valid model.`)
			return nil, nil
		end
		sheepModel = template:Clone()
		sheepModel:SetAttribute("SheepType", randomSheepName)
	end

	collectionService:AddTag(sheepModel, "Sheep")
	sheepModel.Parent = workspace.Base.Sheeps

	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		sheepModel:Destroy()
		return nil, nil
	end
	
	-- Handle animations
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn(`No humaniod found for sheepModel: {sheepModel.Name}`)
		return nil, nil
	end

	nextSheepId += 1
	local id = nextSheepId
	sheepById[id] = sheepModel

	local shearHealthUI = humanoidRootPart:FindFirstChild("Health")
	local healthText = shearHealthUI and shearHealthUI:FindFirstChild("Health")
	if healthText and healthText:IsA("TextLabel") then
		healthText.Text = tostring(data.ShearHealth) .. " / " .. tostring(data.ShearHealth)
	end

	local oddsText = SheepData.getOddsText(randomSheepName, chances)

	-- Set the data
	sheepModel:SetAttribute("id", id)
	sheepModel:SetAttribute("ShearHealth", data.ShearHealth)
	sheepModel:SetAttribute("MaxShearHealth", data.ShearHealth)
	sheepModel:SetAttribute("WoolAmount", data.WoolAmount)
	sheepModel:SetAttribute("SheepName", data.name)
	sheepModel:SetAttribute("Rarity", data.rarity)
	sheepModel:SetAttribute("RarityColor", data.color)
	sheepModel:SetAttribute("Odds", oddsText)

	humanoidRootPart.Anchored = false
	humanoidRootPart.CFrame = CFrame.new(position)

	attachHud(humanoidRootPart, data, oddsText)

	return sheepModel, id
end

return SheepHandler