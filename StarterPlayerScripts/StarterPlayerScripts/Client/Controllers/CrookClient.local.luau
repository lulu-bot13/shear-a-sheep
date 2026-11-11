--[[
	The Shepherd's Crook: a "HOLD" tag over the hovered sheep, click to pick it up or let it go, a hint and a beam to an open podium.
	The rest of the UI hides while it's out; with it put away, each of the player's podiums says to equip it.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.CrookClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
local beamTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("TutorialBeam") :: Beam

--// Configs
local CROOK_NAME = "ShepherdsCrook"
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local PODIUM_TAG = "Podium"
local OCCUPIED_ATTRIBUTE = "Occupied"
local CARRY_ATTRIBUTE = "CarryingSheep" -- "Pen" or "Podium", set by SheepCarryHandler
local SHEEP_AREA_NAME = "SheepArea"
local HINT_Y_SCALE = 0.8
local HINT_SIZE = UDim2.fromScale(0.4, 0.05)
local HOLD_COLOR = Color3.fromRGB(255, 230, 90)
local HOVER_RAY_LENGTH = 300
local BEAM_ATTACHMENT_ROTATION = Vector3.new(0, 0, 90) -- degrees, matches TutorialClient
local WOOL_COLOR = Color3.fromRGB(255, 236, 179) -- PodiumData's Wool colour
local TEXT_WOOL = "x%s Wool"

-- "%s" is "Click", or "Tap" on touch screens.
local TEXT_PICK_UP = "%s a sheep to pick it up"
local TEXT_PLACE = "Place it on a podium stand"
local TEXT_REPLACE = "Swap it with a sheep on a podium stand"
local TEXT_OR_RELEASE = ", or %s to let it go" -- added to the podium text while standing in the pen
local TEXT_GO_TO_PEN = "Take it back to your pen to shear it"
local TEXT_RELEASE = "%s to let it go in your pen"

--// Podium sign: shown on each of the player's podiums while the crook is put away
local SIGN_TITLE = "Equip your Shepherd's Crook"
local SIGN_SUBTITLE = "to place a sheep here"
local SIGN_SIZE = UDim2.fromScale(9, 2.2) -- studs
local SIGN_OFFSET = Vector3.new(0, -3, 0) -- from the podium's top part down onto its base, clear of a sheep standing on top
local SIGN_MAX_DISTANCE = 45

-- Stay up while the rest of the UI is hidden: short-lived popups, the tutorial, and TouchGui (the touch thumbstick).
local KEEP_GUIS = {
	TouchGui = true,
	Tutorial = true,
	Alerts = true,
	AlertsGui = true,
	GemPopup = true,
	BestFindAnnouncement = true,
}

--// State
local hovered: Model? = nil
local boundCrooks: { [Instance]: boolean } = {}
local uiHidden = false
local hiddenGuis: { ScreenGui } = {} -- turned off by this script, so only these are turned back on
local podiumSigns: { [ProximityPrompt]: BillboardGui } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

--// Hint label -------------------------------------------------------------------------

local hintGui = Instance.new("ScreenGui")
hintGui.Name = "CrookHint"
hintGui.ResetOnSpawn = false
hintGui.Parent = playerGui

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.fromScale(0.5, HINT_Y_SCALE)
hintLabel.Size = HINT_SIZE
hintLabel.BackgroundTransparency = 1
hintLabel.Font = Enum.Font.GothamBlack
hintLabel.TextScaled = true
hintLabel.TextColor3 = Color3.new(1, 1, 1)
hintLabel.Visible = false
hintLabel.Parent = hintGui
local hintStroke = Instance.new("UIStroke")
hintStroke.Thickness = 2
hintStroke.Parent = hintLabel

--// Hiding the UI ----------------------------------------------------------------------

local function hideGui(gui: Instance)
	if uiHidden and gui:IsA("ScreenGui") and gui ~= hintGui and not KEEP_GUIS[gui.Name] and gui.Enabled then
		gui.Enabled = false
		table.insert(hiddenGuis, gui)
	end
end

-- Guis added while hidden (a respawned Main) are hidden too; ones opened on purpose later, like a shop, are left alone.
local function setUiHidden(hidden: boolean)
	if hidden == uiHidden then
		return
	end
	uiHidden = hidden
	if hidden then
		for _, gui in playerGui:GetChildren() do
			hideGui(gui)
		end
	else
		for _, gui in hiddenGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	end
end

playerGui.ChildAdded:Connect(hideGui)

--// HOLD tag ---------------------------------------------------------------------------

-- "HOLD" stays where it always was (1 stud above the root); the wool multiplier sits just under it.
local holdTag = Instance.new("BillboardGui")
holdTag.Name = "CrookHold"
holdTag.Size = UDim2.fromScale(3, 2)
holdTag.StudsOffset = Vector3.new(0, 0.6, 0)
holdTag.AlwaysOnTop = true
holdTag.LightInfluence = 0
local holdLabel = Instance.new("TextLabel")
holdLabel.BackgroundTransparency = 1
holdLabel.Size = UDim2.fromScale(1, 0.6)
holdLabel.Font = Enum.Font.GothamBlack
holdLabel.TextScaled = true
holdLabel.TextColor3 = HOLD_COLOR
holdLabel.Text = "HOLD"
holdLabel.Parent = holdTag
local holdStroke = Instance.new("UIStroke")
holdStroke.Thickness = 2
holdStroke.Parent = holdLabel

local woolLabel = Instance.new("TextLabel")
woolLabel.Name = "Wool"
woolLabel.BackgroundTransparency = 1
woolLabel.Position = UDim2.fromScale(0, 0.6)
woolLabel.Size = UDim2.fromScale(1, 0.4)
woolLabel.Font = Enum.Font.GothamBlack
woolLabel.TextScaled = true
woolLabel.TextColor3 = WOOL_COLOR
woolLabel.Parent = holdTag
local woolStroke = Instance.new("UIStroke")
woolStroke.Thickness = 2
woolStroke.Parent = woolLabel

local hoverHighlight = Instance.new("Highlight")
hoverHighlight.Name = "CrookHover"
hoverHighlight.FillColor = HOLD_COLOR
hoverHighlight.OutlineColor = HOLD_COLOR
hoverHighlight.FillTransparency = 0.8
hoverHighlight.DepthMode = Enum.HighlightDepthMode.Occluded

--// Beam -------------------------------------------------------------------------------

local beamStart = Instance.new("Attachment")
beamStart.Name = "CrookBeamStart"
beamStart.Orientation = BEAM_ATTACHMENT_ROTATION
beamStart.Parent = workspace.Terrain
local beamEnd = Instance.new("Attachment")
beamEnd.Name = "CrookBeamEnd"
beamEnd.Orientation = BEAM_ATTACHMENT_ROTATION
beamEnd.Parent = workspace.Terrain

local beam = beamTemplate:Clone()
beam.Attachment0 = beamStart
beam.Attachment1 = beamEnd
beam.FaceCamera = false
beam.Enabled = false
beam.Parent = workspace.Terrain

--// Helpers ----------------------------------------------------------------------------

local function getRoot(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- How much more wool it gives than a plain adult of its type (variant, size, weight, mutation and Charge are all in WoolAmount).
local function getWoolMultiplier(sheep: Model): number
	local wool = sheep:GetAttribute("WoolAmount")
	local baseWool = sheep:GetAttribute("BaseWool")
	if type(wool) ~= "number" or type(baseWool) ~= "number" or baseWool <= 0 then
		return 1
	end
	return wool / baseWool
end

-- 2.5 -> "2.5", 3 -> "3"
local function formatMultiplier(value: number): string
	return (string.format("%.1f", value):gsub("%.0$", ""))
end

local function isHoldingCrook(): boolean
	local tool = player.Character and player.Character:FindFirstChild(CROOK_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

local function getCarrySource(): string?
	local source = player:GetAttribute(CARRY_ATTRIBUTE)
	return if type(source) == "string" then source else nil
end

local function getPlot(): Instance?
	local plotName = player:GetAttribute("PlotName")
	return if type(plotName) == "string" then plotsFolder:FindFirstChild(plotName) else nil
end

-- The pen's box (a part, or a model's bounding box).
local function getPenBox(): (CFrame?, Vector3?)
	local plot = getPlot()
	local area = plot and plot:FindFirstChild(SHEEP_AREA_NAME)
	if area and area:IsA("BasePart") then
		return area.CFrame, area.Size
	elseif area and area:IsA("Model") then
		return area:GetBoundingBox()
	end
	return nil, nil
end

local function isInPen(position: Vector3): boolean
	local boxCFrame, size = getPenBox()
	if not boxCFrame or not size then
		return false
	end
	local localPos = boxCFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= size.X / 2 and math.abs(localPos.Z) <= size.Z / 2
end

-- The podium prompts on the player's own plot.
local function getOwnPodiums(): { ProximityPrompt }
	local plot = getPlot()
	local found: { ProximityPrompt } = {}
	if not plot then
		return found
	end
	for _, prompt in collectionService:GetTagged(PODIUM_TAG) do
		if prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(plot) then
			table.insert(found, prompt)
		end
	end
	return found
end

local function getPromptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- The nearest open podium, or the nearest podium at all when every one is taken (the second result is then true).
local function getTargetPodium(from: Vector3): (Vector3?, boolean)
	local bestOpen, bestOpenDistance = nil, math.huge
	local bestAny, bestAnyDistance = nil, math.huge
	for _, prompt in getOwnPodiums() do
		local position = getPromptPosition(prompt)
		if position then
			local distance = (position - from).Magnitude
			if prompt:GetAttribute(OCCUPIED_ATTRIBUTE) ~= true and distance < bestOpenDistance then
				bestOpen, bestOpenDistance = position, distance
			end
			if distance < bestAnyDistance then
				bestAny, bestAnyDistance = position, distance
			end
		end
	end
	if bestOpen then
		return bestOpen, false
	end
	return bestAny, bestAny ~= nil
end

-- The player's own sheep under the mouse (or the last tap), if any.
local function getSheepUnderMouse(): Model?
	local camera = workspace.CurrentCamera
	if not camera or not player.Character then
		return nil
	end

	rayParams.FilterDescendantsInstances = { player.Character }
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * HOVER_RAY_LENGTH, rayParams)
	local model = result and result.Instance:FindFirstAncestorOfClass("Model")
	while model do
		if collectionService:HasTag(model, SHEEP_TAG) then
			return if model:GetAttribute(OWNER_ATTRIBUTE) == player.UserId then model else nil
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

--// Podium signs -----------------------------------------------------------------------

local function createSignLabel(name: string, text: string, position: UDim2, size: UDim2, color: Color3, parent: Instance)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = label
end

local function createSign(prompt: ProximityPrompt): BillboardGui?
	local top = prompt.Parent
	if not top or not top:IsA("BasePart") then
		return nil
	end
	local sign = Instance.new("BillboardGui")
	sign.Name = "CrookPodiumSign"
	sign.Adornee = top
	sign.Size = SIGN_SIZE
	sign.StudsOffsetWorldSpace = SIGN_OFFSET
	sign.MaxDistance = SIGN_MAX_DISTANCE
	sign.AlwaysOnTop = true -- drawn over the base it sits on
	sign.LightInfluence = 0
	createSignLabel("Title", SIGN_TITLE, UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.6), HOLD_COLOR, sign)
	createSignLabel("Subtitle", SIGN_SUBTITLE, UDim2.fromScale(0, 0.6), UDim2.fromScale(1, 0.4), Color3.new(1, 1, 1), sign)
	sign.Parent = top
	return sign
end

-- Shows the sign on every podium of the player's plot (and removes the ones on podiums that aren't theirs any more).
local function setPodiumSigns(shown: boolean)
	local own: { [ProximityPrompt]: boolean } = {}
	for _, prompt in getOwnPodiums() do
		own[prompt] = true
		local sign = podiumSigns[prompt] or createSign(prompt)
		podiumSigns[prompt] = sign
		if sign then
			sign.Enabled = shown
		end
	end
	for prompt, sign in podiumSigns do
		if not own[prompt] then
			sign:Destroy()
			podiumSigns[prompt] = nil
		end
	end
