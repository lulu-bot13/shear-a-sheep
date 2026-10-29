--!strict

--[[
	Spawns, tracks and recycles sheep. Each sheep lives in the Sheeps folder of its owner's plot,
	is rolled with the owner's Luck and gets a random size tier and weight.

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
local SheepSizeData = require(script.Parent.Parent.Constants.SheepSizeData)
local SheepStyle = require(script.Parent.Parent.Constants.SheepStyle)
local ObjectPool = require(script.Parent.Parent.Utils.ObjectPool)
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)

--// References
local sheepModels = replicatedStorage.Assets.Models.Sheeps
local sheepHudTemplate = replicatedStorage.Assets.UI.SheepHUD :: BillboardGui
local sheepHudNameLabel = sheepHudTemplate:FindFirstChild("NameLabel", true) :: TextLabel? -- the health bar copies its font
local hudStudsOffset = sheepHudTemplate.StudsOffset
local hudWorldOffset = sheepHudTemplate.StudsOffsetWorldSpace
local walkAnimation = replicatedStorage.Assets.Animations.SheepWalking :: Animation

--// Configs
local SHEEPS_FOLDER_NAME = "Sheeps" -- lives inside each plot
local SHEEP_TAG = "Sheep"
local SHEEP_COLLISION_GROUP = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local WOOL_PART_NAME = "Torso" -- the mesh that is the sheep's wool, unless it has a separate Wool part
local SEPARATE_WOOL_NAME = "Wool" -- optional wool part over the Torso
local WOOL_BASE_SIZE = "WoolBaseSize" -- the wool's untouched look, remembered on the part itself
local WOOL_BASE_COLOR = "WoolBaseColor"
local WOOL_BASE_TRANSPARENCY = "WoolBaseTransparency"
local BASE_SCALE = "BaseScale" -- the model's scale as built in Studio, restored after it shrinks away
local SIZE_TIER = "SizeTier" -- SheepSizeData tier id
local SIZE_COLOR = "SizeColor" -- the tier's name colour; nil for plain sizes
local WEIGHT = "Weight" -- kg
local SPAWNED_AT = "SpawnedAt" -- server time, so clients only celebrate fresh spawns (not ones streaming in)
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
local countByOwner: { [number]: number? } = {}
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

-- The sheep's wool: its own "Wool" part when it has one (the second result is then true), else the Torso.
local function getWoolPart(sheep: Instance): (BasePart?, boolean)
	local separate = sheep:FindFirstChild(SEPARATE_WOOL_NAME)
	if separate and separate:IsA("BasePart") then
		return separate, true
	end
	local part = sheep:FindFirstChild(WOOL_PART_NAME)
	return if part and part:IsA("BasePart") then part else nil, false
end

-- The wool's full size (at the model's BaseScale), colour and transparency, recorded before the model is first scaled.
local function getWoolBase(wool: BasePart): (Vector3, Color3, number)
	local size = wool:GetAttribute(WOOL_BASE_SIZE)
	local color = wool:GetAttribute(WOOL_BASE_COLOR)
	local transparency = wool:GetAttribute(WOOL_BASE_TRANSPARENCY)
	if typeof(size) ~= "Vector3" or typeof(color) ~= "Color3" or type(transparency) ~= "number" then
		size, color, transparency = wool.Size, wool.Color, wool.Transparency
		wool:SetAttribute(WOOL_BASE_SIZE, size)
		wool:SetAttribute(WOOL_BASE_COLOR, color)
		wool:SetAttribute(WOOL_BASE_TRANSPARENCY, transparency)
	end
	return size :: Vector3, color :: Color3, transparency :: number
end

-- How many times bigger than its built size the model is right now (its size tier).
local function getScaleRatio(sheep: Model): number
	local baseScale = sheep:GetAttribute(BASE_SCALE)
	return if type(baseScale) == "number" and baseScale > 0 then sheep:GetScale() / baseScale else 1
end

--[[
	Follows the sheep's ShearHealth (seen by everyone). A separate Wool part shrinks and is gone at 0, leaving
	the Torso; without one, the Torso itself shrinks and fades to pink.
]]
local function updateWoolVisual(sheep: Model)
	local wool, separate = getWoolPart(sheep)
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if not wool or type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return
	end

	local baseSize, baseColor, baseTransparency = getWoolBase(wool)
	baseSize *= getScaleRatio(sheep)
	local shorn = 1 - math.clamp(health / maxHealth, 0, 1)
	if separate then
		wool.Size = baseSize * Vector3.new(1, 1, 1):Lerp(WoolData.ShornWoolScale, shorn)
		wool.Transparency = if health <= 0 then 1 else baseTransparency
		return
	end

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

