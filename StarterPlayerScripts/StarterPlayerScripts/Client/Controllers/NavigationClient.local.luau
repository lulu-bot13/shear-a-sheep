--[[
	Main.ToPlot and Main.ToShop ask the server (Navigation) to move the player to their plot or to the SpawnLocation by the plaza.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.NavigationClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared:WaitForChild("Utils"):WaitForChild("Network"))

--// Configs
local MAIN_GUI_NAME = "Main"
local BUTTONS = { ToPlot = "plot", ToShop = "plaza" } -- button name -> Navigation destination
local WAIT_SECONDS = 10

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function bind(mainGui: Instance, name: string, destination: string)
	local button = mainGui:WaitForChild(name, WAIT_SECONDS)
	if not button or not button:IsA("GuiButton") then
		warn(`NavigationClient: Main.{name} button is missing; build it in Studio.`)
		return
	end
	button.Activated:Connect(function()
		network.fireServer(network.RemoteEvents.Teleport, destination)
	end)
end

-- Main resets on spawn, so every new copy is bound again.
local function onGuiAdded(gui: Instance)
	if gui.Name ~= MAIN_GUI_NAME then
		return
	end
	for name, destination in BUTTONS do
		task.spawn(bind, gui, name, destination)
	end
end

network.waitUntilReadyAsync()
playerGui.ChildAdded:Connect(onGuiAdded)
for _, gui in playerGui:GetChildren() do
	onGuiAdded(gui)
end
