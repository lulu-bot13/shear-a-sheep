--!strict

--[[
	The Starter Pack button (Main.StarterPack): a 5 minute countdown in its Timer from the end of the tutorial, then it hides for the session (also once bought).
	Only images named "Shine" spin (RotatingShine); pressing it prompts the pass while OfferHandler's 72 h / 3 session window is open.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.StarterPackClient
]]--

--// Services
local marketplaceService = game:GetService("MarketplaceService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui

--// Configs
local PACK_NAME = "StarterPack"
local SHINE_TAG = "RotatingShine" -- ShineRotate spins it
local OFFER_SECONDS = 5 * 60 -- the button's countdown, from the end of the tutorial; the deadline survives respawns
local TUTORIAL_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient
local WINDOW_HOURS = 72 -- matches OfferHandler.STARTER_PACK_HOURS: sold this long after FirstJoinAt
local SESSIONS = 3 -- matches OfferHandler.STARTER_PACK_SESSIONS
local TIMER_NAMES = { Timer = true, Countdown = true }
local BUY_NAMES = { Buy = true, BuyButton = true, Purchase = true, PurchaseButton = true }
local PASS = MonetizationData.Items.StarterPack
local OWNED_ATTRIBUTE = "PassStarterPack" -- GamePassService sets Pass<key> once owned

type Pack = {
	root: GuiObject,
	timers: { TextLabel },
}

--// State
local packs: { [Instance]: Pack } = {}
local offerEndsAt: number? = nil -- set once the tutorial is over

local function getNumber(name: string): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

-- The server would still sell it: not bought, within 72 h of the first join and the first 3 sessions.
local function canBuy(): boolean
	local firstJoinAt = getNumber("FirstJoinAt")
	return PASS.id ~= 0
		and firstJoinAt > 0
		and getNumber("StarterPackBought") ~= 1
		and player:GetAttribute(OWNED_ATTRIBUTE) ~= true
		and getNumber("SessionCount") <= SESSIONS
		and workspace:GetServerTimeNow() < firstJoinAt + WINDOW_HOURS * 3600
end

local function getSecondsLeft(): number
	return if offerEndsAt then math.max(math.ceil(offerEndsAt - os.clock()), 0) else OFFER_SECONDS
end

local function render(pack: Pack)
	local left = getSecondsLeft()
	for _, timer in pack.timers do
		timer.Text = string.format("%d:%02d", left // 60, left % 60)
	end
	pack.root.Visible = offerEndsAt ~= nil and left > 0 and canBuy()
end

local function renderAll()
	for _, pack in packs do
		render(pack)
	end
end

local function prompt()
	if not canBuy() or getSecondsLeft() <= 0 then
		return
	end
	purchaseEffect.play()
	marketplaceService:PromptGamePassPurchase(player, PASS.id)
end

-- Only the shine turns: a RotatingShine tag on anything else in the pack (its icon) is taken off.
local function fixShines(root: Instance)
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("ImageLabel") then
			continue
		end
		local isShine = string.find(string.lower(descendant.Name), "shine", 1, true) ~= nil
		if isShine and not descendant:HasTag(SHINE_TAG) then
			descendant:AddTag(SHINE_TAG)
		elseif not isShine and descendant:HasTag(SHINE_TAG) then
			descendant:RemoveTag(SHINE_TAG)
			descendant.Rotation = 0
		end
	end
end

-- Main resets on spawn, so each new copy's button is bound as it arrives.
local function bind(root: Instance)
	if packs[root] or root.Name ~= PACK_NAME or not root:IsA("GuiObject") then
		return
	end
	local pack: Pack = { root = root, timers = {} }
	packs[root] = pack

	local buttonBound = false
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") and TIMER_NAMES[descendant.Name] then
			table.insert(pack.timers, descendant)
		elseif descendant:IsA("GuiButton") and BUY_NAMES[descendant.Name] then
			descendant.Activated:Connect(prompt)
			buttonBound = true
		end
	end
	if not buttonBound and root:IsA("GuiButton") then
		root.Activated:Connect(prompt)
	end
	fixShines(root)

	root.Destroying:Once(function()
		packs[root] = nil
	end)
	render(pack)
end

--// Setup -------------------------------------------------------------------------------

for _, descendant in playerGui:GetDescendants() do
	if descendant.Name == PACK_NAME then
		bind(descendant)
	end
end
playerGui.DescendantAdded:Connect(function(descendant: Instance)
	if descendant.Name == PACK_NAME then
		task.defer(bind, descendant) -- its children arrive with it
	end
end)

for _, attribute in { "FirstJoinAt", "StarterPackBought", "SessionCount", OWNED_ATTRIBUTE } do
	player:GetAttributeChangedSignal(attribute):Connect(renderAll)
end

-- The countdown starts when the tutorial ends and ticks once a second until it runs out.
task.spawn(function()
	while tutorialGui:GetAttribute(TUTORIAL_DONE_ATTRIBUTE) ~= true do
		renderAll() -- hidden until then
		tutorialGui:GetAttributeChangedSignal(TUTORIAL_DONE_ATTRIBUTE):Wait()
	end
	offerEndsAt = os.clock() + OFFER_SECONDS
	while getSecondsLeft() > 0 do
		renderAll()
		task.wait(1)
	end
	renderAll()
end)
