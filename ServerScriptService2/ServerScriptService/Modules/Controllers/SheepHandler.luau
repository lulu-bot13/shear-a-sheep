--!strict

--[[
	Spawns, tracks and recycles sheep. Each sheep lives in the Sheeps folder of its owner's plot
	and is rolled with the owner's Luck.

	Location: ServerScriptService.Modules.Controllers.SheepHandler
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")

--// Modules
local Signal = require(replicatedStorage.Source.ModuleLoader.Signal)
local PlotHandler = require(script.Parent.PlotHandler)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local ObjectPool = require(script.Parent.Parent.Utils.ObjectPool)
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepHudTemplate = replicatedStorage.Assets.UI.SheepHUD :: BillboardGui
local sheepHudNameLabel = sheepHudTemplate:FindFirstChild("NameLabel", true) :: TextLabel? -- the health bar copies its font
local walkAnimation = replicatedStorage.Assets.Animations.SheepWalking :: Animation

--// Configs
local SHEEPS_FOLDER_NAME = "Sheeps" -- lives inside each plot
local SHEEP_TAG = "Sheep"
local SHEEP_COLLISION_GROUP = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local WOOL_PART_NAME = "Torso" -- the mesh that is the sheep's wool
local WOOL_BASE_SIZE = "WoolBaseSize" -- the wool's untouched look, remembered on the part itself
local WOOL_BASE_COLOR = "WoolBaseColor"
local HEALTH_HUD_NAME = "HealthHUD"
local HEALTH_HUD_SIZE = Vector2.new(4.5, 1.3) -- studs
local HEALTH_FULL_COLOR = Color3.fromRGB(110, 220, 120)
local HEALTH_EMPTY_COLOR = Color3.fromRGB(230, 90, 80)
local WALK_MIN_SPEED = 0.1 -- below this the sheep counts as standing still

--// Object pool keys
local SHEEP_POOL = "SheepModel" -- keyed by sheep type name, since meshes differ per type
local HUD_POOL = "SheepHUD"
local HUD_KEY = "SheepHUD"

--// State
local sheepById: { [number]: Model } = {}
local woolConnections: { [number]: RBXScriptConnection } = {}
local countByOwner: { [number]: number } = {}
local nextSheepId = 0
local random = Random.new()

local SheepHandler = {}

SheepHandler.CountChanged = Signal.new() -- (player, count)

--// Lookups ---------------------------------------------------------------------------

function SheepHandler.getSheep(id: number): Model?
	return sheepById[id]
end

function SheepHandler.getOwnerId(sheep: Model): number?
	local ownerId = sheep:GetAttribute(OWNER_ATTRIBUTE)
	return if type(ownerId) == "number" then ownerId else nil
end

-- Every active sheep, keyed by id (read only).
function SheepHandler.getAllSheep(): { [number]: Model }
	return sheepById
end

function SheepHandler.getSheepCount(player: Player): number
	return countByOwner[player.UserId] or 0
end

-- Shows or hides the name / rarity / odds billboard floating over the sheep.
function SheepHandler.setHudVisible(sheep: Model, visible: boolean)
	local root = sheep:FindFirstChild("HumanoidRootPart")
	local hud = if root then root:FindFirstChild("SheepHUD") else nil
	if hud and hud:IsA("BillboardGui") then
		hud.Enabled = visible
	end
end

local function setCount(ownerId: number, count: number)
	countByOwner[ownerId] = if count > 0 then count else nil

	local owner = players:GetPlayerByUserId(ownerId)
	if owner then
		SheepHandler.CountChanged:Fire(owner, count)
	end
end

--// Wool look --------------------------------------------------------------------------

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
	return size :: Vector3, color :: Color3
end

-- Shrinks the wool and fades it towards bare skin as the sheep's ShearHealth drops (seen by everyone).
local function updateWoolVisual(sheep: Model)
	local wool = getWoolPart(sheep)
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if not wool or type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local baseSize, baseColor = getWoolBase(wool)
	local shorn = 1 - math.clamp(health / maxHealth, 0, 1)
	wool.Size = baseSize * Vector3.new(1, 1, 1):Lerp(WoolData.ShornTorsoScale, shorn)
	wool.Color = baseColor:Lerp(WoolData.ShornColor, shorn * WoolData.ShornColorBlend)
end

-- The colour of the sheep's full wool (for the wool that flies off it).
function SheepHandler.getWoolColor(sheep: Model): Color3
	local wool = getWoolPart(sheep)
	if not wool then
		return Color3.new(1, 1, 1)
	end
	local _, color = getWoolBase(wool)
	return color
end

--// Health bar ------------------------------------------------------------------------------

-- Builds the health billboard once per model; it sits where the info card does and takes its place while damaged.
local function createHealthHud(root: BasePart)
	local font = sheepHudNameLabel and sheepHudNameLabel.FontFace or Font.fromEnum(Enum.Font.GothamBold)

	local hud = Instance.new("BillboardGui")
	hud.Name = HEALTH_HUD_NAME
	hud.Size = UDim2.fromScale(HEALTH_HUD_SIZE.X, HEALTH_HUD_SIZE.Y)
	hud.StudsOffset = sheepHudTemplate.StudsOffset
	hud.StudsOffsetWorldSpace = sheepHudTemplate.StudsOffsetWorldSpace
	hud.MaxDistance = sheepHudTemplate.MaxDistance
	hud.LightInfluence = 0
	hud.Enabled = false
	hud.Adornee = root

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0.42)
	nameLabel.FontFace = font
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Parent = hud
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLabel

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Position = UDim2.fromScale(0, 0.5)
	bar.Size = UDim2.fromScale(1, 0.5)
	bar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
	bar.Parent = hud
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)
	local barStroke = Instance.new("UIStroke")
	barStroke.Thickness = 2
	barStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barStroke.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.BackgroundTransparency = 1
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.FontFace = font
	healthText.TextScaled = true
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.ZIndex = 2
	healthText.Parent = bar
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 1.5
	textStroke.Parent = healthText

	hud.Parent = root
