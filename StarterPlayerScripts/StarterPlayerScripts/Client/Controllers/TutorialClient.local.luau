--[[
	First-play tutorial: go to a sheep, shear it, buy More Wool and +1 Sheep, farm wool, then rebirth.
	Each step is worked out from the player's progress, so it resumes after a rejoin and ends at the first rebirth.
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local guiService = game:GetService("GuiService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local spotlightUI = require(script.Parent.Parent.Modules.SpotlightUI)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local tutorialText = tutorialGui:WaitForChild("Main"):WaitForChild("TutorialFrame"):WaitForChild("TutorialText1") :: TextLabel
local mainGui = playerGui:WaitForChild("Main")
local pointer = mainGui:WaitForChild("Pointer") :: GuiObject
local hudButtons = mainGui:WaitForChild("Buttons")
local upgradesButton = hudButtons:WaitForChild("Upgrades") :: GuiButton
local rebirthHudButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local upgradeCards = playerGui:WaitForChild("UpgradeShop"):WaitForChild("Main"):WaitForChild("ScrollingFrame")
local rebirthButton = playerGui:WaitForChild("RebirthScreen"):WaitForChild("Main"):WaitForChild("Rebirth") :: GuiButton
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue

--// Configs
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local SHEAR_RANGE_ATTRIBUTE = "ShearRange" -- only shear Tools have it
local NEAR_DISTANCE = 8 -- studs (flat) from a sheep that count as "at" it
local ALWAYS_IN_STUDIO = true -- TODO: set to false once the tutorial is tested; runs it in Studio even on a save that has rebirthed
local TICK_SECONDS = 0.1
local DISPLAY_ORDER = 90 -- the text, spotlight and pointer draw over every window (Alerts are 100)
local STATE_REQUEST_SECONDS = 2 -- re-asks the server for upgrade / rebirth state until it arrives

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_WIDTH = 0.6
local BEAM_TEXTURE = "" -- "rbxassetid://..." for an arrow texture; empty draws a plain beam

local POINTER_ROTATION = 180
local POINTER_GAP = 6 -- pixels between the pointer and the top of its target
local POINTER_BOB_PIXELS = 12
local POINTER_BOB_SPEED = 5

-- Bought in this order during the Upgrades step.
local UPGRADE_STEPS = {
	{ id = "MoreWool", text = "Buy More Wool" },
	{ id = "Capacity", text = "Buy +1 Sheep" },
}

type Stage = "GoToSheep" | "Shear" | "Upgrades" | "Rebirth" | "Done"

--// State
local stage: Stage = "GoToSheep"
local shearedAtStageStart = 0
local upgradeStates: { [string]: any }? = nil -- UpgradeState cards by id
local rebirthCost: number? = nil
local nextStateRequest = 0
local beamSheep: Model? = nil
local highlights: { [Model]: Highlight } = {}
local pointerTarget: GuiObject? = nil
local focused: GuiObject? = nil -- what the spotlight was last tweened over, and where it was
local focusedPosition, focusedSize = Vector2.zero, Vector2.zero
local pointerParent = pointer.Parent
local renderConnection: RBXScriptConnection? = nil

local playerAttachment = Instance.new("Attachment")
playerAttachment.Name = "TutorialBeam"
local sheepAttachment = Instance.new("Attachment")
sheepAttachment.Name = "TutorialBeam"

local beam = Instance.new("Beam")
beam.Name = "TutorialBeam"
beam.Attachment0 = playerAttachment
beam.Attachment1 = sheepAttachment
beam.Color = ColorSequence.new(BEAM_COLOR)
beam.Width0 = BEAM_WIDTH
beam.Width1 = BEAM_WIDTH
beam.FaceCamera = true
beam.LightEmission = 1
beam.Texture = BEAM_TEXTURE
beam.TextureSpeed = 1
beam.Enabled = false
beam.Parent = workspace.Terrain

--// Helpers -------------------------------------------------------------------------

local function getNumberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

local function getRoot(model: Model?): BasePart?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function formatWool(value: number): string
	return numberFormatter:Format(math.floor(value), 1)
end

-- The player's sheep currently on their farm.
local function getOwnSheep(): { Model }
	local found: { Model } = {}
	for _, sheep in collectionService:GetTagged(SHEEP_TAG) do
		if sheep:IsA("Model") and sheep:GetAttribute(OWNER_ATTRIBUTE) == player.UserId
			and sheep:IsDescendantOf(workspace) and getRoot(sheep)
		then
			table.insert(found, sheep)
		end
	end
	return found
end

local function getFlatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function isHoldingShear(): boolean
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool ~= nil and tool:GetAttribute(SHEAR_RANGE_ATTRIBUTE) ~= nil
end

-- False while the object, one of its parents or its ScreenGui is hidden.
local function isShown(guiObject: GuiObject): boolean
	local gui = guiObject:FindFirstAncestorOfClass("ScreenGui")
	if not gui or not gui.Enabled then
		return false
	end

	local current: Instance? = guiObject
	while current and current ~= gui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function isWindowOpen(name: string): boolean
	local window = windowsManager.get(name)
	return window ~= nil and window.isOpen()
end

local function setText(text: string)
	tutorialText.Text = text
end

--// Sheep guides ---------------------------------------------------------------------

-- Outlines exactly these sheep.
local function setHighlights(sheepList: { Model })
	local keep: { [Model]: boolean } = {}
	for _, sheep in sheepList do
		keep[sheep] = true
		if not highlights[sheep] then
			local highlight = Instance.new("Highlight")
			highlight.Name = "TutorialHighlight"
			highlight.FillColor = HIGHLIGHT_COLOR
			highlight.OutlineColor = HIGHLIGHT_COLOR
			highlight.FillTransparency = 0.7
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = sheep
			highlight.Parent = workspace
			highlights[sheep] = highlight
		end
	end

	for sheep, highlight in highlights do
		if not keep[sheep] then
			highlight:Destroy()
			highlights[sheep] = nil
		end
	end
end

-- Draws the beam from the character to the sheep; nil hides it.
local function setBeam(sheep: Model?)
	local playerRoot = getRoot(player.Character)
	local sheepRoot = getRoot(sheep)
	if not playerRoot or not sheepRoot then
		beam.Enabled = false
		return
	end

	playerAttachment.Parent = playerRoot
	sheepAttachment.Parent = sheepRoot
	beam.Enabled = true
end

local function clearSheepGuides()
	setHighlights({})
	setBeam(nil)
	beamSheep = nil
end

--// Pointer + spotlight ------------------------------------------------------------------

-- Pixels between the top of the screen and the top of the gui this instance draws in.
local function getInsetOffset(instance: Instance): Vector2
	local gui = if instance:IsA("ScreenGui") then instance else instance:FindFirstAncestorOfClass("ScreenGui")
	if gui and not gui.IgnoreGuiInset then
		local topLeft = guiService:GetGuiInset()
		return topLeft
	end
	return Vector2.zero
end

-- Spotlights the GuiObject and bobs the pointer over it; nil clears both.
-- FocusUI only measures the target once, so it is called again whenever the target moves (e.g. a window popping in).
local function point(target: GuiObject?)
	pointerTarget = target
	if target and isShown(target) then
		if target ~= focused or target.AbsolutePosition ~= focusedPosition or target.AbsoluteSize ~= focusedSize then
			focused, focusedPosition, focusedSize = target, target.AbsolutePosition, target.AbsoluteSize
			spotlightUI:FocusUI(target)
		end
	elseif focused then
		focused = nil
		spotlightUI:Cleanup()
	end
end

local function updatePointer()
	local target = pointerTarget
	if not target or not isShown(target) then
		pointer.Visible = false
		return
	end

	-- Measured in screen pixels, since the target's ScreenGui may not share the Tutorial gui's inset.
	local targetPosition = target.AbsolutePosition + getInsetOffset(target)
	local bob = (math.sin(os.clock() * POINTER_BOB_SPEED) + 1) / 2 * POINTER_BOB_PIXELS
	local center = Vector2.new(
		targetPosition.X + target.AbsoluteSize.X / 2,
		targetPosition.Y - POINTER_GAP - pointer.AbsoluteSize.Y / 2 - bob
	) - getInsetOffset(tutorialGui)

	pointer.Position = UDim2.fromOffset(center.X, center.Y)
	pointer.Visible = true
end

--// Stages ------------------------------------------------------------------------------

local function setStage(newStage: Stage)
	stage = newStage
	shearedAtStageStart = getNumberAttribute("SheepShearedCount")
	clearSheepGuides()
	point(nil)
end

-- Asks the server again for state the tutorial is still missing.
local function requestState(eventName: any)
	local now = os.clock()
	if now >= nextStateRequest then
		nextStateRequest = now + STATE_REQUEST_SECONDS
		network.fireServer(eventName)
	end
end

-- "Go to a Sheep": every sheep is outlined and a beam leads to one of them.
local function updateGoToSheep()
	setText("Go to a Sheep")
	local sheepList = getOwnSheep()
	setHighlights(sheepList)

	if not beamSheep or not table.find(sheepList, beamSheep) then
		beamSheep = if #sheepList > 0 then sheepList[math.random(#sheepList)] else nil
	end
	setBeam(beamSheep)

	local playerRoot = getRoot(player.Character)
	if not playerRoot then
		return
	end
	for _, sheep in sheepList do
		local sheepRoot = getRoot(sheep) :: BasePart
		if getFlatDistance(playerRoot.Position, sheepRoot.Position) <= NEAR_DISTANCE then
			setStage("Shear")
			return
		end
	end
end

-- The sheep being sheared: the one with the least wool left, then the nearest.
local function getShearTarget(): Model?
	local playerRoot = getRoot(player.Character)
	local best: Model?, bestRatio, bestDistance = nil, math.huge, math.huge
	for _, sheep in getOwnSheep() do
		local health = sheep:GetAttribute("ShearHealth")
		local maxHealth = sheep:GetAttribute("MaxShearHealth")
		if type(health) ~= "number" or type(maxHealth) ~= "number" or maxHealth <= 0 then
			continue
		end

		local ratio = health / maxHealth
		local distance = if playerRoot then getFlatDistance(playerRoot.Position, (getRoot(sheep) :: BasePart).Position) else 0
		if ratio < bestRatio or (ratio == bestRatio and distance < bestDistance) then
			best, bestRatio, bestDistance = sheep, ratio, distance
		end
	end
	return best
end

-- "Click to Shear 1/5": swings landed on the sheep / swings it takes to shear it bare.
local function updateShear()
	if getNumberAttribute("SheepShearedCount") > shearedAtStageStart then
		setStage("Upgrades")
		return
	end
	if not isHoldingShear() then
		setText("Equip your Shears")
		return
	end

	local sheep = getShearTarget()
	local damage = getNumberAttribute("ShearDamage")
	if not sheep or damage <= 0 then
		setText("Click to Shear")
		return
	end

	local total = math.ceil((sheep:GetAttribute("MaxShearHealth") :: number) / damage)
	local left = math.ceil((sheep:GetAttribute("ShearHealth") :: number) / damage)
	setText(`Click to Shear {total - left}/{total}`)
end

-- Opens the shop, then buys More Wool and +1 Sheep; asks for wool first if the next one isn't affordable.
local function updateUpgrades()
	local states = upgradeStates
	if not states then
		requestState(network.RemoteEvents.RequestUpgradeState)
		setText("Open Upgrades")
		point(upgradesButton)
		return
	end

	local step, card = nil, nil
	for _, upgradeStep in UPGRADE_STEPS do
		local state = states[upgradeStep.id]
		if state and state.cost and (state.level or 0) == 0 then
			step, card = upgradeStep, state
			break
		end
	end
	if not step or not card then
		setStage("Rebirth")
		return
	end

	if wool.Value < card.cost then
		setText(`Shear sheep for Wool {formatWool(wool.Value)}/{formatWool(card.cost)}`)
		point(nil)
	elseif not isWindowOpen("UpgradeShop") then
		setText("Open Upgrades")
		point(upgradesButton)
	else
		local cardFrame = upgradeCards:FindFirstChild(step.id)
		local purchase = cardFrame and cardFrame:FindFirstChild("Purchase")
		setText(step.text)
		point(if purchase and purchase:IsA("GuiObject") then purchase else nil)
	end
end

-- Farms wool up to the first rebirth's cost, then opens the rebirth screen and presses Rebirth.
local function updateRebirth()
	local cost = rebirthCost
	if not cost then
		requestState(network.RemoteEvents.RequestRebirthState)
		setText("Farm Wool to Rebirth")
		return
	end

	if wool.Value < cost then
		setText(`Farm Wool to Rebirth {formatWool(wool.Value)}/{formatWool(cost)}`)
		point(nil)
	elseif not isWindowOpen("Rebirth") then
		setText("Open Rebirths")
		point(rebirthHudButton)
	else
		setText("Press Rebirth!")
		point(rebirthButton)
	end
end

local UPDATERS: { [Stage]: () -> () } = {
	GoToSheep = updateGoToSheep,
	Shear = updateShear,
	Upgrades = updateUpgrades,
	Rebirth = updateRebirth,
}

--// Lifecycle ---------------------------------------------------------------------------

local function stop()
	stage = "Done"
	clearSheepGuides()
	point(nil)
	beam:Destroy()
	playerAttachment:Destroy()
	sheepAttachment:Destroy()

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	pointer.Visible = false
	pointer.Parent = pointerParent
	tutorialGui.Enabled = false
end

local function start(firstStage: Stage)
	local startRebirths = getNumberAttribute("Rebirths")
	tutorialGui.ResetOnSpawn = false
	tutorialGui.DisplayOrder = DISPLAY_ORDER
	tutorialGui.Enabled = true
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Rotation = POINTER_ROTATION
	pointer.Visible = false
	pointer.Parent = tutorialGui

	setStage(firstStage)
	renderConnection = runService.RenderStepped:Connect(updatePointer)

	while stage ~= "Done" do
		if getNumberAttribute("Rebirths") > startRebirths then
			stop()
			alerts.show("Tutorial complete!", "success")
			return
		end
		UPDATERS[stage]()
		task.wait(TICK_SECONDS)
	end
end

tutorialGui.Enabled = false
pointer.Visible = false

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.UpgradeState, function(states: { any })
	local byId = {}
	for _, state in states do
		byId[state.id] = state
	end
	upgradeStates = byId
end)

network.connectEvent(network.RemoteEvents.RebirthState, function(state: any)
	rebirthCost = state.woolCost
end)

-- The save has loaded once its numbers are mirrored onto the player.
while player:GetAttribute("Rebirths") == nil do
	player:GetAttributeChangedSignal("Rebirths"):Wait()
end

local forced = ALWAYS_IN_STUDIO and runService:IsStudio()
if forced then
	print("[TutorialClient] running from the start (ALWAYS_IN_STUDIO)")
	start("GoToSheep")
elseif getNumberAttribute("Rebirths") >= 1 then
	print(`[TutorialClient] skipped: this save has {getNumberAttribute("Rebirths")} rebirth(s)`)
	stop()
else
	start(if getNumberAttribute("SheepShearedCount") > 0 then "Upgrades" else "GoToSheep")
end
