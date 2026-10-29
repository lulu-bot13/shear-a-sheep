--[[
	First-play tutorial: equip shears, shear 3 sheep (every other UI hidden), buy 3 upgrades (shearing more when short), close the shop, then rebirth.
	Each step is worked out from the player's progress, so it resumes after a rejoin and ends at the first rebirth.
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local spotlightUI = require(script.Parent.Parent.Modules.SpotlightUI)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local tutorialMain = tutorialGui:WaitForChild("Main") :: GuiObject
local tutorialFrame = tutorialMain:WaitForChild("TutorialFrame") :: GuiObject
local tutorialText = tutorialFrame:WaitForChild("TutorialText") :: TextLabel
local spotlightFrame = tutorialGui:WaitForChild("Spotlight") :: GuiObject
local darkOverlay = tutorialGui:WaitForChild("DarkOverlay") :: GuiObject
local completedLabel = tutorialGui:WaitForChild("TutorialCompletedLabel") :: GuiObject
local tip = tutorialGui:WaitForChild("Tip") :: GuiObject
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local upgradesButton = hudButtons:WaitForChild("Upgrades") :: GuiButton
local rebirthHudButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local upgradeShopMain = playerGui:WaitForChild("UpgradeShop"):WaitForChild("Main")
local upgradeCards = upgradeShopMain:WaitForChild("ScrollingFrame")
local upgradeShopExit = upgradeShopMain:FindFirstChild("Exit", true) :: GuiObject? -- found the same way WindowsManager wires it
local rebirthButton = playerGui:WaitForChild("RebirthScreen"):WaitForChild("Main"):WaitForChild("Rebirth") :: GuiButton
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue
local beamTemplate = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX"):WaitForChild("TutorialBeam") :: Beam

--// Configs
local SHEEP_TAG = "Sheep"
local OWNER_ATTRIBUTE = "OwnerId"
local SHEAR_RANGE_ATTRIBUTE = "ShearRange" -- only shear Tools have it
local NEAR_DISTANCE = 8 -- studs (flat) from a sheep that count as "at" it
local LEAVE_DISTANCE = 12 -- studs (flat) the first sheep is walked away from before the beam leads back to a sheep
local ALWAYS_IN_STUDIO = false -- runs the tutorial in Studio even on a save that has rebirthed
local TICK_SECONDS = 0.1
local DISPLAY_ORDER = 90 -- the text and spotlight draw over every window (Alerts are 100)
local STATE_REQUEST_SECONDS = 2 -- re-asks the server for upgrade / rebirth state until it arrives
local COMPLETED_SECONDS = 3 -- how long the completed label stays up
local SHEEP_TO_SHEAR = 3 -- counting the first sheep
-- The upgrades bought in order, each with why it helps; 45 + 40 + 76 wool, so the last one usually needs another sheep first.
local TUTORIAL_UPGRADES = {
	{ id = "MoreWool", text = "Buy More Wool. Every Sheep gives you more Wool!" },
	{ id = "Capacity", text = "Buy Sheep Capacity. More Sheep fit on your farm!" },
	{ id = "MoreWool", text = "Buy More Wool again. Upgrades stack up!" },
}
local KEEP_HUD_BUTTONS = { Upgrades = true, Rebirth = true } -- the only HUD buttons shown until the tutorial ends
local HIDE_UI_STAGES = { EquipShears = true, GoToSheep = true, FirstShear = true, Shear = true } -- every ScreenGui but the tutorial's is off during these
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_ATTACHMENT_ROTATION = Vector3.new(0, 0, 90) -- degrees, applied to both beam ends
local HOTBAR_SLOT_SIZE = 60 -- pixels, Roblox's default hotbar
local HOTBAR_SLOT_GAP = 5
local HOTBAR_BOTTOM_GAP = 5

type Stage = "EquipShears" | "GoToSheep" | "FirstShear" | "Shear" | "Upgrades" | "CloseUpgrades" | "Rebirth" | "Done"

--// State
local stage: Stage = "EquipShears"
local shearedBaseline = 0 -- SheepShearedCount the "Shear 3 Sheep" progress counts up from
local hiddenHudButtons: { GuiObject } = {}
local hiddenGuis: { ScreenGui } = {}
local popFullScales: { [UIScale]: number } = {} -- each popped object's full size, read before its first pop
local upgradeStates: { [string]: any }? = nil -- UpgradeState cards by id
local rebirthCost: number? = nil
local nextStateRequest = 0
local highlights: { [Model]: Highlight } = {}
local beamSheep: Model? = nil -- the sheep the beam leads to
local firstSheep: Model? = nil -- the sheep "Click To Shear" shows the health of
local beamConnection: RBXScriptConnection? = nil
local focused: GuiObject? = nil -- what the spotlight was last tweened over, and where it was
local focusedPosition, focusedSize = Vector2.zero, Vector2.zero

-- One beam cloned once and reused. Its ends stay in Terrain and are moved each frame,
-- so a respawned character or a replaced sheep can't destroy them.
local beamStart = Instance.new("Attachment")
beamStart.Name = "TutorialBeamStart"
beamStart.Orientation = BEAM_ATTACHMENT_ROTATION
beamStart.Parent = workspace.Terrain
local beamEnd = Instance.new("Attachment")
beamEnd.Name = "TutorialBeamEnd"
beamEnd.Orientation = BEAM_ATTACHMENT_ROTATION
beamEnd.Parent = workspace.Terrain

local beam = beamTemplate:Clone()
beam.Attachment0 = beamStart
beam.Attachment1 = beamEnd
beam.FaceCamera = false -- the ends' rotation sets which way the beam lies
beam.Enabled = false
beam.Parent = workspace.Terrain

-- The hotbar is CoreGui, so the spotlight points at this see-through stand-in sized over it.
local hotbarFrame = Instance.new("Frame")
hotbarFrame.Name = "TutorialHotbar"
hotbarFrame.BackgroundTransparency = 1
hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
hotbarFrame.Position = UDim2.new(0.5, 0, 1, -HOTBAR_BOTTOM_GAP)
hotbarFrame.Parent = spotlightFrame.Parent

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

local function formatHealth(value: number): string
	return numberFormatter:Format(math.ceil(value), 1)
end

local function setText(text: string)
	tutorialText.Text = text
end

--// Sheep highlights -----------------------------------------------------------------

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

-- Runs every frame: draws the beam from the character to beamSheep, or hides it when either is missing.
local function updateBeam()
	local playerRoot = getRoot(player.Character)
	local sheepRoot = getRoot(beamSheep)
	if not playerRoot or not sheepRoot then
		beam.Enabled = false
		return
	end

	beamStart.WorldPosition = playerRoot.Position
	beamEnd.WorldPosition = sheepRoot.Position
	beam.Enabled = true
end

--// Spotlight ---------------------------------------------------------------------------

-- Spotlights the GuiObject; nil clears it.
-- FocusUI only measures the target once, so it is called again whenever the target moves (e.g. a window popping in).
local function point(target: GuiObject?)
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

-- Sizes the hotbar stand-in to one slot per Tool the player has, then spotlights it.
local function pointAtHotbar()
	local toolCount = 0
	for _, container in { player:FindFirstChildOfClass("Backpack") or false, player.Character or false } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") then
					toolCount += 1
				end
			end
		end
	end
	local slots = math.max(toolCount, 1)
	hotbarFrame.Size = UDim2.fromOffset(slots * HOTBAR_SLOT_SIZE + (slots - 1) * HOTBAR_SLOT_GAP, HOTBAR_SLOT_SIZE)
	point(hotbarFrame)
end

--// Stages ------------------------------------------------------------------------------

-- Turns off every ScreenGui but the tutorial's; run each tick, since respawned or newly opened guis come back on.
local function hideOtherGuis()
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= tutorialGui and gui.Enabled then
			gui.Enabled = false
			table.insert(hiddenGuis, gui)
		end
	end
end

local function showOtherGuis()
	for _, gui in hiddenGuis do
		gui.Enabled = true
	end
	table.clear(hiddenGuis)
end

local function setStage(newStage: Stage)
	stage = newStage
	setHighlights({})
	beamSheep = nil
	firstSheep = nil
	point(nil)
	if HIDE_UI_STAGES[newStage] then
		hideOtherGuis()
	else
		showOtherGuis()
	end
end

-- Asks the server again for state the tutorial is still missing.
local function requestState(eventName: any)
	local now = os.clock()
	if now >= nextStateRequest then
		nextStateRequest = now + STATE_REQUEST_SECONDS
		network.fireServer(eventName)
	end
end

-- "Equip Shears": the spotlight sits on the hotbar until a shear is held out.
local function updateEquipShears()
	if isHoldingShear() then
		setStage("GoToSheep")
		return
	end
	setText("Click your Shears to hold them")
	pointAtHotbar()
end

-- "Go to a Sheep": every sheep is outlined and the beam leads to one of them.
local function updateGoToSheep()
	if not isHoldingShear() then
		setStage("EquipShears")
		return
	end
	setText("Follow the arrow to a glowing Sheep")
	local sheepList = getOwnSheep()
	setHighlights(sheepList)
	if not beamSheep or not table.find(sheepList, beamSheep) then
		beamSheep = if #sheepList > 0 then sheepList[math.random(#sheepList)] else nil
	end

	local playerRoot = getRoot(player.Character)
	if not playerRoot then
		return
	end
	for _, sheep in sheepList do
		local sheepRoot = getRoot(sheep) :: BasePart
		if getFlatDistance(playerRoot.Position, sheepRoot.Position) <= NEAR_DISTANCE then
			setStage("FirstShear")
			firstSheep = sheep
			return
		end
	end
end

-- "Click to Shear ... (HP 60/100)": the first sheep's health until it is shorn bare.
local function updateFirstShear()
	if getNumberAttribute("SheepShearedCount") > shearedBaseline then
		setStage("Shear")
		return
	end
	if not isHoldingShear() then
		setStage("EquipShears")
		return
	end

	local sheep = firstSheep
	local playerRoot = getRoot(player.Character)
	local sheepRoot = getRoot(sheep)
	if not sheep or not sheepRoot or not sheep:IsDescendantOf(workspace)
		or (playerRoot and getFlatDistance(playerRoot.Position, sheepRoot.Position) > LEAVE_DISTANCE)
	then
		setStage("GoToSheep")
		return
	end

	setHighlights({ sheep })
	local health = sheep:GetAttribute("ShearHealth")
	local maxHealth = sheep:GetAttribute("MaxShearHealth")
	if type(health) == "number" and type(maxHealth) == "number" then
		setText(`Click the Sheep to shear its Wool! (HP {formatHealth(math.max(health, 0))}/{formatHealth(maxHealth)})`)
	else
		setText("Click the Sheep to shear its Wool!")
	end
end

-- "Shear 2 more Sheep ... 0/2": sheep shorn bare after the first one.
local function updateShear()
	local count = getNumberAttribute("SheepShearedCount")
	if count < shearedBaseline then
		shearedBaseline = count -- the data was reset (e.g. /resetdata), so count from the new total
	end
	local sheared = count - shearedBaseline
	if sheared >= SHEEP_TO_SHEAR then
		setStage("Upgrades")
		return
	end
	if not isHoldingShear() then
		setText("Click your Shears to hold them")
		pointAtHotbar()
		return
	end
	point(nil)
	local remaining = SHEEP_TO_SHEAR - 1 -- the first sheep was the "Click to Shear" stage
	setText(`Nice! Shear {remaining} more Sheep for Wool ({math.max(sheared - 1, 0)}/{remaining})`)
end

-- The TUTORIAL_UPGRADES step still to buy and its card, or nil once every step's level is owned (or maxed).
-- Counted from the cards' levels, so it resumes after a rejoin.
local function getUpgradeStep(): (number?, any)
	local needed: { [string]: number } = {}
	for index, step in TUTORIAL_UPGRADES do
		needed[step.id] = (needed[step.id] or 0) + 1
		local card = upgradeStates and upgradeStates[step.id]
		if card and card.cost and (card.level or 0) < needed[step.id] then
			return index, card
		end
	end
	return nil, nil
end

-- "Upgrade 1/3": opens the shop and buys each TUTORIAL_UPGRADES step; short on wool, it sends the player back to shearing.
local function updateUpgrades()
	if not upgradeStates then
		requestState(network.RemoteEvents.RequestUpgradeState)
		setText("Open Upgrades to spend your Wool")
		point(upgradesButton)
		return
	end
	local index, card = getUpgradeStep()
	if not index then
		setStage("CloseUpgrades")
		return
	end

	local progress = `Upgrade {index}/{#TUTORIAL_UPGRADES}:`
	local shopOpen = isWindowOpen("UpgradeShop")
	if wool.Value < card.cost then
		setHighlights(if shopOpen then {} else getOwnSheep())
		if shopOpen then
			setText(`{progress} Need more Wool! Close Upgrades to shear more`)
			point(upgradeShopExit)
		elseif not isHoldingShear() then
			setText("Click your Shears to hold them")
			pointAtHotbar()
		else
			setText(`{progress} Shear Sheep for more Wool ({formatWool(wool.Value)}/{formatWool(card.cost)})`)
			point(nil)
		end
		return
	end

	setHighlights({})
	if not shopOpen then
		setText(`{progress} Open Upgrades. Upgrades make you earn Wool faster!`)
		point(upgradesButton)
	else
		local cardFrame = upgradeCards:FindFirstChild(card.id)
		local purchase = cardFrame and cardFrame:FindFirstChild("Purchase")
		setText(`{progress} {TUTORIAL_UPGRADES[index].text}`)
		point(if purchase and purchase:IsA("GuiObject") then purchase else nil)
	end
end

local function updateCloseUpgrades()
	if not isWindowOpen("UpgradeShop") then
		setStage("Rebirth")
		return
	end
	setText("Great job! Close Upgrades")
	point(upgradeShopExit)
end

-- Gains wool up to the first rebirth's cost, then opens the rebirth screen and presses Rebirth.
local function updateRebirth()
	local cost = rebirthCost
	if not cost then
		requestState(network.RemoteEvents.RequestRebirthState)
		setText("Shear Sheep for Wool to Rebirth")
		return
	end

	if wool.Value < cost then
		setText(`Shear Sheep for Wool to Rebirth ({formatWool(wool.Value)}/{formatWool(cost)})`)
		point(nil)
	elseif not isWindowOpen("Rebirth") then
		setText("Open Rebirth")
		point(rebirthHudButton)
	else
		setText("Press Rebirth! Luck brings rarer Sheep")
		point(rebirthButton)
	end
end

local UPDATERS: { [Stage]: () -> () } = {
	EquipShears = updateEquipShears,
	GoToSheep = updateGoToSheep,
	FirstShear = updateFirstShear,
	Shear = updateShear,
	Upgrades = updateUpgrades,
	CloseUpgrades = updateCloseUpgrades,
	Rebirth = updateRebirth,
}

--// Lifecycle ---------------------------------------------------------------------------

-- Hides every HUD button the tutorial doesn't use; showHudButtons puts them back.
local function hideHudButtons()
	for _, button in hudButtons:GetChildren() do
		if button:IsA("GuiObject") and button.Visible and not KEEP_HUD_BUTTONS[button.Name] then
			button.Visible = false
			table.insert(hiddenHudButtons, button)
		end
	end
end

local function showHudButtons()
	for _, button in hiddenHudButtons do
		button.Visible = true
	end
	table.clear(hiddenHudButtons)
end

local function stop()
	stage = "Done"
	setHighlights({})
	point(nil)
	if beamConnection then
		beamConnection:Disconnect()
		beamConnection = nil
	end
	beam:Destroy()
	beamStart:Destroy()
	beamEnd:Destroy()
	hotbarFrame:Destroy()
	tutorialMain.Visible = false
	spotlightFrame.Visible = false
	tutorialGui.Enabled = false
	showHudButtons()
	showOtherGuis()
end

-- The object's UIScale and the size it pops up to; a Studio-built UIScale keeps its value as the full size, otherwise one is added at 1.
local function getPopScale(guiObject: GuiObject): (UIScale, number)
	local scale = guiObject:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = guiObject
	end
	local uiScale = scale :: UIScale
	local fullScale = popFullScales[uiScale] or uiScale.Scale
	popFullScales[uiScale] = fullScale
	return uiScale, fullScale
end

local function popIn(guiObject: GuiObject)
	local uiScale, fullScale = getPopScale(guiObject)
	uiScale.Scale = 0
	guiObject.Visible = true
	tweenService:Create(uiScale, POP_IN, { Scale = fullScale }):Play()
end

-- Yields until the object has shrunk away, then hides it.
local function popOut(guiObject: GuiObject)
	local uiScale, fullScale = getPopScale(guiObject)
	local tween = tweenService:Create(uiScale, POP_OUT, { Scale = 0 })
	tween:Play()
	tween.Completed:Wait()
	guiObject.Visible = false
	uiScale.Scale = fullScale
end

-- Pops the completed label and Tip in over the dimmed screen, holds them, then pops them out.
local function showCompleted()
	tutorialGui.Enabled = true
	darkOverlay.Visible = true
	popIn(completedLabel)
	popIn(tip)
	task.wait(COMPLETED_SECONDS)

	task.spawn(popOut, tip)
	popOut(completedLabel)
	darkOverlay.Visible = false
	tutorialGui.Enabled = false
end

local function start(firstStage: Stage)
	local startRebirths = getNumberAttribute("Rebirths")
	tutorialGui.ResetOnSpawn = false
	tutorialGui.DisplayOrder = DISPLAY_ORDER
	tutorialGui.Enabled = true
	tutorialMain.Visible = true
	tutorialFrame.Visible = true
	tutorialText.Visible = true
	hideHudButtons()

	setStage(firstStage)
	beamConnection = runService.RenderStepped:Connect(updateBeam)

	while stage ~= "Done" do
		local rebirths = getNumberAttribute("Rebirths")
		if rebirths < startRebirths then
			startRebirths = rebirths -- the data was reset, so the next rebirth still ends the tutorial
		elseif rebirths > startRebirths then
			stop()
			showCompleted()
			return
		end
		UPDATERS[stage]()
		if HIDE_UI_STAGES[stage] then
			hideOtherGuis()
		end
		task.wait(TICK_SECONDS)
	end
end

tutorialGui.Enabled = false
spotlightFrame.Visible = false -- FocusUI shows it when there's a button to point at
darkOverlay.Visible = false
completedLabel.Visible = false
tip.Visible = false

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
	shearedBaseline = getNumberAttribute("SheepShearedCount")
	start("EquipShears")
elseif getNumberAttribute("Rebirths") >= 1 or getNumberAttribute("Prestiges") >= 1 then
	stop()
else
	local sheared = getNumberAttribute("SheepShearedCount")
	start(if sheared >= SHEEP_TO_SHEAR then "Upgrades" elseif sheared >= 1 then "Shear" else "EquipShears")
end
