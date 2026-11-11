--!strict

--[[
	The Auto Shears purchase button on the HUD (the ImageButton Main.AutoShear): spinning shine, rainbow title and a 5 minute countdown.
	Shown after the tutorial; prompts the pass and hides once it's owned or the countdown runs out for this session.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.AutoShearOfferClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui

--// Configs
local BUTTON_NAME = "AutoShear" -- the ImageButton in StarterGui.Main (the TextButton of the same name is ShearClient's toggle)
local GUI_WAIT_SECONDS = 10
local PASS_ID = MonetizationData.Items.AutoShears.id
local OWNED_ATTRIBUTE = "PassAutoShears" -- GamePassService sets Pass<key> once owned; the free trial doesn't
local OFFER_SECONDS = 5 * 60 -- from the end of the tutorial; the deadline survives respawns
local TUTORIAL_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local SHINE_TAG = "RotatingShine" -- ShineRotate spins it
local RAINBOW_SECONDS = 3 -- one full trip round the colour wheel
local RAINBOW_SATURATION = 0.75

--// State
local offerEndsAt: number? = nil -- set once the tutorial is over
local button: ImageButton? = nil
local title: TextLabel? = nil
local timer: TextLabel? = nil

local function ownsPass(): boolean
	return player:GetAttribute(OWNED_ATTRIBUTE) == true
end

local function secondsLeft(): number
	return if offerEndsAt then math.max(math.ceil(offerEndsAt - os.clock()), 0) else OFFER_SECONDS
end

local function refresh()
	if not button then
		return
	end
	local left = secondsLeft()
	button.Visible = PASS_ID ~= 0 and offerEndsAt ~= nil and not ownsPass() and left > 0
	if timer then
		timer.Text = string.format("%d:%02d", left // 60, left % 60)
	end
end

local function findButton(main: Instance): ImageButton?
	local deadline = os.clock() + GUI_WAIT_SECONDS
	repeat
		for _, child in main:GetChildren() do
			if child.Name == BUTTON_NAME and child:IsA("ImageButton") then
				return child
			end
		end
		task.wait(0.2)
	until os.clock() > deadline or not main.Parent
	return nil
end

-- Main resets on spawn, so the button is found again in each new copy.
local function bind(main: Instance)
	if main.Name ~= "Main" or not main:IsA("ScreenGui") then
		return
	end
	local found = findButton(main)
	if not found or found == button then
		if not found then
			warn(`AutoShearOfferClient: no ImageButton Main.{BUTTON_NAME}; build it in Studio.`)
		end
		return
	end

	button = found
	local titleLabel = found:FindFirstChild("Title")
	title = if titleLabel and titleLabel:IsA("TextLabel") then titleLabel else nil
	local timerLabel = found:FindFirstChild("Timer")
	timer = if timerLabel and timerLabel:IsA("TextLabel") then timerLabel else nil
	local shine = found:FindFirstChild("Shine")
	if shine then
		collectionService:AddTag(shine, SHINE_TAG)
	end

	found.Activated:Connect(function()
		if PASS_ID == 0 or ownsPass() then
			return
		end
		purchaseEffect.play()
		marketplaceService:PromptGamePassPurchase(player, PASS_ID)
	end)
	refresh()
end

player:GetAttributeChangedSignal(OWNED_ATTRIBUTE):Connect(refresh)

playerGui.ChildAdded:Connect(bind)
local existing = playerGui:FindFirstChild("Main")
if existing then
	task.spawn(bind, existing)
end

-- The countdown starts when the tutorial ends and ticks once a second until the offer is gone.
task.spawn(function()
	while tutorialGui:GetAttribute(TUTORIAL_DONE_ATTRIBUTE) ~= true do
		tutorialGui:GetAttributeChangedSignal(TUTORIAL_DONE_ATTRIBUTE):Wait()
	end
	offerEndsAt = os.clock() + OFFER_SECONDS
	while secondsLeft() > 0 do
		refresh()
		task.wait(1)
	end
	refresh()
end)

-- The title cycles through the rainbow while the button is on screen.
runService.RenderStepped:Connect(function()
	if title and button and button.Visible and button.Parent then
		title.TextColor3 = Color3.fromHSV((os.clock() / RAINBOW_SECONDS) % 1, RAINBOW_SATURATION, 1)
	end
end)
