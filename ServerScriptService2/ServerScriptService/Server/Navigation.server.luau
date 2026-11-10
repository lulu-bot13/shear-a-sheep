--[[
	Handles the Main HUD's travel buttons: "plot" sends the player to their plot's SpawnArea, "plaza" to the shear shop's ShearSpawn.
	Location: ServerScriptService.Server.Navigation
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared:WaitForChild("Utils"):WaitForChild("Network"))
local PlotHandler = require(serverScriptService:WaitForChild("Modules"):WaitForChild("Controllers"):WaitForChild("PlotHandler"))

--// Configs
local TELEPORT_COOLDOWN = 1 -- seconds between requests per player

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.Teleport, function(player: Player, destination: unknown)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local target = if destination == "plot" then PlotHandler.getRespawnCFrame(player)
		elseif destination == "plaza" then PlotHandler.getShopCFrame()
		else nil
	if target then
		character:PivotTo(target)
	end
end, { network.Middleware.RateLimit(TELEPORT_COOLDOWN) })
