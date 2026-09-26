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
Resolves the sheep a player is currently shearing

@param player The player to look up
@return sheep The sheep model, or nil if not shearing
@return currentSheepId The player's CurrentSheepId value
]]--
local function getCurrentSheep(player: Player): (Model?, IntValue?)
    local currentSheepId = player:FindFirstChild("CurrentSheepId") :: IntValue?
    if not currentSheepId or currentSheepId.Value == 0 then
        return nil, currentSheepId
    end

    return SheepHandler.getSheep(currentSheepId.Value), currentSheepId
end

--[[
Connects the shear remote so each click damages the player's current sheep
]]--
function shearHandler.Start()
    network.waitUntilReadyAsync()

	-- Shear function
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
            
            -- Reposition player
            local character = player.Character or player.CharacterAdded:Wait()
            local humanoidRootPart: BasePart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                humanoidRootPart.CFrame = humanoidRootPart.CFrame * CFrame.new(-5, 0, 0)
				print(`Repositioned`)
            end

            PenHandler.onSheepRemoved(sheepId)
        end
    end)
end

--[[
Moves the player to the pen's PlayerPos, facing the sheep

@param player The player to move
@param pen The pen holding the player and sheep positions
]]--
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
	Starts shearing when a player triggers a sheep's "Shear" prompt

	@param prompt The triggered prompt
	@param player The player who triggered it
]]--
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

	-- Make the proximity not visible
	prompt.Enabled = false

	network.fireClient(
		network.RemoteEvents.ActivateShearing,
		player,
		sheepId,
		pen and pen.sheepPosition,
		pen and pen.playerPosition
	)
end)


return shearHandler
