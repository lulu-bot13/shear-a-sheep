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

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Variables
local lastPurchase: { [Player]: number } = {}

--// Configs
local BASE_PRICE = 100
local PRICE_MULTIPLIER = 3
local MAX_PENS = 6
local PEN_SPACING = 15.8
local PEN_DIRECTION = Vector3.new(0, 0, -1) -- Base_Fence's RightVector points straight down, so use a horizontal axis.
local DEBOUNCE_SECONDS = 1
local TEMPLATE_NAME = "Plot_1"
local PATH_SEAM_GAP = 0.02 -- Keeps neighbouring path pieces from overlapping and z-fighting.
local SHARED_PART_NAMES = { "StarterPath" } -- Entry parts that exist once and are not copied into new pens.
local OWNER_ATTRIBUTE = "Owner" -- Set by PlotHandler; 0 means nobody owns the plot.
local PURCHASED_ATTRIBUTE = "Purchased" -- Marks pens bought here so PlotHandler never hands them out as a base.
local NO_OWNER = 0
local EFFECT_HEIGHT = 4 -- Studs above the pen's fence where the purchase burst plays.

local connectPlot: (plot: Folder) -> ()

local function isPen(instance: Instance): boolean
	return instance:IsA("Folder") and instance.Name:match("^Plot_%d+$") ~= nil
end

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute(OWNER_ATTRIBUTE)
	return if typeof(owner) == "number" then owner else NO_OWNER
end

local function getOwnedPenCount(ownerId: number): number
	local count = 0
	for _, child in plotsFolder:GetChildren() do
		if isPen(child) and getOwnerId(child) == ownerId then
			count += 1
		end
	end
	return count
end

local function getNextPenNumber(): number
	local number = 1
	while plotsFolder:FindFirstChild(`Plot_{number}`) do
		number += 1
	end
	return number
end

-- Price for pen N = BASE_PRICE * PRICE_MULTIPLIER^(N - 2).
local function getPrice(penNumber: number): number
	return math.round(BASE_PRICE * PRICE_MULTIPLIER ^ (penNumber - 2))
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
		if not isPen(plot) then
			continue
		end

		local prompt, label = getButtonParts(plot)
		if not prompt or not label then
			continue
		end

		local ownerId = getOwnerId(plot)
		if ownerId == NO_OWNER then
			label.Text = "No owner"
			prompt.Enabled = false
			continue
		end

		local ownedCount = getOwnedPenCount(ownerId)
		if ownedCount >= MAX_PENS then
			label.Text = "MAX"
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

-- Resizes and moves a path piece so it sits flush after the previous pen's piece.
local function fitPathPart(part: BasePart, penNumber: number)
	local direction = PEN_DIRECTION.Unit
	local cframe = part.CFrame
	local size = part.Size
	local pieceLength = PEN_SPACING - PATH_SEAM_GAP
	local length: number

	if math.abs(cframe.RightVector:Dot(direction)) >= math.abs(cframe.LookVector:Dot(direction)) then
		length = size.X
		part.Size = Vector3.new(pieceLength, size.Y, size.Z)
	else
		length = size.Z
		part.Size = Vector3.new(size.X, size.Y, pieceLength)
	end

	part.CFrame = cframe + direction * (length / 2 + (penNumber - 1.5) * PEN_SPACING)
end

-- Clones the template plot into the next pen slot, owned by the buyer; returns nil if the template is invalid.
local function createPen(penNumber: number, ownerId: number): Folder?
	local plot = plotsFolder:FindFirstChild(TEMPLATE_NAME) :: Folder?
	if not plot then
		warn(`PenPurchase: {TEMPLATE_NAME} not found.`)
		return nil
	end

	local baseFence = plot:FindFirstChild("Base_Fence") :: Model?
	local waypointsFolder = plot:FindFirstChild("Waypoints") and plot.Waypoints:FindFirstChild("3") :: BasePart?
	if not baseFence or not waypointsFolder then
		warn("PenPurchase: template is missing Base_Fence or Waypoints.3.")
		return nil
	end

	local offset = PEN_DIRECTION.Unit * PEN_SPACING * (penNumber - 1)
	local clone = plot:Clone() :: Folder
	clone.Name = `Plot_{penNumber}`
	clone:SetAttribute(OWNER_ATTRIBUTE, ownerId)
	clone:SetAttribute(PURCHASED_ATTRIBUTE, true)

	for _, name in SHARED_PART_NAMES do
		local shared = clone:FindFirstChild(name)
		if shared then
			shared:Destroy()
		end
	end

	local waypoints = clone:FindFirstChild("Waypoints")
	local paths = clone:FindFirstChild("Paths")
	for _, descendant in clone:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		-- Waypoints 1-3 keep their original spots so every sheep walks the same entry route.
		if waypoints and descendant:IsDescendantOf(waypoints) then
			continue
		end

		if paths and descendant:IsDescendantOf(paths) then
			fitPathPart(descendant, penNumber)
		else
			descendant.CFrame += offset
		end
	end

	-- Extra waypoint stepping over to this pen, matching the last original waypoint.
	if waypoints then
		local last = waypoints:FindFirstChild("3") :: BasePart
		local extra = last:Clone()
		extra.Name = "4"
		extra.CFrame = last.CFrame + offset
		extra.Parent = waypoints
	end

	clone.Parent = plotsFolder
	return clone
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
	if ownedCount >= MAX_PENS then
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

	local newPen = createPen(getNextPenNumber(), player.UserId)
	if not newPen then
		return -- Nothing built, nothing charged.
	end

	money.Value -= price
	print(`{player.Name} bought {newPen.Name} for {price}.`)
	PenHandler.addPen(newPen)
	connectPlot(newPen)
	refreshButtons()

	local prompt = getButtonParts(plot)
	if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
		playPurchaseEffect(prompt.Parent.Position + Vector3.new(0, EFFECT_HEIGHT / 2, 0))
	end

	local fence = newPen:FindFirstChild("Base_Fence")
	if fence and fence:IsA("Model") then
		playPurchaseEffect(fence:GetPivot().Position + Vector3.new(0, EFFECT_HEIGHT, 0))
	end
end

connectPlot = function(plot: Folder)
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
	if isPen(plot) then
		connectPlot(plot :: Folder)
	end
end

players.PlayerRemoving:Connect(function(player)
	lastPurchase[player] = nil
end)

refreshButtons()
