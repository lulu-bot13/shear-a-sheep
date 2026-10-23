--!strict

--[[
	Cycles the wool of every "Rainbow"-tagged sheep Torso through the rainbow, only for sheep near the camera.
	The colour is set locally (no network) and still fades towards bare skin as the sheep is sheared.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RainbowWoolClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)

--// Configs
local TAG = "Rainbow"
local MAX_DISTANCE = 150 -- studs from the camera; further sheep hold their colour
local CYCLE_SECONDS = 4 -- one full trip round the rainbow
local SATURATION = 0.75
local BRIGHTNESS = 1
local UPDATE_INTERVAL = 1 / 30 -- colour refreshes are capped at 30 per second
local RANGE_CHECK_INTERVAL = 0.25 -- how often the list of nearby sheep is rebuilt

--// Types
type Entry = {
	phase: number, -- hue offset so a flock doesn't flash in sync
	shornBlend: number, -- how far towards bare skin the wool is (matches the server's fade)
	connection: RBXScriptConnection?,
}

--// State
local entries: { [BasePart]: Entry } = {}
local nearby: { BasePart } = {}
local random = Random.new()
local updateTimer = 0
local rangeTimer = RANGE_CHECK_INTERVAL -- check range on the first frame

local maxDistanceSquared = MAX_DISTANCE * MAX_DISTANCE
local shornColor = WoolData.ShornColor

local function getShornBlend(sheep: Instance): number
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
		return 0
	end
	return (1 - math.clamp(health / maxHealth, 0, 1)) * WoolData.ShornColorBlend
end

local function onPartAdded(instance: Instance)
	if not instance:IsA("BasePart") or entries[instance] then
		return
	end

	local sheep = instance.Parent
	local entry: Entry = { phase = random:NextNumber(), shornBlend = 0 }
	if sheep then
		entry.shornBlend = getShornBlend(sheep)
		entry.connection = sheep:GetAttributeChangedSignal("ShearHealth"):Connect(function()
			entry.shornBlend = getShornBlend(sheep)
			updateTimer = UPDATE_INTERVAL -- the server just rewrote the colour; paint over it this frame
		end)
	end
	entries[instance] = entry
end

-- Fires when the sheep is sheared bare (its model goes back to the server's pool) or streams out.
local function onPartRemoved(instance: Instance)
	local entry = entries[instance :: BasePart]
	if not entry then
		return
	end
	if entry.connection then
		entry.connection:Disconnect()
	end
	entries[instance :: BasePart] = nil

	local index = table.find(nearby, instance :: BasePart)
	if index then
		nearby[index] = nearby[#nearby]
		nearby[#nearby] = nil
	end
end

local function rebuildNearby()
	table.clear(nearby)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraPosition = camera.CFrame.Position
	for part in entries do
		local offset = part.Position - cameraPosition
		if offset:Dot(offset) <= maxDistanceSquared then
			table.insert(nearby, part)
		end
	end
end

for _, part in collectionService:GetTagged(TAG) do
	onPartAdded(part)
end
collectionService:GetInstanceAddedSignal(TAG):Connect(onPartAdded)
collectionService:GetInstanceRemovedSignal(TAG):Connect(onPartRemoved)

-- PreRender runs after replication, so the server's own wool colour writes never reach the screen.
runService.PreRender:Connect(function(deltaTime: number)
	rangeTimer += deltaTime
	if rangeTimer >= RANGE_CHECK_INTERVAL then
		rangeTimer = 0
		rebuildNearby()
	end

	updateTimer += deltaTime
	if updateTimer < UPDATE_INTERVAL or #nearby == 0 then
		return
	end
	updateTimer = 0

	local hue = (os.clock() / CYCLE_SECONDS) % 1
	for _, part in nearby do
		local entry = entries[part]
		local color = Color3.fromHSV((hue + entry.phase) % 1, SATURATION, BRIGHTNESS)
		part.Color = if entry.shornBlend > 0 then color:Lerp(shornColor, entry.shornBlend) else color
	end
end)
