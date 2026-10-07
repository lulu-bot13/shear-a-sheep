--[[
	Spawns, tracks and recycles sheep. Every sheep belongs to one player and lives in the
	Sheeps folder of that player's plot, so plots never share sheep.

	Location: ServerScriptService.Modules.Controllers.SheepHandler
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")

--// Modules
local PlotHandler = require(script.Parent.PlotHandler)
local SheepData = require(game.ServerScriptService.Modules.Constants.SheepData)
local ObjectPool = require(game.ServerScriptService.Modules.Utils.ObjectPool)
local ShearTimingData = require(replicatedStorage.Shared.Constants.ShearTimingData)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepHudTemplate = replicatedStorage.Assets.UI.SheepHUD :: BillboardGui

--// Configs
local SHEEPS_FOLDER_NAME = "Sheeps" -- lives inside each plot
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local WOOL_PART_NAME = "Torso" -- the mesh that is the sheep's wool
local WOOL_BASE_SIZE = "WoolBaseSize" -- the wool's untouched look, remembered on the part itself
local WOOL_BASE_COLOR = "WoolBaseColor"

--// Object pool keys
local SHEEP_POOL = "SheepModel" -- keyed by sheepType name, since meshes differ per sheepType
local HUD_POOL = "SheepHUD"
local HUD_KEY = "SheepHUD"

local sheepById: { [number]: Model } = {}
local woolConnections: { [number]: RBXScriptConnection } = {}
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
	Returns the Sheep Model registered under the given id, or nil if no
	such sheep is currently active.
]]
function SheepHandler.getSheep(id: number): Model?
	return sheepById[id]
end

--[[
	Returns the id of the player the sheep belongs to, or nil if the sheep has
	no owner (or isn't a sheep).
]]
function SheepHandler.getOwnerId(sheep: Model): number?
	local ownerId = sheep:GetAttribute(OWNER_ATTRIBUTE)
	return if type(ownerId) == "number" then ownerId else nil
end

local function getWoolPart(sheep: Instance): BasePart?
	local part = sheep:FindFirstChild(WOOL_PART_NAME)
	return if part and part:IsA("BasePart") then part else nil
end

-- The wool's full size and colour, recorded the first time this model is used.
local function getWoolBase(wool: BasePart): (Vector3, Color3)
	local size = wool:GetAttribute(WOOL_BASE_SIZE)
	local color = wool:GetAttribute(WOOL_BASE_COLOR)
	if typeof(size) ~= "Vector3" or typeof(color) ~= "Color3" then
		size, color = wool.Size, wool.Color
		wool:SetAttribute(WOOL_BASE_SIZE, size)
		wool:SetAttribute(WOOL_BASE_COLOR, color)
	end
	return size, color
end

-- Shrinks the wool and fades it towards bare skin as the sheep's ShearHealth drops (seen by everyone).
local function updateWoolVisual(sheep: Model)
	-- A worker's pen keeps the wool as it is (nothing to resize/recolour on every swing).
	if sheep:GetAttribute("WorkerShearing") then
		return
	end

	local wool = getWoolPart(sheep)
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if not wool or type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local baseSize, baseColor = getWoolBase(wool)
	local shorn = 1 - math.clamp(health / maxHealth, 0, 1)
	wool.Size = baseSize * Vector3.one:Lerp(ShearTimingData.ShornTorsoScale, shorn)
	wool.Color = baseColor:Lerp(ShearTimingData.ShornColor, shorn * ShearTimingData.ShornColorBlend)
end

-- Puts a pooled sheep's wool back to full.
local function restoreWool(sheep: Instance)
	local wool = getWoolPart(sheep)
	if wool then
		local baseSize, baseColor = getWoolBase(wool)
		wool.Size = baseSize
		wool.Color = baseColor
	end
end

local function resetSheepForPool(sheep: Instance)
	restoreWool(sheep)
	sheep:SetAttribute("WorkerShearing", nil)
	sheep:SetAttribute(OWNER_ATTRIBUTE, nil)

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

	local woolConnection = woolConnections[id]
	if woolConnection then
		woolConnection:Disconnect()
		woolConnections[id] = nil
	end

	local sheepType = sheep:GetAttribute("SheepType")
	if type(sheepType) == "string" then
		ObjectPool.release(SHEEP_POOL, sheepType, sheep, resetSheepForPool)
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
	Returns the Sheeps folder of the plot the player owns (created if the plot lacks one),
	or nil if the player has no plot.
]]
local function getSheepFolder(player: Player): Folder?
	local plot = PlotHandler.getPlayerPlot(player)
	if not plot then
		return nil
	end

	local existing = plot:FindFirstChild(SHEEPS_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = SHEEPS_FOLDER_NAME
	folder.Parent = plot
	return folder
end

--[[
	Clones a sheep into the player's plot and sets its data

	@param player The player the sheep belongs to (it spawns in their plot's Sheeps folder)
	@param position The position for the sheep
	@param chances Chance for the rarity UI
	@return Model, number The sheep and its unique id
]]
function SheepHandler.spawnSheep(player: Player, position: Vector3, chances: { [string]: number }?): (Model?, number?)
	local sheepFolder = getSheepFolder(player)
	if not sheepFolder then
		warn(`SheepHandler: {player.Name} has no plot to spawn a sheep in.`)
		return nil, nil
	end

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

	local humanoidRootPart = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = sheepModel:FindFirstChildOfClass("Humanoid")
	if not humanoidRootPart or not humanoid then
		warn(`SheepHandler: sheep model '{sheepModel.Name}' needs a HumanoidRootPart and a Humanoid.`)
		sheepModel:Destroy()
		return nil, nil
	end

	collectionService:AddTag(sheepModel, SHEEP_TAG)
	sheepModel.Parent = sheepFolder

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
	sheepModel:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
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

	-- Shearing (by hand or by a worker) only ever changes ShearHealth; the wool follows it.
	updateWoolVisual(sheepModel)
	woolConnections[id] = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateWoolVisual(sheepModel)
	end)

	return sheepModel, id
end

return SheepHandler
