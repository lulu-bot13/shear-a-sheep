--// Services
local collectionService =  game:GetService("CollectionService")

--// Prompt
local sellPrompt = collectionService:GetTagged("SellWool")

--// Variables
local playerDebounces = {}
local debounce = false
local cooldownTime = 3

--// Configs
local BASE_AMOUNT = 0.5

local function calculateCashReward(woolAmount: number)
    
    return woolAmount * BASE_AMOUNT

end

sellPrompt.Triggered:Connect(function(player: Player)
    if playerDebounces[player] == true then return end
    playerDebounces[player] = true
    task.delay(cooldownTime, function()
        playerDebounces[player] = false
    end)

    local inventory = player:WaitForChild("Inventory")
    if not inventory then
        warn(`No inventory found for player: {player.Name}`)
        return
    end
    local woolAmount = inventory:FindFirstChild("WoolAmount")
    if not woolAmount or woolAmount <= 0 then return end

    local cashToGrant = calculateCashReward()
    player.leaderstats.Money.Value += cashToGrant

end)