--// Size --------------------------------------------------------------------------------------

-- The sheep's name for a RichText label, its size prefix (if any) in the tier's colour; babies keep it plain.
local function formatName(name: string, size: SheepSizeData.SizeInfo?, baby: boolean?): string
	if not size or not size.prefix then
		return name
	end
	local prefix = if size.color and not baby then `<font color="#{size.color:ToHex()}">{size.prefix}</font>` else size.prefix
	return `{prefix} {name}`
end

-- Raises a billboard with the model so it stays over a scaled sheep's back.
local function setHudOffset(hud: BillboardGui, scaleRatio: number)
	hud.StudsOffset = hudStudsOffset * scaleRatio
	hud.StudsOffsetWorldSpace = hudWorldOffset * scaleRatio
end

--[[
	Scales a model sitting at its BaseScale up by `scale`. ScaleTo grows it around its pivot, so the feet sink;
	returns how far to raise the pivot to keep them where they were.
]]
local function scaleModel(sheep: Model, scale: number): number
	local baseScale = sheep:GetAttribute(BASE_SCALE)
	if type(baseScale) ~= "number" or scale == 1 then
		return 0
	end

	local boxCFrame, boxSize = sheep:GetBoundingBox()
	local footDepth = sheep:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	sheep:ScaleTo(baseScale * scale)
	return math.max(footDepth, 0) * (scale - 1)
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
	nameLabel.TextScaled = true
	nameLabel.RichText = true
	nameLabel.Parent = hud -- coloured by SheepStyle on spawn
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

	local sheepType = sheep:GetAttribute("SheepType")
	local info = if type(sheepType) == "string" then SheepData.Sheep[sheepType] else nil
	nameLabel.Text = if info
		then formatName(info.name, SheepSizeData.get(sheep:GetAttribute(SIZE_TIER)), info.baby)
		else tostring(sheep:GetAttribute("SheepName") or "Sheep")
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.Visible = ratio > 0
	fill.BackgroundColor3 = HEALTH_EMPTY_COLOR:Lerp(HEALTH_FULL_COLOR, ratio)
	healthText.Text = `{math.ceil(health)} / {maxHealth}`
end

--// Pooling -------------------------------------------------------------------------------

local function resetSheepForPool(sheep: Instance)
	local baseScale = sheep:GetAttribute(BASE_SCALE)
	if sheep:IsA("Model") and type(baseScale) == "number" and sheep:GetScale() ~= baseScale then
		sheep:ScaleTo(baseScale)
	end

	local wool = getWoolPart(sheep)
	if wool then
		local baseSize, baseColor, baseTransparency = getWoolBase(wool)
		wool.Size = baseSize
		wool.Color = baseColor
		wool.Transparency = baseTransparency
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
			hud.Adornee = nil :: any -- the type definitions don't allow nil, but the engine does
			ObjectPool.release(HUD_POOL, HUD_KEY, hud)
		end
		root.Anchored = true
	end
end

-- Takes the sheep out of the registry so nothing shears or walks it any more. Returns it and its owner's id.
local function unregisterSheep(id: number): (Model?, number?)
	local sheep = sheepById[id]
	if not sheep then
		return nil, nil
	end

	sheepById[id] = nil

	local woolConnection = woolConnections[id]
	if woolConnection then
		woolConnection:Disconnect()
		woolConnections[id] = nil
	end

	return sheep, SheepHandler.getOwnerId(sheep)
end

local function poolSheep(sheep: Model)
	local sheepType = sheep:GetAttribute("SheepType")
	if type(sheepType) == "string" then
		ObjectPool.release(SHEEP_POOL, sheepType, sheep, resetSheepForPool)
	else
		sheep:Destroy()
	end
end

-- Removes the sheep from the registry and returns its Model to the pool. Returns its owner's id.
local function releaseSheep(id: number): number?
	local sheep, ownerId = unregisterSheep(id)
	if sheep then
		poolSheep(sheep)
	end
	return ownerId
