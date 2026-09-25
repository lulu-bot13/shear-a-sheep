--// Services
local proximityPromptService = game:GetService("ProximityPromptService")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local SheepHandler = require(script.Parent.SheepHandler)
local InventoryHandler = require(script.Parent.InventoryHandler)
local PenHandler = require(script.Parent.PenHandler)
local ShearData = require(game.ServerScriptService.Modules.Constants.ShearData)

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
            local sheepId = currentSheepId.Value
            local woolAmount = sheep:GetAttribute("WoolAmount") :: number
            local newTotal = InventoryHandler.addItem(player, "Wool", woolAmount)
            print(`Added {woolAmount} wool to {player.Name}'s inventory. New total: {newTotal}`)

            SheepHandler.removeSheep(sheepId)
            currentSheepId.Value = 0

            network.fireClient(network.RemoteEvents.DeactivateShearing, player)

            -- Free up the pen this sheep belonged to so the next one can
            -- walk in.
            PenHandler.onSheepRemoved(sheepId)
        end
    end)
end

--[[
    Snaps the player's HumanoidRootPart to the pen's PlayerPos, facing the
    sheep, so every pen frames the same way no matter where the player was
    standing when they triggered the prompt. Position is set here, on the
    server, rather than trusting the client to place itself. The look-at
    target keeps the player's own Y so a raised SheepPos doesn't tilt the
    player's body up toward it -- they just turn to face it horizontally.
]]
local function snapPlayerToPen(player: Player, pen: {playerPosition: Vector3, sheepPosition: Vector3})
	local character = player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoidRootPart then
		return
	end

	local lookTarget = Vector3.new(pen.sheepPosition.X, pen.playerPosition.Y, pen.sheepPosition.Z)
	humanoidRootPart.CFrame = CFrame.lookAt(pen.playerPosition, lookTarget)
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

	local pen = PenHandler.getPenForSheep(sheepId)
	if pen then
		snapPlayerToPen(player, pen)
	end

	network.fireClient(
		network.RemoteEvents.ActivateShearing,
		player,
		sheepId,
		pen and pen.sheepPosition,
		pen and pen.playerPosition
	)
end)


return shearHandler
