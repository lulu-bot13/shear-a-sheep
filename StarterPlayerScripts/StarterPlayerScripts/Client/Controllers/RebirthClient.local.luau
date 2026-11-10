--[[
	The rebirth screen (StarterGui.RebirthScreen): wool cost, before -> after luck, rebirth / Prestige counts and the sheep the rebirth
	needs (spinning in RequirementTip.SheepViewport, found or its pity countdown). Plays the pen's rebirth poof. RebirthHandler decides everything.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RebirthClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local soundService = game:GetService("SoundService")
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local runService = game:GetService("RunService")

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local hudButtons = playerGui:WaitForChild("Main"):WaitForChild("Buttons")
local openButton = hudButtons:WaitForChild("Rebirth") :: GuiButton
local hudProgress = openButton:WaitForChild("Progress") :: TextLabel

local rebirthGui = playerGui:WaitForChild("RebirthScreen") :: ScreenGui
local mainFrame = rebirthGui:WaitForChild("Main") :: Frame -- not the "Main" ImageLabel (panel art) inside it
local exitButton = mainFrame:WaitForChild("ExitButton") :: GuiButton
local rebirthButton = mainFrame:WaitForChild("RebirthButton") :: ImageButton -- image only; tinted grey while unaffordable
local skipRebirthButton = mainFrame:WaitForChild("SkipRebirth") :: GuiButton
-- The 1X / MAX switch sits beside Main, directly under the ScreenGui; its ToggleButton slides along the track.
local amountSwitch = rebirthGui:WaitForChild("Switch") :: GuiObject
local amountKnob = amountSwitch:WaitForChild("ToggleButton") :: GuiButton
local amountLabel = amountKnob:WaitForChild("Multiplier") :: TextLabel
local rebirthCount = mainFrame:WaitForChild("RebirthCount") :: TextLabel
local prestigeCount = mainFrame:WaitForChild("Prestiges") :: TextLabel

local woolPrice = mainFrame:WaitForChild("WoolPrice") :: TextLabel

local requirementTip = mainFrame:WaitForChild("RequirementTip") :: GuiObject
local requirementText = requirementTip:WaitForChild("RequirementText") :: TextLabel
local keepNote = requirementTip:WaitForChild("KeepNote") :: TextLabel
local sheepViewport = requirementTip:WaitForChild("SheepViewport") :: ViewportFrame -- the rebirth sheep's preview
local sheepStatus = sheepViewport:WaitForChild("Status") :: TextLabel -- NOT FOUND / FOUND badge on it
local vfxFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("VFX", 10)
local poofTemplate = vfxFolder and vfxFolder:FindFirstChild("PoofAttachment") :: Attachment?
if not poofTemplate then
	warn("RebirthClient: ReplicatedStorage.Assets.VFX.PoofAttachment is missing, so the rebirth poof is skipped.")
end

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local numberFormatter = require(replicatedStorage.Shared.Utils.NumberFormatter)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local luckRain = require(script.Parent.Parent.Modules.LuckRain)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)
local rebirthVFX = require(script.Parent.Parent.Modules.RebirthVFX)
local sheepModels = require(script.Parent.Parent.Modules.SheepModels)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

-- The before -> after labels built in Studio.
local rewardBefore = mainFrame:WaitForChild("BeforeFrame"):WaitForChild("PreviousAmount") :: TextLabel
local rewardAfter = mainFrame:WaitForChild("AfterFrame"):WaitForChild("AfterAmount") :: TextLabel

--// Sounds
local rebirthedSound = soundService:WaitForChild("UISounds"):FindFirstChild("Rebirthed") :: Sound?

--// Configs
local REWARD_BEFORE_COLOR = Color3.fromRGB(170, 170, 170)
local REWARD_AFTER_COLOR = Color3.fromRGB(170, 235, 170)
local KEEP_NOTE_TEXT = "Only costs wool! Your upgrades, sheep and Luck are kept."
-- What the RequirementTip labels say once the player can Prestige.
local PRESTIGE_TIP_TEXT = {
	RequirementText = "REBIRTHS MAXED, PRESTIGE TO GO FURTHER!",
	KeepNote = `<font color="#FF5A5A">RESETS ALL STATS (index and shear count stays the same)</font>`,
}
local GREY_TINT = Color3.fromRGB(140, 140, 140) -- the Rebirth button's ImageColor3 while unaffordable
local SHINE_TAG = "ShineButton"
local AMOUNTS = { 1, "max" } -- what the Switch flips between; "max" is as many as the player can afford
local KNOB_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STATE_REQUEST_SECONDS = 0.55 -- just over RebirthServer's cooldown, which drops state requests sent sooner

-- The HUD button wiggles every few seconds while a rebirth is ready.
local ALERT_SHAKE_SECONDS = 3
local ALERT_SHAKE_ANGLES = { -10, 10, -8, 8, -4, 4, 0 }
local CLICK_SHAKE_ANGLES = { -3, 3, -2, 2, 0 }

local REASON_TEXT = {
	NotReady = "Not enough wool to rebirth",
	MaxRebirths = "Rebirths are MAXED",
	Busy = "Already rebirthing",
	NeedSheep = "Find the rebirth sheep first!",
}
local PREVIEW_CAMERA_FOV = 40
local PREVIEW_CAMERA_PITCH = math.rad(15)
local PREVIEW_FILL = 0.9 -- of the viewport the spinning sheep fills
local PREVIEW_SPIN_SPEED = math.rad(45) -- per second, while the screen is open
-- The rebirth sheep stays in full colour (unlike the Index's silhouettes) so the player knows what to look for.
local SHEEP_NAME_COLOR = "#FFD54A"
local STATUS_LOOKS = {
	found = { text = "FOUND ✓", color = Color3.fromRGB(66, 255, 82) },
	missing = { text = "NOT FOUND", color = Color3.fromRGB(255, 80, 80) },
}
local MAX_POOFS = 45

--// State
local state: any = nil -- the last RebirthState from the server
local prestigeState: any = nil -- the last PrestigeState; once it can Prestige, the Rebirth button prestiges instead
local wasReady = false -- so the "Rebirth Available" alert shows once each time the bar reaches 100%
local normalTint = rebirthButton.ImageColor3 -- as built in Studio, restored once affordable
local amountIndex = 1 -- into AMOUNTS; back to 1X every time the screen opens
local nextStateRequest = 0
local stateRequestQueued = false
local tipTexts: { [TextLabel]: string } = {} -- each RequirementTip label's own text, restored while the player can't Prestige
local previewSheep: string? = nil -- the sheep in SheepViewport right now
local previewModel: Model? = nil
local previewCenter = Vector3.zero
local previewAngle = 0
local spinConnection: RBXScriptConnection? = nil
local knobOnePosition = amountKnob.Position -- the 1X side, as built in Studio
-- The MAX side mirrors the 1X side across the track.
local knobMirror = 2 * amountKnob.AnchorPoint.X - 1
local knobMaxPosition = UDim2.new(
	1 - knobOnePosition.X.Scale + knobMirror * amountKnob.Size.X.Scale,
	-knobOnePosition.X.Offset + knobMirror * amountKnob.Size.X.Offset,
	knobOnePosition.Y.Scale,
	knobOnePosition.Y.Offset
)
local restRotations = {
	[rebirthButton] = rebirthButton.Rotation,
	[skipRebirthButton] = skipRebirthButton.Rotation,
	[openButton] = openButton.Rotation,
}

--// Helpers -------------------------------------------------------------------------

local function formatMultiplier(value: number): string
	return "x" .. (string.format("%.2f", value):gsub("%.?0+$", ""))
end

-- "x1.08 Luck"
local function formatRewards(luckFactor: number): string
	return `{formatMultiplier(luckFactor)} Luck`
end

local function canPrestige(): boolean
	return prestigeState ~= nil and prestigeState.canPrestige == true
end

local function getSelectedAmount(): number | string
	return AMOUNTS[amountIndex]
end

-- Asks for the state for the selected amount; one sent too soon after the last goes out once the cooldown ends.
local function requestState()
	if stateRequestQueued then
		return
	end
	local delaySeconds = nextStateRequest - os.clock()
	if delaySeconds > 0 then
		stateRequestQueued = true
		task.delay(delaySeconds, function()
			stateRequestQueued = false
			requestState()
		end)
		return
	end
	nextStateRequest = os.clock() + STATE_REQUEST_SECONDS
	network.fireServer(network.RemoteEvents.RequestRebirthState, getSelectedAmount())
end

local function setAmountIndex(index: number)
	amountIndex = index
	local amount = getSelectedAmount()
	amountLabel.Text = if amount == "max" then "MAX" else `{amount}X`
	local knobPosition = if amount == "max" then knobMaxPosition else knobOnePosition
	tweenService:Create(amountKnob, KNOB_TWEEN, { Position = knobPosition }):Play()
end

local function toggleAmount()
	setAmountIndex(amountIndex % #AMOUNTS + 1)
	requestState()
end

-- Wiggles around the button's rest angle, so a shake started mid hover-tilt can't leave it tilted.
local function shake(button: GuiObject, angles: { number })
	task.spawn(function()
		local baseRotation = restRotations[button] or button.Rotation
		for _, angle in angles do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = baseRotation + angle }):Play()
			task.wait(0.04)
		end
	end)
end

--// Rendering --------------------------------------------------------------------------

-- How far the player's wool is towards the next rebirth, 0 to 1.
local function getProgress(): number
	if state.maxed or state.woolCost <= 0 then
		return 1
	end
	return math.clamp(state.wool / state.woolCost, 0, 1)
end

-- Puts a scriptless copy of the sheep in SheepViewport, sized so it stays inside the frame as it spins.
local function buildPreview(sheepType: string)
	for _, child in sheepViewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	previewModel = nil
	local template = sheepModels.find(sheepType)
	if not template then
		return
	end

	local model = template:Clone()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("BillboardGui") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model:PivotTo(CFrame.new())
	model.Parent = sheepViewport

	local camera = Instance.new("Camera")
	camera.FieldOfView = PREVIEW_CAMERA_FOV
	camera.Parent = sheepViewport
	sheepViewport.CurrentCamera = camera

	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = boxCFrame.Position
	local radius = math.max(Vector2.new(boxSize.X, boxSize.Z).Magnitude, boxSize.Y) / 2
	local distance = radius / math.tan(math.rad(PREVIEW_CAMERA_FOV / 2)) / PREVIEW_FILL
	local direction = (CFrame.Angles(0, math.pi, 0) * CFrame.Angles(-PREVIEW_CAMERA_PITCH, 0, 0)).LookVector
	camera.CFrame = CFrame.lookAt(center - direction * distance, center)
	previewModel = model
	previewCenter = center
end

-- The sheep the next rebirth needs, with a FOUND / NOT FOUND badge; hidden when none is needed or the player can Prestige.
local function renderSheepPreview()
	local sheepType = if state and not canPrestige() then state.requiredSheep else nil
	sheepViewport.Visible = sheepType ~= nil
	if sheepType and sheepType ~= previewSheep then
		buildPreview(sheepType)
	end
	previewSheep = sheepType

	local look = if state and state.requiredFound then STATUS_LOOKS.found else STATUS_LOOKS.missing
	sheepStatus.Text = look.text
	sheepStatus.BackgroundColor3 = look.color
end

-- Turns the preview sheep round its middle while the screen is open.
local function spinPreview(deltaTime: number)
	local model = previewModel
	if not model or not sheepViewport.Visible then
		return
	end
	previewAngle = (previewAngle + deltaTime * PREVIEW_SPIN_SPEED) % (math.pi * 2)
	model:PivotTo(CFrame.new(previewCenter) * CFrame.Angles(0, previewAngle, 0) * CFrame.new(-previewCenter))
end

-- The rebirth sheep: "FIND THE GOLDEN SHEEP TO REBIRTH" (its name highlighted) with its pity countdown, or "Found ✓" once it's in the Index.
local function renderRequirementTip(prestigeReady: boolean)
	for label, originalText in tipTexts do
		label.Text = if prestigeReady then PRESTIGE_TIP_TEXT[label.Name] else originalText
	end
	local name = state and state.requiredName
	if prestigeReady or not name then
		return
	end
	local highlighted = `<font color="{SHEEP_NAME_COLOR}">{name}</font>`
	if state.requiredFound then
		keepNote.Text = `{highlighted}: Found ✓`
	else
		requirementText.Text = `FIND THE <font color="{SHEEP_NAME_COLOR}">{string.upper(name)}</font> TO REBIRTH`
		keepNote.Text = `{highlighted} not found yet - guaranteed in {state.pityLeft} {if state.pityLeft == 1 then "spawn" else "spawns"}`
	end
end

local function getNeedSheepText(): string
	local name = state and state.requiredName
	return if name then `Find the {name} first!` else REASON_TEXT.NeedSheep
end

local function render()
	if not state then
		return
	end

	rebirthCount.Text = `You have {state.rebirths} {if state.rebirths == 1 then "rebirth" else "rebirths"}`
	prestigeCount.Text = `You have {state.prestiges} prestige`
	rewardBefore.Text = formatRewards(state.luckFactor)
	rewardAfter.Text = if state.maxed then "MAX" else formatRewards(state.amountLuckFactor)

	woolPrice.Text = if state.maxed then "MAX" else numberFormatter:Format(state.amountCost, 1)
	local prestigeReady = canPrestige()
	renderRequirementTip(prestigeReady)
	renderSheepPreview()

	local affordable = state.amountCanRebirth and not state.maxed
	rebirthButton.ImageColor3 = if affordable or prestigeReady then normalTint else GREY_TINT
end

-- The HUD button's Progress shows the wool percentage.
local function updateHud()
	if state then
		-- Rounded down, so 100% only shows once the rebirth is actually affordable.
		hudProgress.Text = if state.maxed then "MAX" else `{math.floor(getProgress() * 100)}%`
	end
end

--// Setup -------------------------------------------------------------------------------

local window = windowsManager.register("Rebirth", {
	gui = rebirthGui,
	frame = mainFrame,
	openButton = openButton,
	closeButton = exitButton,
	onOpen = function()
		amountSwitch.Visible = true
		setAmountIndex(1)
		render()
		requestState()
		if not spinConnection then
			spinConnection = runService.RenderStepped:Connect(spinPreview)
		end
	end,
	-- WindowsManager only pops Main in and out, so the Switch beside it is hidden as soon as the window closes.
	onClose = function()
		amountSwitch.Visible = false
		if spinConnection then
			spinConnection:Disconnect()
			spinConnection = nil
		end
	end,
})
amountSwitch.Visible = false
sheepViewport.Visible = false -- until the server says which sheep is needed

setAmountIndex(1)

rewardBefore.TextColor3 = REWARD_BEFORE_COLOR
rewardAfter.TextColor3 = REWARD_AFTER_COLOR

-- The Studio note still warns that rebirths reset progress.
for _, descendant in mainFrame:GetDescendants() do
	if descendant:IsA("TextLabel") and descendant.Text:lower():find("reset") then
		descendant.Text = KEEP_NOTE_TEXT
	end
end
for _, label in { requirementText, keepNote } do
	tipTexts[label] = label.Text
end
-- The sheep's name and the Prestige warning are coloured with font tags.
requirementText.RichText = true
keepNote.RichText = true
collectionService:AddTag(rebirthButton, SHINE_TAG)
hudProgress.Text = "0%"
updateHud()

task.spawn(function()
	while true do
		task.wait(ALERT_SHAKE_SECONDS)
		if state and state.canRebirth and not window.isOpen() then
			shake(openButton, ALERT_SHAKE_ANGLES)
		end
	end
end)

amountKnob.MouseButton1Click:Connect(toggleAmount)

rebirthButton.MouseButton1Click:Connect(function()
	if canPrestige() then
		network.fireServer(network.RemoteEvents.RequestPrestige)
	elseif not state or state.amount ~= getSelectedAmount() then
		requestState()
	elseif state.amountCanRebirth and not state.maxed then
		network.fireServer(network.RemoteEvents.RequestRebirth, getSelectedAmount())
	else
		local text = if state.maxed then REASON_TEXT.MaxRebirths elseif state.needsSheep then getNeedSheepText() else REASON_TEXT.NotReady
		alerts.show(text, "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

-- The server prompts the Skip Rebirth product, so it can refuse at max rebirths or before the rebirth sheep is found.
skipRebirthButton.MouseButton1Click:Connect(function()
	if state and (state.maxed or (state.requiredSheep and not state.requiredFound)) then
		alerts.show(if state.maxed then REASON_TEXT.MaxRebirths else getNeedSheepText(), "error")
		shake(skipRebirthButton, CLICK_SHAKE_ANGLES)
		return
	end
	purchaseEffect.play()
	network.fireServer(network.RemoteEvents.RequestProductPrompt, "SkipRebirth")
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RebirthState, function(newState: any)
	state = newState
	local ready = newState.canRebirth == true and not newState.maxed
	if ready and not wasReady then
		announcements.show("RebirthAlert", "Rebirth Available")
	end
	wasReady = ready
	updateHud()
	if window.isOpen() then
		render()
	end
end)

network.connectEvent(network.RemoteEvents.RebirthResult, function(success: boolean, reason: string?, rebirths: number?, count: number?)
	if success then
		local times = if count and count > 1 then ` x{count}` else ""
		announcements.show("Rebirthed", `Rebirthed{times} ({rebirths or "?"})`)
		if rebirthedSound then
			rebirthedSound:Play()
		end
		luckRain.play(rebirthGui)
		if player.Character then
			rebirthVFX.play(player.Character)
		end
	else
		alerts.show(if reason == "NeedSheep" then getNeedSheepText() else REASON_TEXT[reason or ""] or "Can't rebirth", "error")
		shake(rebirthButton, CLICK_SHAKE_ANGLES)
	end
end)

-- A rebirth clears that player's pen in a burst of PoofAttachment puffs (everyone nearby sees it).
network.connectEvent(network.RemoteEvents.SheepPoof, function(positions: { Vector3 })
	if not poofTemplate or type(positions) ~= "table" then
		return
	end
	for index, position in positions do
		if index > MAX_POOFS or typeof(position) ~= "Vector3" then
			break
		end
		local poof = poofTemplate:Clone()
		poof.WorldPosition = position
		poof.Parent = workspace.Terrain
		local longest = 0
		for _, emitter in poof:GetDescendants() do
			if emitter:IsA("ParticleEmitter") then
				local count = emitter:GetAttribute("EmitCount")
				emitter:Emit(if type(count) == "number" then count else 10)
				longest = math.max(longest, emitter.Lifetime.Max)
			end
		end
		debris:AddItem(poof, longest + 0.1)
	end
end)

network.connectEvent(network.RemoteEvents.PrestigeState, function(newState: any)
	prestigeState = newState
	if window.isOpen() then
		render()
	end
end)

requestState()
network.fireServer(network.RemoteEvents.RequestPrestigeState)
