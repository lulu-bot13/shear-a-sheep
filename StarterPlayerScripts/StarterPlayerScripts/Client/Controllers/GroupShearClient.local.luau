--[[
	Every plot's GroupShear: spins its Shear model and, walked into, opens StarterGui.JoinGroup to claim the reward shear.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.GroupShearClient
]]--

--// Services
local groupService = game:GetService("GroupService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local GroupData = require(replicatedStorage.Shared.Constants.GroupData)
local alerts = require(script.Parent.Parent.Modules.Alerts)
local announcements = require(script.Parent.Parent.Modules.Announcements)
local purchaseEffect = require(script.Parent.Parent.Modules.PurchaseEffect)
local windowsManager = require(script.Parent.Parent.Modules.WindowsManager)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
local joinGui = playerGui:WaitForChild("JoinGroup") :: ScreenGui
local mainFrame = joinGui:WaitForChild("Main") :: Frame
local claimButton = mainFrame:WaitForChild("Claim") :: TextButton
local exitButton = mainFrame:WaitForChild("ExitButton") :: GuiButton
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui

--// Configs
local GROUP_SHEAR_NAME = "GroupShear"
local HITBOX_NAME = "Hitbox"
local SHEAR_MODEL_NAME = "Shear"
local SPIN_SPEED = math.rad(90) -- radians per second around the vertical axis
local BOB_HEIGHT = 0.4 -- studs up and down
local BOB_SPEED = 2 -- radians per second
local CLOSE_DISTANCE = 6 -- studs outside the hitbox before the window closes itself
local DISTANCE_CHECK_SECONDS = 0.25
local CLAIM_TEXT = claimButton.Text
local CLAIMED_TEXT = "CLAIMED"
local CLAIM_AUTO_COLOR = claimButton.AutoButtonColor
-- The Studio look is the locked one (not in the group, or already claimed).
local LOCKED_BACKGROUND = claimButton.BackgroundColor3
local LOCKED_TEXT_COLOR = claimButton.TextColor3
local READY_BACKGROUND = Color3.fromRGB(76, 205, 80)
local READY_TEXT_COLOR = Color3.new(1, 1, 1)
local JOINED_STATUSES = { [Enum.GroupMembershipStatus.Joined] = true, [Enum.GroupMembershipStatus.AlreadyMember] = true }
local REASON_TEXT = {
	Owned = "Already claimed!",
	NotInGroup = "Join the group to claim!",
	Failed = "Couldn't claim, try again",
}

--// State
local groupId = GroupData.getGroupId()
local spinning: { [BasePart]: CFrame } = {} -- each Shear's handle and its resting CFrame
local connectedHitboxes: { [BasePart]: boolean } = {}
local inGroup = false
local claimPending = false
local nearHitbox = false

--// Claim button --------------------------------------------------------------------------

local function ownsReward(): boolean
	local owned = player:GetAttribute("OwnedShears")
	return type(owned) == "string" and table.find(string.split(owned, ","), GroupData.RewardShearId) ~= nil
end

-- Claimed, the button goes grey and stops taking clicks (no hover / press tint either).
local function refreshClaim()
	local owned = ownsReward()
	local ready = inGroup and not owned
	claimButton.Text = if owned then CLAIMED_TEXT else CLAIM_TEXT
	claimButton.Interactable = not owned
	claimButton.Active = not owned
	claimButton.AutoButtonColor = if owned then false else CLAIM_AUTO_COLOR
	claimButton.BackgroundColor3 = if ready then READY_BACKGROUND else LOCKED_BACKGROUND
	claimButton.TextColor3 = if ready then READY_TEXT_COLOR else LOCKED_TEXT_COLOR
end

local function checkMembership()
	if groupId == 0 then
		return
	end
	local success, result = pcall(player.IsInGroupAsync, player, groupId)
	inGroup = success and result == true
	refreshClaim()
end

local window = windowsManager.register("JoinGroup", {
	gui = joinGui,
	frame = mainFrame,
	closeButton = exitButton,
	onOpen = function()
		refreshClaim()
		task.spawn(checkMembership)
	end,
})

-- Not in the group, a press asks them to join (and readies the button if they do); in it, it claims.
claimButton.Activated:Connect(function()
	if claimPending or ownsReward() then
		return
	end
	if not inGroup then
		if groupId == 0 then
			return
		end
		local success, status = pcall(groupService.PromptJoinAsync, groupService, groupId)
		if success and JOINED_STATUSES[status] then
			inGroup = true
			refreshClaim()
		end
		return
	end

	claimPending = true
	network.fireServer(network.RemoteEvents.ClaimGroupShear)
end)

--// Hitboxes -------------------------------------------------------------------------------

-- Studs from the position to the hitbox's surface (0 when inside it).
local function getHitboxDistance(hitbox: BasePart, position: Vector3): number
	local offset = hitbox.CFrame:PointToObjectSpace(position)
	local half = hitbox.Size / 2
	local clamped = Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z)
	)
	return (offset - clamped).Magnitude