end

--// Updating ---------------------------------------------------------------------------

local function setHovered(sheep: Model?)
	if sheep == hovered then
		return
	end
	hovered = sheep
	if sheep then
		woolLabel.Text = string.format(TEXT_WOOL, formatMultiplier(getWoolMultiplier(sheep)))
	end

	local root = getRoot(sheep)
	holdTag.Adornee = root
	holdTag.Parent = if root then root else nil
	hoverHighlight.Adornee = sheep
	hoverHighlight.Parent = if sheep then workspace else nil
end

local function getClickWord(): string
	return if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then "Tap" else "Click"
end

-- Hint text and beam target for what the player should do next; nil text hides the hint.
local function getGoal(playerRoot: BasePart): (string?, Vector3?)
	local source = getCarrySource()
	local inPen = isInPen(playerRoot.Position)
	if source == "Podium" then
		if inPen then
			return string.format(TEXT_RELEASE, getClickWord()), nil
		end
		local boxCFrame = getPenBox()
		return TEXT_GO_TO_PEN, if boxCFrame then boxCFrame.Position else nil
	elseif source then
		local podium, allTaken = getTargetPodium(playerRoot.Position)
		local text = if allTaken then TEXT_REPLACE else TEXT_PLACE
		if inPen then
			text ..= string.format(TEXT_OR_RELEASE, getClickWord():lower())
		end
		return text, podium
	elseif isHoldingCrook() then
		return string.format(TEXT_PICK_UP, getClickWord()), nil
	end
	return nil, nil
