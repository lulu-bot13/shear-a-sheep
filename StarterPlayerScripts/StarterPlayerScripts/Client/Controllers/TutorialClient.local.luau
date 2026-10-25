--[[
	First-play tutorial: go to a sheep, shear 3, buy More Wool, close the shop, gain wool, then rebirth.
	Each step is worked out from the player's progress, so it resumes after a rejoin and ends at the first rebirth.
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local guiService = game:GetService("GuiService")
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
local mainGui = playerGui:WaitForChild("Main")
local pointer = mainGui:WaitForChild("Pointer") :: GuiObject
local hudButtons = mainGui:WaitForChild("Buttons")
local upgradesButton = hudButtons:WaitForChild("Upgrades") :: GuiButton
local rebirthHudButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local upgradeShopMain = playerGui:WaitForChild("UpgradeShop"):WaitForChild("Main")
local upgradeCards = upgradeShopMain:WaitForChild("ScrollingFrame")
local upgradeShopExit = upgradeShopMain:FindFirstChild("Exit", true) :: GuiObject? -- found the same way WindowsManager wires it
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
local COMPLETED_SECONDS = 3 -- how long the completed label stays up
local SHEEP_TO_SHEAR = 3
local MORE_WOOL_ID = "MoreWool"
local KEEP_HUD_BUTTONS = { Upgrades = true, Rebirth = true } -- the only HUD buttons shown until the tutorial ends
local POP_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_COLOR = Color3.fromRGB(255, 230, 90)
local BEAM_WIDTH = 0.6
local BEAM_TEXTURE = "" -- "rbxassetid://..." for an arrow texture; empty draws a plain beam

local POINTER_ROTATION = 180
local POINTER_GAP = 6 -- pixels between the pointer and the top of its target
local POINTER_BOB_PIXELS = 12
local POINTER_BOB_SPEED = 5

type Stage = "GoToSheep" | "Shear" | "Upgrades" | "CloseUpgrades" | "Rebirth" | "Done"

--// State
local stage: Stage = "GoToSheep"
local shearedBaseline = 0 -- SheepShearedCount the "Shear 3 Sheep" progress counts up from
local hiddenHudButtons: { GuiObject } = {}
local popFullScales: { [UIScale]: number } = {} -- each popped object's full size, read before its first pop
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
	setText("Walk to a Sheep")
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

-- "Shear Sheep for Wool 1/3": sheep shorn bare since the tutorial started.
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
		setText("Equip your Shears")
		return
	end
	setText(`Shear Sheep for Wool {sheared}/{SHEEP_TO_SHEAR}`)
end

-- Opens the shop and buys More Wool; asks for wool first if it isn't affordable.
local function updateUpgrades()
	local card = upgradeStates and upgradeStates[MORE_WOOL_ID]
	if not card then
		requestState(network.RemoteEvents.RequestUpgradeState)
		setText("Spend Wool on Upgrades")
		point(upgradesButton)
		return
	end
	if (card.level or 0) > 0 or not card.cost then
		setStage("CloseUpgrades")
		return
	end

	if not isWindowOpen("UpgradeShop") then
		setText("Spend Wool on Upgrades")
		point(upgradesButton)
	elseif wool.Value < card.cost then
		setText(`Shear sheep for Wool {formatWool(wool.Value)}/{formatWool(card.cost)}`)
		point(nil)
	else
		local cardFrame = upgradeCards:FindFirstChild(MORE_WOOL_ID)
		local purchase = cardFrame and cardFrame:FindFirstChild("Purchase")
		setText("Buy More Wool to earn faster")
		point(if purchase and purchase:IsA("GuiObject") then purchase else nil)
	end
end

local function updateCloseUpgrades()
	if not isWindowOpen("UpgradeShop") then
		setStage("Rebirth")
		return
	end
	setText("Close Upgrades")
	point(upgradeShopExit)
end

-- Gains wool up to the first rebirth's cost, then opens the rebirth screen and presses Rebirth.
local function updateRebirth()
	local cost = rebirthCost
	if not cost then
		requestState(network.RemoteEvents.RequestRebirthState)
		setText("Gain Wool")
		return
	end

	if wool.Value < cost then
		setText(`Gain {formatWool(cost)} Wool to Rebirth {formatWool(wool.Value)}/{formatWool(cost)}`)
		point(nil)
	elseif not isWindowOpen("Rebirth") then
		setText("Open Rebirths")
		point(rebirthHudButton)
	else
		setText("Rebirth for a permanent Wool boost!")
		point(rebirthButton)
	end
end

local UPDATERS: { [Stage]: () -> () } = {
	GoToSheep = updateGoToSheep,
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
	tutorialMain.Visible = false
	spotlightFrame.Visible = false
	tutorialGui.Enabled = false
	showHudButtons()
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

-- Pops the completed label in over the dimmed screen, holds it, then pops it out; the Tip stays up until the next rebirth.
local function showCompleted()
	tutorialGui.Enabled = true
	darkOverlay.Visible = true
	popIn(completedLabel)
	popIn(tip)
	task.wait(COMPLETED_SECONDS)

	popOut(completedLabel)
	darkOverlay.Visible = false

	-- The Tip stays up until the player's next rebirth.
	local rebirths = getNumberAttribute("Rebirths")
	while true do
		player:GetAttributeChangedSignal("Rebirths"):Wait()
		local newRebirths = getNumberAttribute("Rebirths")
		if newRebirths > rebirths then
			break
		end
		rebirths = newRebirths -- the data was reset, so the next rebirth still hides it
	end
	popOut(tip)
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
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Rotation = POINTER_ROTATION
	pointer.Visible = false
	pointer.Parent = tutorialGui
	hideHudButtons()

	setStage(firstStage)
	renderConnection = runService.RenderStepped:Connect(updatePointer)

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
		task.wait(TICK_SECONDS)
	end
end

tutorialGui.Enabled = false
pointer.Visible = false
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
	start("GoToSheep")
elseif getNumberAttribute("Rebirths") >= 1 then
	print(`[TutorialClient] skipped: this save has {getNumberAttribute("Rebirths")} rebirth(s)`)
	stop()
else
	start(if getNumberAttribute("SheepShearedCount") >= SHEEP_TO_SHEAR then "Upgrades" else "GoToSheep")
end
