--[[
	One-time Shepherd's Crook tutorial, the first time the crook is held after the main tutorial: pick up a sheep, put it on a podium,
	then why it helps. Uses the Tutorial gui's TutorialFrame and is saved through TutorialHandler (CrookTutorialDone).
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local userInputService = game:GetService("UserInputService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local tutorialFrame = tutorialGui:WaitForChild("TutorialFrame") :: GuiObject
local tutorialText = tutorialFrame:WaitForChild("TutorialText") :: TextLabel
local tutorialProgression = tutorialFrame:WaitForChild("TutorialProgression") :: TextLabel
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local CROOK_NAME = "ShepherdsCrook"
local PODIUM_TAG = "Podium" -- on each podium's ProximityPrompt
local OCCUPIED_ATTRIBUTE = "Occupied" -- set on the prompt by SheepCarryHandler
local CARRY_ATTRIBUTE = "CarryingSheep" -- "Pen" or "Podium" while a sheep is carried, set by SheepCarryHandler
local DONE_KEY = "CrookTutorialDone" -- mirrored from the save by PlayerDataHandler, 1 once shown
local MAIN_DONE_ATTRIBUTE = "MainTutorialDone" -- set on the Tutorial gui by TutorialClient once it's finished with it
local ACTIVE_ATTRIBUTE = "CrookTutorialActive" -- on the Tutorial gui while this runs, so DailyRewardClient doesn't open over it
local SHEAR_ACTIVE_ATTRIBUTE = "ShearTutorialActive" -- set on the Tutorial gui by ShearTutorialClient while it runs
local TICK_SECONDS = 0.1
local DISPLAY_ORDER = 90 -- matches TutorialClient
local PLACE_GRACE_SECONDS = 0.5 -- after a carry ends, how long to wait for the podium's Occupied to arrive before calling it a release
local EXPLAIN_SECONDS = 5 -- the last step closes after this long, or on a click
local EXPLAIN_MIN_SECONDS = 0.6 -- clicks sooner than this after the last step appears don't close it
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 230, 90)
local STEP_COUNT = 3

--// State
local podiumHighlights: { [Instance]: Highlight } = {}

--// Helpers ---------------------------------------------------------------------------

local function isHoldingCrook(): boolean
	local tool = player.Character and player.Character:FindFirstChild(CROOK_NAME)
	return tool ~= nil and tool:IsA("Tool")
end

local function getCarrySource(): string?
	local source = player:GetAttribute(CARRY_ATTRIBUTE)
	return if type(source) == "string" then source else nil
end

local function getClickWord(): string
	return if userInputService.TouchEnabled and not userInputService.KeyboardEnabled then "Tap" else "Click"
end

-- The podium prompts on the player's own plot.
local function getOwnPodiums(): { ProximityPrompt }
	local plotName = player:GetAttribute("PlotName")
	local plot = if type(plotName) == "string" then plotsFolder:FindFirstChild(plotName) else nil
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

local function countOccupied(): number
	local count = 0
	for _, prompt in getOwnPodiums() do
		if prompt:GetAttribute(OCCUPIED_ATTRIBUTE) == true then
			count += 1
		end
	end
	return count
end

-- Every podium on the player's plot as a whole (the prompt sits on its top part, inside the podium model).
local function getPodiumsToShow(): { Instance }
	local found: { Instance } = {}
	for _, prompt in getOwnPodiums() do
		local top = prompt.Parent
		local podium = top and top.Parent
		local target = if podium and podium:IsA("Model") then podium else top
		if target then
			table.insert(found, target)
		end
	end
	return found
end

local function setShown(shown: boolean)
	tutorialGui.Enabled = shown
	tutorialFrame.Visible = shown
end

local function setStep(step: number, text: string)
	tutorialProgression.Text = `{step}/{STEP_COUNT}`
	tutorialText.Text = text
	setShown(true)
end

-- Outlines every podium (shown = true) or none.
local function setPodiumHighlights(shown: boolean)
	local keep: { [Instance]: boolean } = {}
	if shown then
		for _, podium in getPodiumsToShow() do
			keep[podium] = true
			if not podiumHighlights[podium] then
				local highlight = Instance.new("Highlight")
				highlight.Name = "CrookTutorialPodium"
				highlight.FillColor = HIGHLIGHT_COLOR
				highlight.OutlineColor = HIGHLIGHT_COLOR
				highlight.FillTransparency = 0.7
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Adornee = podium
				highlight.Parent = workspace
				podiumHighlights[podium] = highlight
			end
		end
	end
	for podium, highlight in podiumHighlights do
		if not keep[podium] then
			highlight:Destroy()
			podiumHighlights[podium] = nil
		end
	end
end

--// Steps -------------------------------------------------------------------------------

-- Steps 1 and 2: pick a sheep up, then put it on a podium; a sheep let go in the pen (or dropped on death) goes back to step 1.
local function runPlacing()
	local carrying = false
	local occupiedBefore = 0
	local carryEndedAt: number? = nil

	while true do
		local source = getCarrySource()
		if not carrying then
			if source == "Pen" then
				carrying, occupiedBefore, carryEndedAt = true, countOccupied(), nil
			elseif isHoldingCrook() then
				setStep(1, `Select a sheep: {getClickWord()} one in your pen to pick it up`)
			else
				setShown(false) -- put away before picking one up; wait for it to come back out
			end
		end

		if carrying then
			if source == "Podium" then
				return -- swapped onto a full podium: the old podium sheep was handed back
			elseif source == nil then
				if countOccupied() > occupiedBefore then
					return
				end
				carryEndedAt = carryEndedAt or os.clock()
				if os.clock() - (carryEndedAt :: number) >= PLACE_GRACE_SECONDS then
					carrying = false
					setPodiumHighlights(false)
					continue
				end
			else
				setStep(2, "Place the sheep on one of the glowing podiums")
				setPodiumHighlights(true)
			end
		end
		task.wait(TICK_SECONDS)
	end
end

-- Step 3: why podiums matter; closes after EXPLAIN_SECONDS or on a click.
local function runExplain()
	setPodiumHighlights(true)
	setStep(3, "Placing a sheep on a podium gives you higher base stats!")

	local shownAt = os.clock()
	local closed = false
	local connection = userInputService.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if os.clock() - shownAt >= EXPLAIN_MIN_SECONDS and (inputType == Enum.UserInputType.MouseButton1
			or inputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonR2)
		then
			closed = true
		end
	end)
	while not closed and os.clock() - shownAt < EXPLAIN_SECONDS do
		task.wait(TICK_SECONDS)
	end
	connection:Disconnect()
end

--// Lifecycle ---------------------------------------------------------------------------

network.waitUntilReadyAsync()

-- The save has loaded once its numbers are mirrored onto the player.
while player:GetAttribute(DONE_KEY) == nil do
	player:GetAttributeChangedSignal(DONE_KEY):Wait()
end
if player:GetAttribute(DONE_KEY) == 1 then
	return
end

while not tutorialGui:GetAttribute(MAIN_DONE_ATTRIBUTE) do
	tutorialGui:GetAttributeChangedSignal(MAIN_DONE_ATTRIBUTE):Wait()
end
while not isHoldingCrook() or tutorialGui:GetAttribute(SHEAR_ACTIVE_ATTRIBUTE) == true do
	task.wait(TICK_SECONDS)
end

tutorialGui.DisplayOrder = DISPLAY_ORDER
tutorialGui:SetAttribute(ACTIVE_ATTRIBUTE, true)
runPlacing()
runExplain()
setShown(false)
tutorialGui:SetAttribute(ACTIVE_ATTRIBUTE, false)
setPodiumHighlights(false)
network.fireServer(network.RemoteEvents.CrookTutorialDone)