end

-- Shows the sheep bare and pink with no billboards, holds it still for a moment, then it vanishes.
local function playVanish(sheep: Model, onDone: () -> ())
	updateWoolVisual(sheep)
	SheepHandler.setHudVisible(sheep, false)

	local root = sheep:FindFirstChild("HumanoidRootPart")
	local healthHud = root and root:FindFirstChild(HEALTH_HUD_NAME)
	if healthHud and healthHud:IsA("BillboardGui") then
		healthHud.Enabled = false
	end
	if not root or not root:IsA("BasePart") then
		onDone()
		return
	end

	root.Anchored = true
	collectionService:RemoveTag(sheep, SHEEP_TAG) -- client effects (grazing etc.) let go of it

	task.delay(WoolData.VanishDelay, onDone)
end

-- Removes a sheep that broke out; its owner's sheep count drops by one.
function SheepHandler.removeSheep(id: number)
	local ownerId = releaseSheep(id)
	if ownerId then
		setCount(ownerId, (countByOwner[ownerId] or 1) - 1)
	end
end

-- Removes a sheep sheared bare: it stands naked for a moment before going back to the pool. The count drops right away.
function SheepHandler.vanishSheep(id: number)
	local sheep, ownerId = unregisterSheep(id)
	if not sheep then
		return
	end
	if ownerId then
		setCount(ownerId, (countByOwner[ownerId] or 1) - 1)
	end

	playVanish(sheep, function()
		poolSheep(sheep)
	end)
end

