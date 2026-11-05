--!strict

--[[
	Spins every "RotatingShine"-tagged shine in the player's RobuxShop, only while the shop window is open.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShineRotator
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
local SHOP_GUI_NAME = "RobuxShop"
local SPEED = 25 -- degrees per second

--// State
local shopGui: ScreenGui? = nil
local mainFrame: GuiObject? = nil
local shines: { [GuiObject]: boolean } = {}

--// Shines ---------------------------------------------------------------------------

local function onShineAdded(instance: Instance)
	if shopGui and instance:IsA("GuiObject") and instance:IsDescendantOf(shopGui) then
		shines[instance] = true
	end
end

local function onShineRemoved(instance: Instance)
	if instance:IsA("GuiObject") then
		shines[instance] = nil
	end
end

-- Points everything at this copy of the shop; a fresh copy (e.g. after a respawn reset) replaces the old one.
local function attach(gui: Instance)
	if gui.Name ~= SHOP_GUI_NAME or not gui:IsA("ScreenGui") or gui == shopGui then
		return
	end
	shopGui = gui :: ScreenGui
	mainFrame = nil
	table.clear(shines)
	for _, instance in collectionService:GetTagged(TAG) do
		onShineAdded(instance)
	end

	local main = gui:WaitForChild("Main")
	if shopGui == gui and main:IsA("GuiObject") then
		mainFrame = main
	end
end

collectionService:GetInstanceAddedSignal(TAG):Connect(onShineAdded)
collectionService:GetInstanceRemovedSignal(TAG):Connect(onShineRemoved)

playerGui.ChildAdded:Connect(attach)
task.spawn(attach, playerGui:WaitForChild(SHOP_GUI_NAME))

--// Setup -------------------------------------------------------------------------------

-- Rotation comes from the clock, so the spin speed doesn't depend on frame rate.
runService.PreRender:Connect(function()
	local gui, main = shopGui, mainFrame
	if not gui or not main or not gui.Enabled or not main.Visible then
		return
	end

	local rotation = (os.clock() * SPEED) % 360
	for shine in shines do
		shine.Rotation = rotation
	end
end)
