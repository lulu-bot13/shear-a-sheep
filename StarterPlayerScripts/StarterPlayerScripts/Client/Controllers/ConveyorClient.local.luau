--!strict

--[[
	Scrolls the Chevrons texture on every "Conveyor" belt near the camera at the belt's speed; a Paused belt (full pen) stands still.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ConveyorClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

--// Configs
local CONVEYOR_TAG = "Conveyor"
local TEXTURE_NAME = "Chevrons"
local SPEED_ATTRIBUTE = "Speed"
local RIDE_SPEED_ATTRIBUTE = "RideSpeed" -- set by the server when refills need a faster belt
local PAUSED_ATTRIBUTE = "Paused"
local DEFAULT_SPEED = 10
local NEAR_DISTANCE = 200 -- studs from the camera a belt keeps scrolling
local REFRESH_SECONDS = 1 -- how often the nearby set is rebuilt
local SCROLL_DIRECTION = -1 -- OffsetStudsV runs against the part's LookVector on a Top-face texture

--// State
local belts: { [BasePart]: Texture } = {}
local nearby: { [BasePart]: Texture } = {}
local renderConnection: RBXScriptConnection? = nil

local function getSpeed(belt: BasePart): number
	local ride = belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	local base = belt:GetAttribute(SPEED_ATTRIBUTE)
	return if type(ride) == "number" then ride elseif type(base) == "number" then base else DEFAULT_SPEED
end

local function onRender(dt: number)
	for belt, texture in nearby do
		local tile = math.max(texture.StudsPerTileV, 0.01)
		texture.OffsetStudsV = (texture.OffsetStudsV + SCROLL_DIRECTION * getSpeed(belt) * dt) % tile
	end
end

-- The per-frame scroll only runs while a moving belt is near the camera.
local function refreshNearby()
	table.clear(nearby)
	local camera = workspace.CurrentCamera
	if camera then
		local origin = camera.CFrame.Position
		for belt, texture in belts do
			if belt:GetAttribute(PAUSED_ATTRIBUTE) ~= true and (belt.Position - origin).Magnitude <= NEAR_DISTANCE then
				nearby[belt] = texture
			end
		end
	end

	if next(nearby) and not renderConnection then
		renderConnection = runService.RenderStepped:Connect(onRender)
	elseif not next(nearby) and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function addBelt(instance: Instance)
	if not instance:IsA("BasePart") or belts[instance] or not instance:IsDescendantOf(workspace) then
		return
	end
	local texture = instance:FindFirstChild(TEXTURE_NAME)
	if not texture or not texture:IsA("Texture") then
		warn(`ConveyorClient: {instance:GetFullName()} has no {TEXTURE_NAME} Texture; add one in Studio to show it moving.`)
		return
	end
	belts[instance] = texture

	-- A belt that pauses or resumes shouldn't wait for the next refresh.
	instance:GetAttributeChangedSignal(PAUSED_ATTRIBUTE):Connect(refreshNearby)
end

local function removeBelt(instance: Instance)
	if instance:IsA("BasePart") then
		belts[instance] = nil
		refreshNearby()
	end
end

for _, belt in collectionService:GetTagged(CONVEYOR_TAG) do
	addBelt(belt)
end
collectionService:GetInstanceAddedSignal(CONVEYOR_TAG):Connect(addBelt)
collectionService:GetInstanceRemovedSignal(CONVEYOR_TAG):Connect(removeBelt)

-- The camera has no "moved far" event, so the nearby set is rechecked once a second.
while true do
	refreshNearby()
	task.wait(REFRESH_SECONDS)
end
