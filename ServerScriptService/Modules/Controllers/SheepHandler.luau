--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)
local ObjectPool = require(game.ServerScriptService.Modules.Utils.ObjectPool)
local SheepAnimator = require(game.ServerScriptService.Modules.Utils.SheepAnimator)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepHudTemplate = replicatedStorage.Assets.UI.SheepHUD :: BillboardGui

--// Object pool keys
local SHEEP_POOL = "SheepModel" -- keyed by species name, since meshes differ per species
local HUD_POOL = "SheepHUD"
local HUD_KEY = "SheepHUD" -- one shared bucket; every sheep uses the same billboard template

local sheepById: { [number]: Model } = {}
local nextSheepId = 0

local SheepHandler = {}

--[[
	Only the actual species entries in SheepData carry a numeric `chance`
	field (helper tables like RarityColors/UpgradeMultipliers and helper
	functions live alongside them in the same module and must be skipped).
]]--
local function isSpeciesEntry(data: any): boolean
	return type(data) == "table" and type(data.chance) == "number"
end

--[[
    Returns the sheep Model registered under the given id, or nil if no
    such sheep is currently active.
]]
function SheepHandler.getSheep(id: number): Model?
	return sheepById[id]
end

-- Removes every dynamic bit a pooled sheep model picked up while it was active, so the
-- next spawn reuses it as if it were fresh out of ReplicatedStorage.
local function resetSheepForPool(sheep: Model)
	SheepAnimator.snapToRest(sheep) -- avoid baking a mid-stride pose in as the next "rest"
	SheepAnimator.unregister(sheep)

	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.WalkSpeed = 0
	end

	local root = sheep:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local prompt = root:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end

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
    has no known species, which shouldn't normally happen).
]]
function SheepHandler.removeSheep(id: number)
	local sheep = sheepById[id]
	if not sheep then
		return
	end

	sheepById[id] = nil

	local species = sheep:GetAttribute("Species")
	if type(species) == "string" then
		ObjectPool.release(SHEEP_POOL, species, sheep, resetSheepForPool)
	else
		SheepAnimator.unregister(sheep)
		sheep:Destroy()
	end
end

local function getChance(sheepName: string, data: { chance: number }, chances: { [string]: number }?): number
	return if chances and chances[sheepName] then chances[sheepName] else data.chance
end

local function getRandomSheep(chances: { [string]: number }?)
    local totalChance = 0
    for sheepName, data in SheepData do
        if isSpeciesEntry(data) then
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
        if isSpeciesEntry(data) then
            cumulativeChance += getChance(sheepName, data, chances)
            if randomValue <= cumulativeChance then
                return sheepName
            end
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
-- Acquires a SheepHUD billboard from the pool, or clones a fresh one if the pool is empty.
local function acquireHud(): BillboardGui
	local hud = ObjectPool.acquire(HUD_POOL, HUD_KEY)
	if not hud then
		hud = sheepHudTemplate:Clone()
	end
	return hud :: BillboardGui
end

-- Fills in and (re)parents a SheepHUD billboard under the sheep's HumanoidRootPart.
local function attachHud(sheepModel: Model, humanoidRootPart: BasePart, data, oddsText: string)
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
    Clones a random sheep species (weighted by SheepData chance), sets its
    gameplay attributes, attaches its SheepHUD billboard (name/rarity/odds)
    and places it at the given world position. Does NOT add a
    ProximityPrompt -- callers that walk the sheep somewhere first (see
    PenHandler) should call SheepHandler.makeShearable once it arrives.
    Returns the spawned Model and its unique id, or (nil, nil) if the
    chosen species has no valid model/data.
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
		sheepModel:SetAttribute("Species", randomSheepName)
	end

	collectionService:AddTag(sheepModel, "Sheep")
	sheepModel.Parent = workspace.Base.Sheeps

	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		sheepModel:Destroy()
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
	sheepModel:SetAttribute("Rarity", data.rarity)
	sheepModel:SetAttribute("RarityColor", data.color)
	sheepModel:SetAttribute("Odds", oddsText)

	humanoidRootPart.Anchored = false
	humanoidRootPart.CFrame = CFrame.new(position)

	attachHud(sheepModel, humanoidRootPart, data, oddsText)
	SheepAnimator.register(sheepModel)

	return sheepModel, id
end

return SheepHandler