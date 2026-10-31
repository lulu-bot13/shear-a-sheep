--!strict

--[[
	The Shepherd's Crook: picks a sheep up out of the pen to carry overhead, places it on a "Podium" tagged prompt (or swaps it
	with the sheep already there) and releases a carried sheep back into the pen. Podium sheep are saved and stood back up on join.
	Location: ServerScriptService.Modules.Controllers.SheepCarryHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local FarmData = require(script.Parent.Parent.Constants.FarmData)
local Analytics = require(script.Parent.Analytics)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local CROOK_NAME = "ShepherdsCrook"
local PODIUM_TAG = "Podium" -- on each podium's ProximityPrompt
local OCCUPIED_ATTRIBUTE = "Occupied"
local CARRY_ATTRIBUTE = "CarryingSheep" -- "Pen" or "Podium" (where the carried sheep came from), nil when empty-handed
local PLACE_TEXT = "Place"
local REPLACE_TEXT = "Replace"
local PICK_UP_RANGE = 30 -- studs from the player a clicked sheep may be
local CARRY_HEIGHT = 2.5 -- studs above the character's root the sheep's feet sit
local RELEASE_DISTANCE = 4 -- studs in front of the player a released sheep lands
local GROUND_BELOW_ROOT = 3 -- studs from a character's root down to its feet
local REQUEST_COOLDOWN = 0.25

type Carried = {
	sheep: Model,
	weld: WeldConstraint,
}

--// State
local carried: { [Player]: Carried } = {}
local displayed: { [ProximityPrompt]: Model } = {}
local savingPodiums = false -- true while this handler writes PodiumSheep, so its own Changed is ignored

local SheepCarryHandler = {}

--// Helpers ---------------------------------------------------------------------------

local function getRoot(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isHoldingCrook(player: Player): boolean
	local tool = player.Character and player.Character:FindFirstChild(CROOK_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

-- The plot (a child of Plots) the instance sits in.
local function getPlotOf(instance: Instance): Instance?
	local current: Instance? = instance
	while current and current.Parent ~= plotsFolder do
		current = current.Parent
	end
	return current
end

-- The lowest and highest world Y the part reaches, whichever way it is turned.
local function getWorldYRange(part: BasePart): (number, number)
	local cframe, half = part.CFrame, part.Size / 2
	local extent = math.abs(cframe.RightVector.Y) * half.X + math.abs(cframe.UpVector.Y) * half.Y + math.abs(cframe.LookVector.Y) * half.Z
	return cframe.Position.Y - extent, cframe.Position.Y + extent
end

-- The lowest point of the sheep's visible parts (the invisible root can hang below its feet).
local function getBottomY(sheep: Model): number
	local bottom = math.huge
	for _, descendant in sheep:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			bottom = math.min(bottom, (getWorldYRange(descendant)))
		end
	end
	return if bottom < math.huge then bottom else sheep:GetPivot().Position.Y
end

-- The highest point of the podium's top, a part or every part of a model.
local function getTopY(top: Instance): number
	if top:IsA("BasePart") then
		local _, high = getWorldYRange(top)
		return high
	end
	local highest = -math.huge
	for _, descendant in top:GetDescendants() do
		if descendant:IsA("BasePart") then
			local _, high = getWorldYRange(descendant)
			highest = math.max(highest, high)
		end
	end
	return highest
end

-- Stands the sheep upright at `position` (turned by `yaw`), then lifts it so its feet rest exactly at that height.
local function standAt(sheep: Model, position: Vector3, yaw: number)
	sheep:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
	sheep:PivotTo(sheep:GetPivot() + Vector3.new(0, position.Y - getBottomY(sheep), 0))
end

-- A carried or displayed sheep is weightless and stands limp; a sheep back in the pen walks and collides with its root again.
local function setCarryPhysics(sheep: Model, carrying: boolean)
	local root = getRoot(sheep)
	for _, descendant in sheep:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Massless = carrying
			if descendant == root then
				descendant.CanCollide = not carrying
			end
		end
	end

	local humanoid = sheep:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = carrying
		humanoid.WalkSpeed = 0
	end

	-- A sheep picked up mid-walk keeps its stride otherwise, which throws off where its feet are.
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if carrying and animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
		for _, descendant in sheep:GetDescendants() do
			if descendant:IsA("Motor6D") then
				descendant.Transform = CFrame.identity
			end
		end
	end
end

local function hideHealthHud(sheep: Model)
	local root = getRoot(sheep)
	local healthHud = root and root:FindFirstChild("HealthHUD")
	if healthHud and healthHud:IsA("BillboardGui") then
		healthHud.Enabled = false
	end
end

--// Carrying ------------------------------------------------------------------------------

-- Welds the sheep over the player's head.
local function carry(player: Player, sheep: Model, source: string)
	local playerRoot = getRoot(player.Character)
	local root = getRoot(sheep)
	if not playerRoot or not root then
		SheepHandler.discardSheep(sheep)
		return
	end

	PodiumBonusHandler.hideStats(sheep)
	setCarryPhysics(sheep, true)
	root.Anchored = false
	local _, yaw = playerRoot.CFrame:ToOrientation()
	standAt(sheep, playerRoot.Position + Vector3.new(0, CARRY_HEIGHT, 0), yaw)
	sheep.Parent = PlotHandler.getPlayerPlot(player) or workspace

	local weld = Instance.new("WeldConstraint")
	weld.Name = "CrookWeld"
	weld.Part0 = playerRoot
	weld.Part1 = root
	weld.Parent = root

	carried[player] = { sheep = sheep, weld = weld }
	player:SetAttribute(CARRY_ATTRIBUTE, source)
end

-- Lets go of the carried sheep and returns it, or nil when the player wasn't carrying one.
local function letGo(player: Player): Model?
	local entry = carried[player]
	if not entry then
		return nil
	end

	carried[player] = nil
	entry.weld:Destroy()
	if player.Parent then
		player:SetAttribute(CARRY_ATTRIBUTE, nil)
	end
	return entry.sheep
end

-- Puts the sheep back in the player's pen with its feet at `position`.
local function returnToPen(player: Player, sheep: Model, position: Vector3)
	setCarryPhysics(sheep, false)
	SheepHandler.returnSheep(player, sheep, position)
end

local function discard(sheep: Model)
	PodiumBonusHandler.hideStats(sheep)
	setCarryPhysics(sheep, false)
	SheepHandler.discardSheep(sheep)
end

-- A dead or respawning player's sheep drops back into a random spot in their pen.
local function dropCarried(player: Player)
	local sheep = letGo(player)
	if not sheep then
		return
	end

	local plot = PlotHandler.getPlayerPlot(player)
	local position = plot and SheepWanderHandler.getSpawnPosition(plot)
	if position then
		returnToPen(player, sheep, position)
	else
		discard(sheep)
	end
end

-- True while the player stands inside their plot's SheepArea.
local function isInPen(player: Player, position: Vector3): boolean
	local plot = PlotHandler.getPlayerPlot(player)
	local area = plot and plot:FindFirstChild(FarmData.SheepAreaName)
	local boxCFrame, size
	if area and area:IsA("BasePart") then
		boxCFrame, size = area.CFrame, area.Size
	elseif area and area:IsA("Model") then
		boxCFrame, size = area:GetBoundingBox()
	else
		return false
	end

	local localPos = boxCFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= size.X / 2 and math.abs(localPos.Z) <= size.Z / 2
end

--// Podiums -------------------------------------------------------------------------------

local function setOccupied(prompt: ProximityPrompt, occupied: boolean)
	prompt:SetAttribute(OCCUPIED_ATTRIBUTE, occupied)
	prompt.ActionText = if occupied then REPLACE_TEXT else PLACE_TEXT
end

-- Stands the sheep on top of the podium part holding the prompt, facing away from the way the part does, with its name card showing.
local function display(prompt: ProximityPrompt, sheep: Model)
	local top = prompt.Parent
	local root = getRoot(sheep)
	if not root or not top or not (top:IsA("BasePart") or top:IsA("Model")) then
		discard(sheep)
		return
	end

	local topCFrame = if top:IsA("BasePart") then top.CFrame else top:GetPivot()
	local _, yaw = topCFrame:ToOrientation()

	setCarryPhysics(sheep, true)
	root.Anchored = true
	standAt(sheep, Vector3.new(topCFrame.Position.X, getTopY(top), topCFrame.Position.Z), yaw + math.pi)
	sheep.Parent = top.Parent or top
	hideHealthHud(sheep)
	SheepHandler.setHudVisible(sheep, true)
	PodiumBonusHandler.showStats(sheep, SheepHandler.saveSheep(sheep))

	displayed[prompt] = sheep
	setOccupied(prompt, true)
end

-- Saved under the podium's name (e.g. "Podium1"), the same on every plot since they are all built from TemplatePlot.
local function getPodiumKey(prompt: ProximityPrompt): string?
	local top = prompt.Parent
	local podium = top and top.Parent
	return if podium then podium.Name else nil
end

local function savePodium(player: Player, prompt: ProximityPrompt, sheep: Model)
	local key = getPodiumKey(prompt)
	if not key then
		return
	end

	local saved = PlayerDataHandler.get(player, "PodiumSheep")
	local podiums = if type(saved) == "table" then table.clone(saved) else {}
	podiums[key] = SheepHandler.saveSheep(sheep)
	savingPodiums = true
	PlayerDataHandler.set(player, "PodiumSheep", podiums)
	savingPodiums = false
end

-- Places the carried sheep on the podium; a sheep already standing there is handed to the player in its place.
local function onPodiumTriggered(prompt: ProximityPrompt, player: Player)
	local plot = getPlotOf(prompt)
	if not plot or plot:GetAttribute("Owner") ~= player.UserId or not carried[player] then
		return
	end

	local sheep = letGo(player) :: Model
	local previous = displayed[prompt]
	displayed[prompt] = nil
	display(prompt, sheep)
	savePodium(player, prompt, sheep)
	Analytics.podiumPlaced(player, sheep:GetAttribute("SheepType"))

	if previous and previous.Parent then
		carry(player, previous, "Podium")
	end
end

-- Sends every sheep standing on the plot's podiums back to the pool and opens the podiums up again.
local function clearPodiums(plot: Instance)
	for prompt, sheep in displayed do
		if prompt:IsDescendantOf(plot) then
			displayed[prompt] = nil
			discard(sheep)
			setOccupied(prompt, false)
		end
	end
end

-- Stands the player's saved sheep back on their plot's podiums (and clears any that are no longer saved).
local function restorePodiums(player: Player)
	local plot = PlotHandler.getPlayerPlot(player)
	if not plot then
		return
	end
	clearPodiums(plot)

	local saved = PlayerDataHandler.get(player, "PodiumSheep")
	if type(saved) ~= "table" then
		return
	end
	for _, prompt in collectionService:GetTagged(PODIUM_TAG) do
		local key = prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(plot) and getPodiumKey(prompt)
		local sheep = if key and saved[key] then SheepHandler.loadSheep(player, saved[key]) else nil
		if sheep then
			display(prompt :: ProximityPrompt, sheep)
		end
	end
end

local function bindPodium(instance: Instance)
	if not instance:IsA("ProximityPrompt") or not instance:IsDescendantOf(plotsFolder) then
		return
	end
	local prompt = instance :: ProximityPrompt
	setOccupied(prompt, false)
	prompt.Triggered:Connect(function(player: Player)
		onPodiumTriggered(prompt, player)
	end)
end

--// Remote handlers -----------------------------------------------------------------------

local function onPickUp(player: Player, sheep: any)
	if typeof(sheep) ~= "Instance" or not sheep:IsA("Model") or carried[player] or not isHoldingCrook(player) then
		return
	end

	local id = sheep:GetAttribute("id")
	local health = sheep:GetAttribute("ShearHealth")
	local playerRoot = getRoot(player.Character)
	local root = getRoot(sheep)
	if type(id) ~= "number" or SheepHandler.getSheep(id) ~= sheep or SheepHandler.getOwnerId(sheep) ~= player.UserId
		or type(health) ~= "number" or health <= 0 or sheep:GetAttribute("Rising") or not playerRoot or not root
		or sheep:GetAttribute("Boss") or sheep:GetAttribute("Minion") -- Reapers can't be saved to a podium
		or (root.Position - playerRoot.Position).Magnitude > PICK_UP_RANGE
	then
		return
	end

	local taken = SheepHandler.takeSheep(id)
	if taken then
		carry(player, taken, "Pen")
	end
end

local function onRelease(player: Player)
	local playerRoot = getRoot(player.Character)
	if not carried[player] or not playerRoot or not isInPen(player, playerRoot.Position) then
		return
	end

	local flatLook = Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z)
	local forward = if flatLook.Magnitude > 0.01 then flatLook.Unit * RELEASE_DISTANCE else Vector3.zero
	local position = playerRoot.Position + forward - Vector3.new(0, GROUND_BELOW_ROOT, 0)
	returnToPen(player, letGo(player) :: Model, position)
end

--// Lifecycle ----------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			dropCarried(player)
		end)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	player.CharacterRemoving:Connect(function()
		dropCarried(player)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	task.spawn(function()
		if PlayerDataHandler.waitForData(player) and PlotHandler.waitForPlot(player) then
			restorePodiums(player)
		end
	end)
end

function SheepCarryHandler.Start()
	network.waitUntilReadyAsync()

	network.connectEvent(network.RemoteEvents.CrookPickUp, onPickUp, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})
	network.connectEvent(network.RemoteEvents.CrookRelease, onRelease, {
		network.Middleware.RateLimit(REQUEST_COOLDOWN),
	})

	for _, prompt in collectionService:GetTagged(PODIUM_TAG) do
		bindPodium(prompt)
	end
	collectionService:GetInstanceAddedSignal(PODIUM_TAG):Connect(bindPodium)

	PlotHandler.PlotReleased:Connect(function(_, plot: Instance)
		clearPodiums(plot)
	end)
	players.PlayerRemoving:Connect(function(player: Player)
		local sheep = letGo(player)
		if sheep then
			discard(sheep)
		end
	end)
	-- A data reset (or anything else rewriting the save) puts the podiums back in line with it.
	PlayerDataHandler.Changed:Connect(function(player: Player, key: string)
		if key == "PodiumSheep" and not savingPodiums then
			restorePodiums(player)
		end
	end)
	players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return SheepCarryHandler
