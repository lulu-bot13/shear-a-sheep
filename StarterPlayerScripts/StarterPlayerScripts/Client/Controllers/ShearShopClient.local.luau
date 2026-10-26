--[[
	The shear shop UI (StarterGui.Shop).

	Touching the ShearShopHitbox in the CenterPlaza opens the shop; walking away closes it. Each shear in
	ShearShopUIData gets a card cloned from the Template: name, speed / damage, a spinning
	3D preview and a purchase button. Buying is validated by the server (ShearShopHandler);
	the cards update from the player's "ShearId" / "OwnedShears" attributes and wool. A shear that is
	owned shows EQUIP (EquipShear); the equipped one shows UNEQUIP, which switches back to the default shear.

	Performance: the previews are built once (on first open), and ONE render connection
	exists only while the shop is open. It turns each preview by moving its ViewportFrame
	camera (no model is moved) and skips cards scrolled out of view.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ShearShopClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local soundService = game:GetService("SoundService")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local UIData = require(script.Parent.Parent.Modules.ShearShopUIData)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local shearTemplates = replicatedStorage:WaitForChild("Assets"):WaitForChild("Shears")
local shopGui = playerGui:WaitForChild("Shop") :: ScreenGui
local mainFrame = shopGui:WaitForChild("Main") :: Frame
local scrollFrame = mainFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local cardTemplate = scrollFrame:WaitForChild("Template") :: Frame
local wool = player:WaitForChild("Inventory"):WaitForChild("Wool") :: IntValue
local shopHitbox = workspace:WaitForChild("Base"):WaitForChild("CenterPlaza"):WaitForChild("ShearShop")
	:WaitForChild("Shack"):WaitForChild("ShearShopHitbox") :: BasePart

--// Sounds
local purchaseSound = soundService:WaitForChild("UISounds"):FindFirstChild("Cash") :: Sound?

--// Configs
local CLOSE_DISTANCE = 6 -- studs outside the hitbox before the shop closes itself
local DEFAULT_SHEAR_ID = "DefaultShear"
local DISTANCE_CHECK_SECONDS = 0.25
local MESSAGE_SECONDS = 1.3
-- Main HUD children left up while the shop is open; Ability is hidden by AbilityClient whenever any window is open.
local HUD_KEEP = { WoolAmount = true, SheepCount = true, Ability = true }

local REASON_TEXT = {
	NoWool = "Not enough wool",
	TooFar = "Too far away",
	Owned = "Already owned",
	NotOwned = "Buy it first",
	Locked = "Shear more sheep",
}

type Card = {
	info: any,
	frame: Frame,
	purchase: GuiButton,
	purchaseLabel: TextLabel,
	priceLabel: TextLabel,
	viewport: ViewportFrame?,
	camera: Camera?,
	center: Vector3,
	distance: number,
	messageToken: number,
}

--// State
local cards: { Card } = {}
local cardById: { [string]: Card } = {}
local previewsBuilt = false
local nearShop = false
local renderConnection: RBXScriptConnection? = nil
local spinAngle = 0
local pendingPurchaseId: string? = nil -- equips reply on the same event, so only this id plays the purchase sound
local lastSheepSheared: number? = nil -- nil until the saved count first arrives, so joining doesn't announce old unlocks
local hiddenHud: { GuiObject } = {}

--// Helpers ---------------------------------------------------------------------

local function shake(button: GuiObject)
	task.spawn(function()
		for _, angle in { -3, 3, -2, 2, 0 } do
			tweenService:Create(button, TweenInfo.new(0.04), { Rotation = angle }):Play()
			task.wait(0.04)
		end
	end)
end

-- The shears in the player's temporary inventory (the server's "OwnedShears" attribute: "DefaultShear,SteelShears").
local function isOwned(id: string): boolean
	local owned = player:GetAttribute("OwnedShears")
	if type(owned) ~= "string" then
		return id == DEFAULT_SHEAR_ID
	end
	for ownedId in string.gmatch(owned, "[^,]+") do
		if ownedId == id then
			return true
		end
	end
	return false
end

local function getSheepSheared(): number
	local count = player:GetAttribute("SheepShearedCount")
	return if type(count) == "number" then count else 0
end

local function getState(card: Card): string
	if card.info.id == (player:GetAttribute("ShearId") or DEFAULT_SHEAR_ID) then
		return "equipped"
	elseif isOwned(card.info.id) then
		return "owned"
	elseif getSheepSheared() < card.info.sheepRequired then
		return "locked"
	elseif wool.Value >= card.info.price then
		return "ready"
	end
	return "poor"
end

local function refreshCard(card: Card)
	local state = getState(card)
	local colors = UIData.ButtonColors

	card.priceLabel.Text = if state == "locked"
		then UIData.formatSheep(card.info.sheepRequired)
		else UIData.formatWool(card.info.price)

	if state == "equipped" then
		card.purchase.BackgroundColor3 = colors.Equipped
		card.purchaseLabel.Text = if card.info.id == DEFAULT_SHEAR_ID then "EQUIPPED" else "UNEQUIP"
	elseif state == "owned" then
		card.purchase.BackgroundColor3 = colors.Owned
		card.purchaseLabel.Text = "EQUIP"
	elseif state == "locked" then
		card.purchase.BackgroundColor3 = colors.Locked
		card.purchaseLabel.Text = "BUY"
	else
		card.purchase.BackgroundColor3 = if state == "ready" then colors.Ready else colors.Poor
		card.purchaseLabel.Text = "BUY"
	end

	card.purchase:SetAttribute("State", state)
end

local function refreshAll()
	for _, card in cards do
		card.messageToken += 1 -- a pending message must not overwrite the fresh text
		refreshCard(card)
	end
end

-- Shows a short message in the card's Price, then goes back to the price.
local function flashMessage(card: Card, text: string)
	card.messageToken += 1
	local token = card.messageToken
	card.priceLabel.Text = text
	alerts.show(`{card.info.displayName}: {text}`, "error")
	shake(card.purchase)

	task.delay(MESSAGE_SECONDS, function()
		if token == card.messageToken then
			refreshCard(card)
		end
	end)
end

-- Pops StarterGui.Alerts.Main.ShearAlert for each shear whose sheep requirement the new count just reached.
local function checkShearUnlocks()
	local count = player:GetAttribute("SheepShearedCount")
	if type(count) ~= "number" then
		return
	end

	local previous = lastSheepSheared
	lastSheepSheared = count
	if not previous then
		return
	end

	for _, info in UIData.Shears do
		if info.sheepRequired > previous and info.sheepRequired <= count and not isOwned(info.id) then
			announcements.show("ShearAlert", `NEW SHEAR UNLOCKED: {info.displayName}`)
		end
	end
end

--// Cards & previews ---------------------------------------------------------------

-- Sizes the scroll frame's canvas (Y) to fit every card plus the frame's own padding.
local function updateCanvasSize()
	local layout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		return
	end

	local padding = scrollFrame:FindFirstChildOfClass("UIPadding")
	local paddingY = 0
	if padding then
		local frameHeight = scrollFrame.AbsoluteSize.Y
		paddingY = padding.PaddingTop.Offset + padding.PaddingTop.Scale * frameHeight
			+ padding.PaddingBottom.Offset + padding.PaddingBottom.Scale * frameHeight
	end

	scrollFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + paddingY)
