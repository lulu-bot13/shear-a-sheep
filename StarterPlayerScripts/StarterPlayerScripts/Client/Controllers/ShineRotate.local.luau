--!strict

--[[
	Spins every "RotatingShine"-tagged ImageLabel in the player's gui from one RenderStepped connection, skipping any that aren't on screen.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShineRotate
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local TAG = "RotatingShine"
local SPEED_ATTRIBUTE = "ShineSpeed" -- optional number attribute on the shine, overrides SPEED; negative spins it the other way
local SPEED = 30 -- degrees per second

--// State
type Shine = {
	startRotation: number,
	addedAt: number,
	destroying: RBXScriptConnection,
}

local shines: { [ImageLabel]: Shine } = {}

--// Helpers -------------------------------------------------------------------------

-- Visible all the way up, inside an Enabled ScreenGui in PlayerGui (not StarterGui).
local function isShown(image: GuiObject): boolean
	local current: Instance? = image
	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return current == playerGui
end

local function getSpeed(image: ImageLabel): number
	local override = image:GetAttribute(SPEED_ATTRIBUTE)
	return if type(override) == "number" then override else SPEED
end

--// Shines ---------------------------------------------------------------------------

local function onShineRemoved(instance: Instance)
	if not instance:IsA("ImageLabel") then
		return
	end
	local shine = shines[instance]
	if not shine then
		return
	end
	shines[instance] = nil
	shine.destroying:Disconnect()
end

local function onShineAdded(instance: Instance)
	if not instance:IsA("ImageLabel") or shines[instance] or not instance:IsDescendantOf(playerGui) then
		return
	end
	local image = instance
	shines[image] = {
		startRotation = image.Rotation,
		addedAt = os.clock(),
		destroying = image.Destroying:Connect(function()
			onShineRemoved(image)
		end),
	}
end

--// Setup -------------------------------------------------------------------------------

collectionService:GetInstanceAddedSignal(TAG):Connect(onShineAdded)
collectionService:GetInstanceRemovedSignal(TAG):Connect(onShineRemoved)

for _, instance in collectionService:GetTagged(TAG) do
	onShineAdded(instance)
end

-- Rotation comes from the clock, so the spin speed doesn't depend on frame rate; hidden shines are skipped.
runService.RenderStepped:Connect(function()
	local now = os.clock()
	for image, shine in shines do
		if isShown(image) then
			image.Rotation = (shine.startRotation + (now - shine.addedAt) * getSpeed(image)) % 360
		end
	end
end)