end

-- Shows the wool left as a bar over the sheep once it has been sheared at all; the info card hides meanwhile.
local function updateHealthHud(sheep: Model)
	local root = sheep:FindFirstChild("HumanoidRootPart")
	local hud = root and root:FindFirstChild(HEALTH_HUD_NAME)
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if not hud or not hud:IsA("BillboardGui") or type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local damaged = health < maxHealth
	hud.Enabled = damaged
	SheepHandler.setHudVisible(sheep, not damaged)
	if not damaged then
		return
	end

	local ratio = math.clamp(health / maxHealth, 0, 1)
	local nameLabel = hud:FindFirstChild("NameLabel") :: TextLabel
	local bar = hud:FindFirstChild("Bar") :: Frame
	local fill = bar:FindFirstChild("Fill") :: Frame
	local healthText = bar:FindFirstChild("HealthText") :: TextLabel

	nameLabel.Text = tostring(sheep:GetAttribute("SheepName") or "Sheep")
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.Visible = ratio > 0
	fill.BackgroundColor3 = HEALTH_EMPTY_COLOR:Lerp(HEALTH_FULL_COLOR, ratio)
	healthText.Text = `{math.ceil(health)} / {maxHealth}`
end

--// Pooling -------------------------------------------------------------------------------

local function resetSheepForPool(sheep: Instance)
	local wool = getWoolPart(sheep)
	if wool then
		local baseSize, baseColor = getWoolBase(wool)
		wool.Size = baseSize
		wool.Color = baseColor
	end

	sheep:SetAttribute(OWNER_ATTRIBUTE, nil)
	sheep:SetAttribute("Grazing", nil)

	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	if humanoid then
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

-- Removes the sheep from the registry and returns its Model to the pool. Returns its owner's id.
local function releaseSheep(id: number): number?
	local sheep = sheepById[id]
	if not sheep then
		return nil
	end

	sheepById[id] = nil
	local ownerId = SheepHandler.getOwnerId(sheep)

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

	return ownerId
end

-- Removes a sheep (sheared bare or broke out); its owner's sheep count drops by one.
function SheepHandler.removeSheep(id: number)
	local ownerId = releaseSheep(id)
	if ownerId then
		setCount(ownerId, (countByOwner[ownerId] or 1) - 1)
	end
end

-- Removes every sheep the player owns without counting it as a loss (they left, or rebirthed).
function SheepHandler.clearSheep(player: Player)
	for id, sheep in sheepById do
		if SheepHandler.getOwnerId(sheep) == player.UserId then
			releaseSheep(id)
		end
	end
	countByOwner[player.UserId] = nil
end

--// Building a sheep -------------------------------------------------------------------

-- Loops SheepWalking while the sheep moves. The track loads on its first move, once the model is in the game.
local function bindWalkAnimation(humanoid: Humanoid)
	local track: AnimationTrack? = nil
	humanoid.Running:Connect(function(speed: number)
		if not track then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			track = animator:LoadAnimation(walkAnimation)
		end
		local walkTrack = track :: AnimationTrack
		walkTrack.Looped = true

		if speed > WALK_MIN_SPEED and not walkTrack.IsPlaying then
			walkTrack:Play()
		elseif speed <= WALK_MIN_SPEED and walkTrack.IsPlaying then
			walkTrack:Stop()
		end
	end)
end