end

local idleApplied = false -- the idle state (no crook, nothing carried) is already on screen

local function update()
	local carrying = getCarrySource() ~= nil
	local active = carrying or isHoldingCrook()
	if not active and idleApplied then
		return
	end
	idleApplied = not active

	for _, prompt in getOwnPodiums() do
		if prompt.Enabled ~= carrying then
			prompt.Enabled = carrying
		end
	end
	setPodiumSigns(not active)
	setUiHidden(active)

	setHovered(if isHoldingCrook() and not carrying then getSheepUnderMouse() else nil)

	local playerRoot = getRoot(player.Character)
	local text, beamTarget
	if playerRoot then
		text, beamTarget = getGoal(playerRoot)
	end

	hintLabel.Visible = text ~= nil
	if text and hintLabel.Text ~= text then
		hintLabel.Text = text
	end

	if playerRoot and beamTarget then
		beamStart.WorldPosition = playerRoot.Position
		beamEnd.WorldPosition = beamTarget
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

local function onActivated()
	if getCarrySource() then
		local playerRoot = getRoot(player.Character)
		if playerRoot and isInPen(playerRoot.Position) then
			network.fireServer(network.RemoteEvents.CrookRelease)
		end
		return
	end

	-- Looked up again: on touch the tap that activated the tool is also what moved the "mouse".
	local sheep = getSheepUnderMouse() or hovered
	if sheep then
		network.fireServer(network.RemoteEvents.CrookPickUp, sheep)
	end