end

local function createCards()
	cardTemplate.Visible = false
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None

	-- Every card added re-fits the canvas. The layout only measures its content after the child lands, so the
	-- refresh is deferred; the size-changed hook keeps it right when the window is resized too.
	scrollFrame.ChildAdded:Connect(function(child: Instance)
		if child:IsA("GuiObject") then
			task.defer(updateCanvasSize)
		end
	end)

	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
	end

	for index, info in UIData.Shears do
		local frame = cardTemplate:Clone()
		frame.Name = info.id
		frame.LayoutOrder = index
		frame.Visible = true

		local nameLabel = frame:WaitForChild("ShearName") :: TextLabel
		local buffsLabel = frame:WaitForChild("Buffs") :: TextLabel
		local purchase = frame:WaitForChild("Purchase") :: GuiButton
		local priceLabel = frame:WaitForChild("Price") :: TextLabel
		local purchaseLabel = purchase:WaitForChild("Label") :: TextLabel

		nameLabel.Text = info.displayName
		buffsLabel.Text = `Damage: {info.damage}\nRange: {info.range} studs`
		purchase.AutoButtonColor = true
		if purchase:IsA("TextButton") then
			purchase.Text = ""
		end

		local card: Card = {
			info = info,
			frame = frame,
			purchase = purchase,
			purchaseLabel = purchaseLabel,
			priceLabel = priceLabel,
			viewport = nil,
			camera = nil,
			center = Vector3.zero,
			distance = 5,
			messageToken = 0,
		}
		table.insert(cards, card)
		cardById[info.id] = card

		purchase.MouseButton1Click:Connect(function()
			local state = getState(card)
			if state == "ready" then
				pendingPurchaseId = info.id
				network.fireServer(network.RemoteEvents.PurchaseShear, info.id)
			elseif state == "owned" then
				network.fireServer(network.RemoteEvents.EquipShear, info.id)
			elseif state == "equipped" and info.id ~= DEFAULT_SHEAR_ID then
				network.fireServer(network.RemoteEvents.EquipShear, DEFAULT_SHEAR_ID)
			elseif state == "poor" then
				flashMessage(card, REASON_TEXT.NoWool)
			elseif state == "locked" then
				flashMessage(card, REASON_TEXT.Locked)
			else
				shake(purchase)
			end
		end)

		frame.Parent = scrollFrame
	end

	updateCanvasSize()
end

