--!strict

--[[
Lets each plot's owner buy the next pen through that plot's BuyPenButton prompt

Location: ServerScriptService.Server.PenPurchase
]]--

--// Services
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local PenHandler = require(serverScriptService.Modules.Controllers.PenHandler)
local RebirthHandler = require(serverScriptService.Modules.Controllers.RebirthHandler)
local EconomyData = require(serverScriptService.Modules.Constants.EconomyData)
local PenSlotUnlocks = require(serverScriptService.Modules.Constants.PenSlotUnlocks)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Variables
local lastPurchase: { [Player]: number } = {}

--// Configs
local MAX_PENS = EconomyData.MAX_PENS
local DEBOUNCE_SECONDS = 1
local OWNER_ATTRIBUTE = "Owner"
local NO_OWNER = 0
local REBIRTHS_ATTRIBUTE = "Rebirths"
local EFFECT_HEIGHT = 4

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute(OWNER_ATTRIBUTE)
	return if typeof(owner) == "number" then owner else NO_OWNER
end

local function getOwnedPenCount(ownerId: number): number
	local owner = players:GetPlayerByUserId(ownerId)
	return if owner then #PenHandler.getPens(owner) else 0
end

local function getPenLimit(owner: Player): number
	return math.min(MAX_PENS, PenSlotUnlocks.getSlotLimit(RebirthHandler.getRebirths(owner)))
end

-- Price for pen N = BASE_PRICE * PRICE_MULTIPLIER^(N - 2).
local function getPrice(penNumber: number): number
	return EconomyData.getPenPrice(penNumber)
end

-- The prompt and price label live on the inner BuyPenButton part, so search the whole model.
local function getButtonParts(plot: Instance): (ProximityPrompt?, TextLabel?)
	local button = plot:FindFirstChild("BuyPenButton")
	if not button then
		return nil, nil
	end

	local prompt = button:FindFirstChildWhichIsA("ProximityPrompt", true)
	local label = button:FindFirstChild("Label", true)
	return prompt, if label and label:IsA("TextLabel") then label else nil
end

-- Each button shows the price of its own owner's next pen.
local function refreshButtons()
	for _, plot in plotsFolder:GetChildren() do
		local prompt, label = getButtonParts(plot)
		if not prompt or not label then
			continue
		end

		local owner = players:GetPlayerByUserId(getOwnerId(plot))
		if not owner then
			label.Text = "No owner"
			prompt.Enabled = false
			continue
		end

		local ownedCount = #PenHandler.getPens(owner)
		local limit = getPenLimit(owner)
		if ownedCount >= limit then
			local reachedMax = limit >= math.min(MAX_PENS, PenSlotUnlocks.getMaxSlots())
			label.Text = if reachedMax then "MAX" else "Rebirth to unlock"
			prompt.Enabled = false
		else
			label.Text = `Buy Pen: {getPrice(ownedCount + 1)}`
			prompt.Enabled = true
		end
	end
end

-- Bursts sparkles at a position and cleans itself up.
local function playPurchaseEffect(position: Vector3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(15, 30)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -20, 0)
	emitter.Drag = 3
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 221, 87), Color3.fromRGB(120, 255, 160))
	emitter.Parent = anchor

	anchor.Parent = workspace
	emitter:Emit(60)
	debris:AddItem(anchor, 2)
end

local function onTriggered(plot: Folder, player: Player)
	-- Only the plot's owner can upgrade it, whichever button was pressed.
	if getOwnerId(plot) ~= player.UserId then
		return
	end

	local now = os.clock()
	if lastPurchase[player] and now - lastPurchase[player] < DEBOUNCE_SECONDS then
		return
	end
	lastPurchase[player] = now

	local ownedCount = getOwnedPenCount(player.UserId)
	if ownedCount >= getPenLimit(player) then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	if not money or not money:IsA("IntValue") then
		return
	end

	local price = getPrice(ownedCount + 1)
	if money.Value < price then
		print(`{player.Name} can't afford pen {ownedCount + 1} ({money.Value}/{price}).`)
		return
	end

	local newPen = PenHandler.createPen(player)
	if not newPen then
		return
	end

	money.Value -= price
	print(`{player.Name} bought {newPen.penModel.Name} for {price}.`)

	local prompt = getButtonParts(plot)
	if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
		playPurchaseEffect(prompt.Parent.Position + Vector3.new(0, EFFECT_HEIGHT / 2, 0))
	end

	playPurchaseEffect(newPen.penModel:GetPivot().Position + Vector3.new(0, EFFECT_HEIGHT, 0))
end

local function connectPlot(plot: Folder)
	plot:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(refreshButtons)

	local prompt = getButtonParts(plot)
	if not prompt then
		warn(`PenPurchase: {plot.Name} has no BuyPenButton prompt.`)
		return
	end

	prompt.Triggered:Connect(function(player: Player)
		onTriggered(plot, player)
	end)
end

for _, plot in plotsFolder:GetChildren() do
	if plot:IsA("Folder") then
		connectPlot(plot)
	end
end

players.PlayerRemoving:Connect(function(player)
	lastPurchase[player] = nil
end)

local function watchRebirths(player: Player)
	player:GetAttributeChangedSignal(REBIRTHS_ATTRIBUTE):Connect(refreshButtons)
end

PenHandler.PenAdded:Connect(refreshButtons)
PenHandler.PenRemoved:Connect(refreshButtons)
players.PlayerAdded:Connect(watchRebirths)
for _, player in players:GetPlayers() do
	watchRebirths(player)
end

refreshButtons()
