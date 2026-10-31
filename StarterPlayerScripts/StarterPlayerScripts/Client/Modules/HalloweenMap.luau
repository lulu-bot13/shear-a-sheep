--!strict

--[[
	Halloween recolour of the map: "BaseFloor" tagged parts, workspace.Base.GrassWalls "Grass" and every "TreeLeaves" go orange,
	and blend back to their own colours when it ends. Parts that stream in later are picked up too.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.HalloweenMap
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

--// Configs
local FLOOR_TAG = "BaseFloor"
local BASE_NAME = "Base"
local GRASS_WALLS_NAME = "GrassWalls"
local GRASS_NAME = "Grass"
local LEAVES_NAME = "TreeLeaves"
local WAIT_TIMEOUT = 10 -- seconds to wait for workspace.Base.GrassWalls
local FLOOR_COLOR = Color3.fromRGB(255, 117, 24) -- BaseFloor and Grass
local TEXTURE_COLOR = Color3.fromRGB(170, 70, 10) -- Textures and Decals on them
local LEAVES_COLOR = Color3.fromRGB(230, 100, 20)
local BLEND_TWEEN = TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut) -- matches WeatherEffects' blend

type Entry = {
	property: "Color" | "Color3", -- Color on BaseParts, Color3 on Textures and Decals
	original: Color3,
	halloween: Color3,
	usePartColor: boolean?, -- Unions only: their own UsePartColor, which Halloween turns on so the orange shows
}

--// State
-- Strong tables: Instances as weak keys get collected while the part still exists, which emptied these before Night.
local entries: { [Instance]: Entry } = {}
local tweens: { [Instance]: Tween } = {}
local active = false
local started = false

local HalloweenMap = {}

--// Helpers ---------------------------------------------------------------------

local function isSurface(instance: Instance): boolean
	return instance:IsA("Texture") or instance:IsA("Decal")
end

local function paint(instance: Instance, entry: Entry, instant: boolean)
	local existing = tweens[instance]
	if existing then
		existing:Cancel()
		tweens[instance] = nil
	end

	local color = if active then entry.halloween else entry.original
	if entry.usePartColor ~= nil then
		(instance :: UnionOperation).UsePartColor = active or entry.usePartColor
	end
	if instant then
		(instance :: any)[entry.property] = color
		return
	end
	local tween = tweenService:Create(instance, BLEND_TWEEN, { [entry.property] = color })
	tweens[instance] = tween
	tween.Completed:Once(function()
		if tweens[instance] == tween then
			tweens[instance] = nil
		end
	end)
	tween:Play()
end

-- Remembers the instance's own colour the first time it's seen; one appearing mid-Halloween snaps straight to orange.
local function track(instance: Instance, halloween: Color3)
	if entries[instance] then
		return
	end
	local property: "Color" | "Color3" = if instance:IsA("BasePart") then "Color" else "Color3"
	local entry: Entry = { property = property, original = (instance :: any)[property], halloween = halloween }
	if instance:IsA("UnionOperation") then
		entry.usePartColor = instance.UsePartColor
	end
	entries[instance] = entry
	instance.Destroying:Once(function()
		entries[instance] = nil
		tweens[instance] = nil
	end)
	if active then
		paint(instance, entry, true)
	end
end

--// Map pieces ------------------------------------------------------------------

-- A tagged floor is a part or a model of them; either way its parts go orange and their Textures/Decals darker.
local function trackFloorPiece(instance: Instance)
	local parent = instance.Parent
	if instance:IsA("BasePart") then
		track(instance, FLOOR_COLOR)
	elseif isSurface(instance) and parent and parent:IsA("BasePart") then
		track(instance, TEXTURE_COLOR)
	end
end

local function trackFloor(root: Instance)
	trackFloorPiece(root)
	for _, descendant in root:GetDescendants() do
		trackFloorPiece(descendant)
	end
	root.DescendantAdded:Connect(trackFloorPiece)
end

-- A "Grass" part, or any part inside a "Grass" model, plus the Textures/Decals on them.
local function isGrass(instance: Instance): boolean
	return instance:IsA("BasePart") and (instance.Name == GRASS_NAME or instance:FindFirstAncestor(GRASS_NAME) ~= nil)
end

local function trackGrassPiece(instance: Instance)
	local parent = instance.Parent
	if isGrass(instance) then
		track(instance, FLOOR_COLOR)
	elseif isSurface(instance) and parent and isGrass(parent) then
		track(instance, TEXTURE_COLOR)
	end
end

local function trackGrassWalls()
	local base = workspace:WaitForChild(BASE_NAME, WAIT_TIMEOUT)
	local walls = if base then base:WaitForChild(GRASS_WALLS_NAME, WAIT_TIMEOUT) else nil
	if not walls then
		warn(`HalloweenMap: workspace.{BASE_NAME}.{GRASS_WALLS_NAME} not found, so the grass walls keep their colour`)
		return
	end
	for _, descendant in walls:GetDescendants() do
		trackGrassPiece(descendant)
	end
	walls.DescendantAdded:Connect(trackGrassPiece)
end

local function trackLeaves(instance: Instance)
	if instance.Name == LEAVES_NAME and instance:IsA("BasePart") then
		track(instance, LEAVES_COLOR) -- MeshParts with a TextureID barely show it, but it's set anyway
	end
end

--// API -------------------------------------------------------------------------

-- Finds the map pieces and keeps watching for ones that stream in; call once before setActive.
function HalloweenMap.start()
	if started then
		return
	end
	started = true

	for _, tagged in collectionService:GetTagged(FLOOR_TAG) do
		trackFloor(tagged)
	end
	collectionService:GetInstanceAddedSignal(FLOOR_TAG):Connect(trackFloor)

	for _, descendant in workspace:GetDescendants() do
		trackLeaves(descendant)
	end
	workspace.DescendantAdded:Connect(trackLeaves)

	task.spawn(trackGrassWalls)
end

-- Turns the orange map on or off; `instant` skips the blend (joining mid-Halloween).
function HalloweenMap.setActive(on: boolean, instant: boolean?)
	if on == active then
		return
	end
	active = on
	for instance, entry in entries do
		if instance.Parent then
			paint(instance, entry, instant == true)
		end
	end
end

return HalloweenMap