end

--// Setup ------------------------------------------------------------------------------

-- Prompts on other players' plots never show here, whatever they carry.
local function hideForeignPodium(instance: Instance)
	local plot = getPlot()
	if instance:IsA("ProximityPrompt") and not (plot and instance:IsDescendantOf(plot)) then
		instance.Enabled = false
	end
end

-- Each crook Tool is bound once; equipping it again fires ChildAdded again.
local function bindCrook(child: Instance)
	if not child:IsA("Tool") or child.Name ~= CROOK_NAME or boundCrooks[child] then
		return
	end
	boundCrooks[child] = true
	child.Activated:Connect(onActivated)
	child.Destroying:Once(function()
		boundCrooks[child] = nil
	end)
end

local function onCharacterAdded(character: Model)
	character.ChildAdded:Connect(bindCrook)
	for _, child in character:GetChildren() do
		bindCrook(child)
	end
end

network.waitUntilReadyAsync()

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

for _, prompt in collectionService:GetTagged(PODIUM_TAG) do
	hideForeignPodium(prompt)
end
collectionService:GetInstanceAddedSignal(PODIUM_TAG):Connect(function(instance: Instance)
	idleApplied = false -- a new own podium prompt starts enabled until the next update turns it off
	hideForeignPodium(instance)
end)
player:GetAttributeChangedSignal("PlotName"):Connect(function()
	idleApplied = false
	for _, prompt in collectionService:GetTagged(PODIUM_TAG) do
		hideForeignPodium(prompt)
	end
end)

runService.RenderStepped:Connect(update)
