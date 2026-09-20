--// Services
local proximityPromptService = game:GetService("ProximityPromptService")

--[[
    This function handles the player equipping 
    the sheep when they catch up to them and
    prevents them from selecting while already shearing another sheep.
]]
proximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
    
    local actionText = prompt.ActionText

    if actionText ~= "Shear" then return end

    local sheepName = prompt:GetAttribute("SheepName")
    local sheepId = prompt:GetAttribute("Id")

    local currentSheep = player:FindFirstChild("CurrentSheep")
    
    if currentSheep.Value ~= nil then
        warn(`Player '{player.Name}' is already shearing a sheep.`)
        return
    else
        currentSheep.Value = sheepId

        print(`Player has selected {sheepName} to shear.`)

        -- Send a remote event to the client saying player is shearing
        --[[
            TODO: 
                Make quick shearing data so that each shear is its own item with specific data
        ]]
    end
end)