-- Builds the ViewportFrame + model for one card. Only geometry is kept (no scripts, VFX or animation rigs).
local function buildPreview(card: Card)
	local template = shearTemplates:FindFirstChild(card.info.id)
	local holder = card.frame:FindFirstChild("ShearImage")
	if not template or not holder then
		return
	end

	local tool = template:Clone()
	local model = Instance.new("Model")
	model.Name = card.info.id

	for _, child in tool:GetChildren() do
		if child:IsA("BasePart") then
			for _, descendant in child:GetDescendants() do
				if not (descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint")) then
					descendant:Destroy()
				end
			end
			child.Anchored = true
			child.Parent = model
		end
	end
	tool:Destroy()

	model.PrimaryPart = model:FindFirstChild("Handle") :: BasePart?
	model:PivotTo(CFrame.new())

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -1, -1)

	local camera = Instance.new("Camera")
	camera.FieldOfView = UIData.PreviewFieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	model.Parent = viewport
	viewport.Parent = holder

	local boxCFrame, boxSize = model:GetBoundingBox()
	card.center = boxCFrame.Position
	card.distance = (boxSize.Magnitude * 0.5) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	card.viewport = viewport
	card.camera = camera

	camera.CFrame = CFrame.lookAt(card.center + Vector3.new(0, 0, card.distance), card.center)
end

local function buildPreviews()
	if previewsBuilt then
		return
	end
	previewsBuilt = true

	for _, card in cards do
		buildPreview(card)
	end
end

-- Spins every visible preview: orbits its camera round the shear (one connection for all cards).
local function onRender(deltaTime: number)
	spinAngle = (spinAngle + deltaTime * UIData.SpinSpeed) % (math.pi * 2)

	local pitch = UIData.PreviewPitch
	local flat = math.cos(pitch)
	local viewTop = scrollFrame.AbsolutePosition.Y
	local viewBottom = viewTop + scrollFrame.AbsoluteSize.Y

	for _, card in cards do
		local viewport, camera = card.viewport, card.camera
		if not viewport or not camera then
			continue
		end

		-- Scrolled out of view: nothing to draw, so don't touch it.
		local top = viewport.AbsolutePosition.Y
		if top > viewBottom or top + viewport.AbsoluteSize.Y < viewTop then
			continue
		end

		local offset = Vector3.new(math.sin(spinAngle) * flat, math.sin(pitch), math.cos(spinAngle) * flat) * card.distance
		camera.CFrame = CFrame.lookAt(card.center + offset, card.center)
	end
end

--// Open / close ------------------------------------------------------------------

-- Hides the Main HUD (buttons, Luck, ...) apart from HUD_KEEP; showHud puts back what was showing.
local function hideHud()
	local hud = playerGui:FindFirstChild("Main")
	if not hud then
		return
	end
	for _, child in hud:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and not HUD_KEEP[child.Name] then
			child.Visible = false
			table.insert(hiddenHud, child)
		end
	end
end

local function showHud()
	for _, child in hiddenHud do
		child.Visible = true
	end
	table.clear(hiddenHud)
end

-- Studs from the position to the hitbox's surface (0 when inside it).
local function getHitboxDistance(position: Vector3): number
	local offset = shopHitbox.CFrame:PointToObjectSpace(position)
	local half = shopHitbox.Size / 2
	local clamped = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return (offset - clamped).Magnitude
end

local window = windowsManager.register("ShearShop", {
	gui = shopGui,
	frame = mainFrame,
	onOpen = function()
		buildPreviews()
		refreshAll()
		hideHud()
		renderConnection = runService.RenderStepped:Connect(onRender)
	end,
	onClose = function()
		showHud()
		if renderConnection then
			renderConnection:Disconnect()
			renderConnection = nil
		end
	end,
})

-- Opens the shop, then closes it once the player walks away. Closed by hand, it stays shut until they leave and come back.
local function enterShop()
	nearShop = true
	window.open()

	while true do
		task.wait(DISTANCE_CHECK_SECONDS)
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart or getHitboxDistance(rootPart.Position) > CLOSE_DISTANCE then
			break
		end
	end

	nearShop = false
	if window.isOpen() then
		window.close()
	end
end

--// Setup ---------------------------------------------------------------------------

createCards()

wool.Changed:Connect(function()
	if window.isOpen() then
		refreshAll()
	end
end)

for _, attribute in { "ShearId", "OwnedShears", "SheepShearedCount" } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if window.isOpen() then
			refreshAll()
		end
	end)
end

checkShearUnlocks()
player:GetAttributeChangedSignal("SheepShearedCount"):Connect(checkShearUnlocks)

shopHitbox.Touched:Connect(function(hit: BasePart)
	if not nearShop and player.Character and hit:IsDescendantOf(player.Character) then
		task.spawn(enterShop)
	end
end)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.ShearPurchaseResult, function(id: string, success: boolean, reason: string?)
	local card = cardById[id]
	if not card then
		return
	end

	local wasPurchase = id == pendingPurchaseId
	if wasPurchase then
		pendingPurchaseId = nil
	end

	if success then
		refreshAll()
		if wasPurchase and purchaseSound then
			purchaseSound:Play()
		end
		local scale = card.frame:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = card.frame
		end
		scale.Scale = 1.06
		tweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	else
		flashMessage(card, REASON_TEXT[reason or ""] or "Can't buy")
	end
end)