end

-- Opens the window, then closes it once the player walks away. Closed by hand, it stays shut until they leave and come back.
local function enterHitbox(hitbox: BasePart)
	nearHitbox = true
	window.open()

	while true do
		task.wait(DISTANCE_CHECK_SECONDS)
		local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart or not hitbox.Parent or getHitboxDistance(hitbox, rootPart.Position) > CLOSE_DISTANCE then
			break
		end
	end

	nearHitbox = false
	if window.isOpen() then
		window.close()
	end
end

local function trackHitbox(hitbox: BasePart)
	if connectedHitboxes[hitbox] then
		return
	end
	connectedHitboxes[hitbox] = true
	hitbox.Touched:Connect(function(hit: BasePart)
		-- The tutorial turns other guis off every tick, so the window waits until it's over.
		if not nearHitbox and not tutorialGui.Enabled and player.Character and hit:IsDescendantOf(player.Character) then
			task.spawn(enterHitbox, hitbox)
		end
	end)
	hitbox.Destroying:Once(function()
		connectedHitboxes[hitbox] = nil
	end)
end

local function trackHandle(handle: BasePart)
	if spinning[handle] then
		return
	end
	spinning[handle] = handle.CFrame
	handle.Destroying:Once(function()
		spinning[handle] = nil
	end)
end

-- Plots are rebuilt on the server and stream in and out, so every GroupShear part is picked up as it arrives.
local function onDescendant(descendant: Instance)
	if not descendant:IsA("BasePart") then
		return
	end
	local parent = descendant.Parent
	if descendant.Name == HITBOX_NAME and parent and parent.Name == GROUP_SHEAR_NAME then
		trackHitbox(descendant)
	elseif parent and parent.Name == SHEAR_MODEL_NAME and parent.Parent and parent.Parent.Name == GROUP_SHEAR_NAME then
		trackHandle(descendant)
	end
end

--// Setup ----------------------------------------------------------------------------------

plotsFolder.DescendantAdded:Connect(onDescendant)
for _, descendant in plotsFolder:GetDescendants() do
	onDescendant(descendant)
end

runService.RenderStepped:Connect(function()
	local now = os.clock()
	local spin = CFrame.Angles(0, (now * SPIN_SPEED) % (math.pi * 2), 0)
	local bob = Vector3.new(0, math.sin(now * BOB_SPEED) * BOB_HEIGHT, 0)
	for handle, rest in spinning do
		if handle.Parent then
			handle.CFrame = CFrame.new(rest.Position + bob) * spin * rest.Rotation
		else
			spinning[handle] = nil -- streamed out; picked up again with a fresh CFrame when it streams back in
		end
	end
end)

player:GetAttributeChangedSignal("OwnedShears"):Connect(refreshClaim)

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.GroupShearResult, function(success: boolean, reason: string?)
	claimPending = false
	if success then
		purchaseEffect.celebrate()
		announcements.show("ShearAlert", "ROYAL SHEARS CLAIMED!")
		window.close()
		return
	end
	if reason == "NotInGroup" then
		inGroup = false
	end
	refreshClaim()
	alerts.show(REASON_TEXT[reason or ""] or REASON_TEXT.Failed, "error")
end)
