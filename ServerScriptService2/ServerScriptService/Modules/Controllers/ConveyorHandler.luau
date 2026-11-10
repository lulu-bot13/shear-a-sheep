--!strict

--[[
	Makes every "Conveyor" tagged part in the workspace carry what stands on it along its LookVector at its RideSpeed (or Speed)
	attribute, and stops it while its Paused attribute is true. The parked TemplatePlot in ServerStorage is skipped.

	Location: ServerScriptService.Modules.Controllers.ConveyorHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")

--// Configs
local CONVEYOR_TAG = "Conveyor"
local SPEED_ATTRIBUTE = "Speed"
local RIDE_SPEED_ATTRIBUTE = "RideSpeed" -- set by SheepBeltHandler when refills need a faster belt
local PAUSED_ATTRIBUTE = "Paused"
local DEFAULT_SPEED = 10

--// State
local watched: { [BasePart]: boolean } = {}

local ConveyorHandler = {}

local function getSpeed(belt: BasePart): number
	local ride = belt:GetAttribute(RIDE_SPEED_ATTRIBUTE)
	local base = belt:GetAttribute(SPEED_ATTRIBUTE)
	return if type(ride) == "number" then ride elseif type(base) == "number" then base else DEFAULT_SPEED
end

local function apply(belt: BasePart)
	local paused = belt:GetAttribute(PAUSED_ATTRIBUTE) == true
	belt.AssemblyLinearVelocity = if paused then Vector3.zero else belt.CFrame.LookVector * getSpeed(belt)
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or watched[instance] or not instance:IsDescendantOf(workspace) then
		return
	end
	if not instance.Anchored then
		warn(`ConveyorHandler: {instance:GetFullName()} should be Anchored so it carries sheep and players without moving itself.`)
	end
	watched[instance] = true

	instance.AttributeChanged:Connect(function(name: string)
		if name == PAUSED_ATTRIBUTE or name == SPEED_ATTRIBUTE or name == RIDE_SPEED_ATTRIBUTE then
			apply(instance)
		end
	end)
	instance.Destroying:Once(function()
		watched[instance] = nil
	end)
	apply(instance)
end

function ConveyorHandler.Start()
	collectionService:GetInstanceAddedSignal(CONVEYOR_TAG):Connect(watch)
	for _, belt in collectionService:GetTagged(CONVEYOR_TAG) do
		watch(belt)
	end
end

return ConveyorHandler