--[[
	The collision group, health bar and walk animation are set up once per model; pooled models keep them.
	Only the invisible root collides: the camera pops in front of any opaque collidable part, and players stand
	inside the sheep while shearing (the groups don't collide), so collidable body parts yanked the camera around.
]]
local function prepareNewModel(sheepModel: Model, root: BasePart)
	for _, descendant in sheepModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = SHEEP_COLLISION_GROUP
			descendant.CanCollide = descendant == root
		end
	end
	createHealthHud(root)
	bindWalkAnimation(sheepModel:FindFirstChildOfClass("Humanoid") :: Humanoid)
end

local function acquireModel(sheepType: string): Model?
	local pooled = ObjectPool.acquire(SHEEP_POOL, sheepType)
	if pooled then
		return pooled :: Model
	end

	local template = sheepModels:FindFirstChild(sheepType)
	if not template or not template:IsA("Model") then
		warn(`SheepHandler: '{sheepType}' is not a model in Assets.Models.Sheeps.`)
		return nil
	end

	local sheepModel = template:Clone()
	local root = sheepModel:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not sheepModel:FindFirstChildOfClass("Humanoid") then
		warn(`SheepHandler: sheep model '{sheepType}' needs a HumanoidRootPart and a Humanoid.`)
		sheepModel:Destroy()
		return nil
	end

	sheepModel:SetAttribute("SheepType", sheepType)
	prepareNewModel(sheepModel, root)
	return sheepModel
end

-- Fills in and (re)parents a SheepHUD billboard under the sheep's HumanoidRootPart.
local function attachHud(root: BasePart, info: SheepData.SheepInfo, oddsText: string)
	local hud = (ObjectPool.acquire(HUD_POOL, HUD_KEY) or sheepHudTemplate:Clone()) :: BillboardGui

	local card = hud:FindFirstChild("Card")
	local nameLabel = card and card:FindFirstChild("NameLabel") :: TextLabel?
	local rarityPill = card and card:FindFirstChild("RarityPill")
	local rarityLabel = rarityPill and rarityPill:FindFirstChild("RarityLabel") :: TextLabel?
	local oddsLabel = card and card:FindFirstChild("OddsLabel") :: TextLabel?

	if nameLabel then
		nameLabel.Text = info.name
	end
	if rarityLabel then
		rarityLabel.Text = info.rarity
	end
	if rarityPill and rarityPill:IsA("Frame") then
		rarityPill.BackgroundColor3 = info.color
	end
	if oddsLabel then
		oddsLabel.Text = oddsText
	end

	hud.Name = "SheepHUD"
	hud.Enabled = true
	hud.Adornee = root
	hud.Parent = root
end

-- The Sheeps folder of the plot the player owns (created if missing), or nil if they have no plot.
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
	Rolls a sheep type with the player's Luck and drops it at `position` on their plot.
	Returns the sheep and its id, or nil if it couldn't be spawned.
]]
function SheepHandler.spawnSheep(player: Player, position: Vector3, luck: number): (Model?, number?)
	local sheepFolder = getSheepFolder(player)
	if not sheepFolder then
		return nil, nil
	end

	local sheepType = SheepData.roll(luck, random)
	local info = sheepType and SheepData.Sheep[sheepType]
	if not sheepType or not info then
		return nil, nil
	end

	local sheepModel = acquireModel(sheepType)
	if not sheepModel then
		return nil, nil
	end

	local root = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart
	local oddsText = SheepData.getOddsText(sheepType, luck)

	nextSheepId += 1
	local id = nextSheepId
	sheepById[id] = sheepModel

	sheepModel:SetAttribute("id", id)
	sheepModel:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	sheepModel:SetAttribute("ShearHealth", info.ShearHealth)
	sheepModel:SetAttribute("MaxShearHealth", info.ShearHealth)
	sheepModel:SetAttribute("WoolAmount", info.WoolAmount)
	sheepModel:SetAttribute("LuckAmount", info.LuckAmount)
	sheepModel:SetAttribute("SheepType", sheepType)
	sheepModel:SetAttribute("SheepName", info.name)
	sheepModel:SetAttribute("Rarity", info.rarity)
	sheepModel:SetAttribute("RarityColor", info.color)
	sheepModel:SetAttribute("Odds", oddsText)

	sheepModel:PivotTo(CFrame.new(position) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	root.Anchored = false
	collectionService:AddTag(sheepModel, SHEEP_TAG)
	sheepModel.Parent = sheepFolder

	-- The server walks the sheep, so it keeps physics ownership (no handing it to a nearby player).
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	attachHud(root, info, oddsText)

	-- Shearing only ever changes ShearHealth; the wool and health bar follow it.
	updateWoolVisual(sheepModel)
	updateHealthHud(sheepModel)
	woolConnections[id] = sheepModel:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateWoolVisual(sheepModel)
		updateHealthHud(sheepModel)
	end)

	setCount(player.UserId, (countByOwner[player.UserId] or 0) + 1)
	return sheepModel, id
end

return SheepHandler
