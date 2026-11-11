--!strict

--[[
	While this player's own RobuxConveyor is locked, shows its RobuxTag and a prompt that buys the RobuxConveyor game pass.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.RobuxConveyorClient
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
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local PASS = MonetizationData.Items.RobuxConveyor
local MODEL_NAME = "RobuxConveyor"
local BELT_NAME = "Belt"
local TAG_NAME = "RobuxTag"
local UNLOCKED_ATTRIBUTE = "Unlocked" -- set by SheepBeltHandler
local TAG_TEXT = `{1 + (PASS.multiplier or 2)}x SHEEP`
local PROMPT_NAME = "UnlockPrompt"
local PROMPT_ACTION = "Unlock"
local PROMPT_DISTANCE = 15

--// State
local watched: { [Instance]: boolean } = {}

local function isOwnPlot(plot: Instance): boolean
	return plot:GetAttribute("Owner") == player.UserId
end

-- Locked conveyors on this player's plot get the tag and a buy prompt; every other one (or an unlocked one) gets neither.
local function update(model: Instance)
	local plot = model.Parent
	local belt = model:FindFirstChild(BELT_NAME)
	if not plot or not belt or not belt:IsA("BasePart") then
		return
	end
	local locked = PASS.id ~= 0 and isOwnPlot(plot) and model:GetAttribute(UNLOCKED_ATTRIBUTE) ~= true

	local tag = belt:FindFirstChild(TAG_NAME)
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = locked
		local label = tag:FindFirstChildWhichIsA("TextLabel")
		if label then
			label.Text = TAG_TEXT
		end
	end

	local prompt = belt:FindFirstChild(PROMPT_NAME)
	if locked and not prompt then
		local newPrompt = Instance.new("ProximityPrompt")
		newPrompt.Name = PROMPT_NAME
		newPrompt.ActionText = PROMPT_ACTION
		newPrompt.ObjectText = PASS.displayName
		newPrompt.MaxActivationDistance = PROMPT_DISTANCE
		newPrompt.RequiresLineOfSight = false
		newPrompt.Triggered:Connect(function()
			purchaseEffect.play()
			marketplaceService:PromptGamePassPurchase(player, PASS.id)
		end)
		newPrompt.Parent = belt
	elseif not locked and prompt then
		prompt:Destroy()
	end
end

local function watchModel(model: Instance)
	if watched[model] then
		return
	end
	watched[model] = true
	model:GetAttributeChangedSignal(UNLOCKED_ATTRIBUTE):Connect(function()
		update(model)
	end)
	model.Destroying:Once(function()
		watched[model] = nil
	end)
	update(model)
end

-- Plots are rebuilt from the template on server start, so each plot's conveyor is picked up whenever it appears.
local function watchPlot(plot: Instance)
	local function check(child: Instance)
		if child.Name == MODEL_NAME and child:IsA("Model") then
			watchModel(child)
		end
	end
	plot.ChildAdded:Connect(check)
	for _, child in plot:GetChildren() do
		check(child)
	end
	plot:GetAttributeChangedSignal("Owner"):Connect(function()
		local model = plot:FindFirstChild(MODEL_NAME)
		if model then
			update(model)
		end
	end)
end

plotsFolder.ChildAdded:Connect(watchPlot)
for _, plot in plotsFolder:GetChildren() do
	watchPlot(plot)
end
