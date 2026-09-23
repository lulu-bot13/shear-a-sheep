--// Services
local proximityPromptService = game:GetService("ProximityPromptService")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SheepHandler = require(script.Parent.SheepHandler)
local ShearData = require(game.ServerScriptService.Modules.Constants.ShearData)

--// Configurations
local proximityPromptConnections = {}

local shearHandler = {}

--[[
    Resolves the sheep a player is currently shearing, or nil if they aren't
    shearing anything (CurrentSheepId defaults to 0, used as the "not
    shearing" sentinel since sheep ids start at 1).
]]
local function getCurrentSheep(player: Player): (Model?, IntValue?)
    local currentSheepId = player:FindFirstChild("CurrentSheepId") :: IntValue?
    if not currentSheepId or currentSheepId.Value == 0 then
        return nil, currentSheepId
    end

    return SheepHandler.getSheep(currentSheepId.Value), currentSheepId
end

function shearHandler.Start()
    -- Guards against firing/connecting remotes before Network.startServer()
    -- has set up the remote folder (see Network.waitUntilReadyAsync).
    network.waitUntilReadyAsync()

    --[[
        Handles a single shear click from the client. The client sends no
        payload -- the server resolves the player's current sheep itself so
        it never has to trust which sheep the client claims to be shearing.
    ]]
    network.connectEvent(network.RemoteEvents.Shear, function(player: Player)
        local sheep, currentSheepId = getCurrentSheep(player)
        if not sheep or not currentSheepId then
            return
        end

        local shearHealth = math.max(sheep:GetAttribute("ShearHealth") - ShearData.Default.damage, 0)
        sheep:SetAttribute("ShearHealth", shearHealth)

        print(`Shearing sheep. Deducted {ShearData.Default.damage} health. Current Health: {shearHealth}`)

        if shearHealth <= 0 then
            SheepHandler.removeSheep(currentSheepId.Value)
            currentSheepId.Value = 0

            network.fireClient(network.RemoteEvents.DeactivateShearing, player)
        end
    end)
end

--[[
        Handles the player equipping the sheep when they catch up to them and
        prevents them from selecting while already shearing another sheep.
    ]]
proximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	local actionText = prompt.ActionText

	if actionText ~= "Shear" then
		return
	end

	local sheepId = prompt:GetAttribute("Id")
	local currentSheepId = player:FindFirstChild("CurrentSheepId") :: IntValue?
	if not currentSheepId then
		return
	end

	if currentSheepId.Value ~= 0 then
		warn(`Player '{player.Name}' is already shearing a sheep.`)
		return
	end

	local sheepModel = SheepHandler.getSheep(sheepId)
	if not sheepModel then
		warn(`No active sheep found for id {sheepId}.`)
		return
	end

	currentSheepId.Value = sheepId

	print(`Player has selected {sheepModel.Name} to shear.`)

	network.fireClient(network.RemoteEvents.ActivateShearing, player, sheepId)
end)


return shearHandler