-- Takes a sheep off the farm without pooling it (the Shepherd's Crook picked it up). The count drops right away.
function SheepHandler.takeSheep(id: number): Model?
	local sheep, ownerId = unregisterSheep(id)
	if not sheep then
		return nil
	end
	if ownerId then
		setCount(ownerId, (countByOwner[ownerId] or 1) - 1)
	end

	collectionService:RemoveTag(sheep, SHEEP_TAG) -- nothing shears, outlines or grazes it while it is away
	sheep:SetAttribute("Grazing", nil)
	return sheep
end

-- Sends a sheep that was taken (or never came back) to the pool.
function SheepHandler.discardSheep(sheep: Model)
	poolSheep(sheep)
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
	sheepModel:SetAttribute(BASE_SCALE, sheepModel:GetScale())
	local wool = getWoolPart(sheepModel)
	if wool then
		getWoolBase(wool) -- before any size tier scales it
	end
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

	local babyModels = sheepModels:FindFirstChild("BabySheeps")
	local template = sheepModels:FindFirstChild(sheepType) or (babyModels and babyModels:FindFirstChild(sheepType))
	if not template or not template:IsA("Model") then
		warn(`SheepHandler: '{sheepType}' is not a model in Assets.Models.Sheeps or Sheeps.BabySheeps.`)
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
local function attachHud(root: BasePart, info: SheepData.SheepInfo, oddsText: string, size: SheepSizeData.SizeInfo, weight: number, scaleRatio: number)
	local hud = (ObjectPool.acquire(HUD_POOL, HUD_KEY) or sheepHudTemplate:Clone()) :: BillboardGui

	local card = hud:FindFirstChild("Card")
	local nameLabel = card and card:FindFirstChild("NameLabel") :: TextLabel?
	local rarityPill = card and card:FindFirstChild("RarityPill")
	local rarityLabel = rarityPill and rarityPill:FindFirstChild("RarityLabel") :: TextLabel?
	local oddsLabel = card and card:FindFirstChild("OddsLabel") :: TextLabel?

	if nameLabel then
		nameLabel.RichText = true
		nameLabel.Text = formatName(info.name, size, info.baby)
		SheepStyle.apply(nameLabel, SheepStyle.getMood(info.rarity, info.baby))
	end
	if rarityLabel then
		rarityLabel.Text = info.rarity
	end
	if rarityPill and rarityPill:IsA("Frame") then
		rarityPill.BackgroundColor3 = info.color
	end
	if oddsLabel then
		oddsLabel.Text = `{oddsText} · {weight} kg`
	end

	setHudOffset(hud, scaleRatio)
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

-- Puts a taken sheep back on the player's farm with its feet at `position`, keeping its type, size and wool. Returns its new id.
function SheepHandler.returnSheep(player: Player, sheep: Model, position: Vector3): number?
	local sheepFolder = getSheepFolder(player)
	local root = sheep:FindFirstChild("HumanoidRootPart")
	if not sheepFolder or not root or not root:IsA("BasePart") then
		poolSheep(sheep)
		return nil
	end

	nextSheepId += 1
	local id = nextSheepId
	sheepById[id] = sheep
	sheep:SetAttribute("id", id)
	sheep:SetAttribute(OWNER_ATTRIBUTE, player.UserId)

	local boxCFrame, boxSize = sheep:GetBoundingBox()
	local footDepth = sheep:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	local _, yaw = sheep:GetPivot():ToOrientation()
	sheep:PivotTo(CFrame.new(position + Vector3.new(0, footDepth, 0)) * CFrame.Angles(0, yaw, 0))
	root.Anchored = false
	collectionService:AddTag(sheep, SHEEP_TAG)
	sheep.Parent = sheepFolder
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	updateHealthHud(sheep)
	woolConnections[id] = sheep:GetAttributeChangedSignal("ShearHealth"):Connect(function()
		updateWoolVisual(sheep)
		updateHealthHud(sheep)
	end)

	setCount(player.UserId, (countByOwner[player.UserId] or 0) + 1)
	return id
end

--[[
	Rolls a sheep type with the player's Luck, rebirths and Prestiges and drops it at `position` on their plot.
	Returns the sheep and its id, or nil if it couldn't be spawned.
]]
function SheepHandler.spawnSheep(player: Player, position: Vector3, luck: number, rebirths: number, prestiges: number, luckBoost: number?): (Model?, number?)
	local sheepFolder = getSheepFolder(player)
	if not sheepFolder then
		return nil, nil
	end

	local sheepType = SheepData.roll(luck, rebirths, prestiges, random, luckBoost)
	local info = sheepType and SheepData.Sheep[sheepType]
	if not sheepType or not info then
		return nil, nil
	end

	local sheepModel = acquireModel(sheepType)
	if not sheepModel then
		return nil, nil
	end

	local root = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart
	local oddsText = SheepData.getOddsText(sheepType, luck, rebirths, prestiges, luckBoost)

	local size = SheepSizeData.roll(random)
	local weight, weightWool = SheepSizeData.rollWeight(size, info.baby == true, random)
	local lift = scaleModel(sheepModel, size.scale)
	local scaleRatio = getScaleRatio(sheepModel)
	local maxHealth = math.floor(info.ShearHealth * size.health + 0.5)
	local healthHud = root:FindFirstChild(HEALTH_HUD_NAME)
	if healthHud and healthHud:IsA("BillboardGui") then
		setHudOffset(healthHud, scaleRatio)
		SheepStyle.apply(healthHud:FindFirstChild("NameLabel") :: TextLabel, SheepStyle.getMood(info.rarity, info.baby))
	end

	nextSheepId += 1
	local id = nextSheepId
	sheepById[id] = sheepModel

	sheepModel:SetAttribute("id", id)
	sheepModel:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	sheepModel:SetAttribute("ShearHealth", maxHealth)
	sheepModel:SetAttribute("MaxShearHealth", maxHealth)
	sheepModel:SetAttribute("WoolAmount", math.max(math.floor(info.WoolAmount * size.wool * weightWool + 0.5), 1))
	sheepModel:SetAttribute("LuckAmount", info.LuckAmount)
	sheepModel:SetAttribute("SheepType", sheepType)
	sheepModel:SetAttribute("SheepName", if size.prefix then `{size.prefix} {info.name}` else info.name)
	sheepModel:SetAttribute("Rarity", info.rarity)
	sheepModel:SetAttribute("RarityColor", info.color)
	sheepModel:SetAttribute("Odds", oddsText)
	sheepModel:SetAttribute(SIZE_TIER, size.id)
	sheepModel:SetAttribute(SIZE_COLOR, size.color)
	sheepModel:SetAttribute(WEIGHT, weight)
	sheepModel:SetAttribute(SPAWNED_AT, workspace:GetServerTimeNow())
	sheepModel:SetAttribute("Charged", nil) -- SheepSpawnHandler charges it after; pooled models must not keep an old charge

	sheepModel:PivotTo(CFrame.new(position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))
	root.Anchored = false
	collectionService:AddTag(sheepModel, SHEEP_TAG)
	sheepModel.Parent = sheepFolder

	-- The server walks the sheep, so it keeps physics ownership (no handing it to a nearby player).
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	attachHud(root, info, oddsText, size, weight, scaleRatio)

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

--// Saving -------------------------------------------------------------------------------

-- What a sheep kept off the farm (e.g. on a podium) saves as.
export type SavedSheep = {
	type: string,
	size: string,
	weight: number,
	wool: number,
	health: number,
	maxHealth: number,
	odds: string,
	charged: boolean?,
}

function SheepHandler.saveSheep(sheep: Model): SavedSheep?
	local sheepType = sheep:GetAttribute("SheepType")
	local size = sheep:GetAttribute(SIZE_TIER)
	local weight = sheep:GetAttribute(WEIGHT)
	local wool = sheep:GetAttribute("WoolAmount")
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	local odds = sheep:GetAttribute("Odds")
	if type(sheepType) ~= "string" or type(size) ~= "string" or type(weight) ~= "number" or type(wool) ~= "number"
		or type(health) ~= "number" or type(maxHealth) ~= "number"
	then
		return nil
	end

	return {
		type = sheepType,
		size = size,
		weight = weight,
		wool = wool,
		health = health,
		maxHealth = maxHealth,
		odds = if type(odds) == "string" then odds else "",
		charged = if sheep:GetAttribute("Charged") == true then true else nil,
	}
end

--[[
	Rebuilds a saved sheep as it was, off the farm like a taken one (not counted, sheared or walked; SheepCarryHandler places it).
	Returns nil when its type or size no longer exists.
]]
function SheepHandler.loadSheep(player: Player, saved: any): Model?
	if type(saved) ~= "table" then
		return nil
	end
	local info = SheepData.Sheep[saved.type]
	local size = SheepSizeData.get(saved.size)
	local sheepModel = if info and size then acquireModel(saved.type) else nil
	if not info or not size or not sheepModel or type(saved.maxHealth) ~= "number" then
		return nil
	end

	local root = sheepModel:FindFirstChild("HumanoidRootPart") :: BasePart
	scaleModel(sheepModel, size.scale)
	local scaleRatio = getScaleRatio(sheepModel)
	local healthHud = root:FindFirstChild(HEALTH_HUD_NAME)
	if healthHud and healthHud:IsA("BillboardGui") then
		setHudOffset(healthHud, scaleRatio)
		SheepStyle.apply(healthHud:FindFirstChild("NameLabel") :: TextLabel, SheepStyle.getMood(info.rarity, info.baby))
	end

	local odds = if type(saved.odds) == "string" then saved.odds else ""
	local weight = if type(saved.weight) == "number" then saved.weight else size.minWeight
	sheepModel:SetAttribute(OWNER_ATTRIBUTE, player.UserId)
	sheepModel:SetAttribute("ShearHealth", math.clamp(tonumber(saved.health) or saved.maxHealth, 1, saved.maxHealth))
	sheepModel:SetAttribute("MaxShearHealth", saved.maxHealth)
	sheepModel:SetAttribute("WoolAmount", if type(saved.wool) == "number" then saved.wool else info.WoolAmount)
	sheepModel:SetAttribute("LuckAmount", info.LuckAmount)
	sheepModel:SetAttribute("SheepType", saved.type)
	sheepModel:SetAttribute("SheepName", if size.prefix then `{size.prefix} {info.name}` else info.name)
	sheepModel:SetAttribute("Rarity", info.rarity)
	sheepModel:SetAttribute("RarityColor", info.color)
	sheepModel:SetAttribute("Odds", odds)
	sheepModel:SetAttribute(SIZE_TIER, size.id)
	sheepModel:SetAttribute(SIZE_COLOR, size.color)
	sheepModel:SetAttribute(WEIGHT, weight)
	sheepModel:SetAttribute(SPAWNED_AT, nil) -- not a fresh spawn, so no spawn celebration
	sheepModel:SetAttribute("Charged", if saved.charged == true then true else nil)

	attachHud(root, info, odds, size, weight, scaleRatio)
	updateWoolVisual(sheepModel)
	collectionService:RemoveTag(sheepModel, SHEEP_TAG) -- a pooled model may still carry it
	return sheepModel
end

return SheepHandler
