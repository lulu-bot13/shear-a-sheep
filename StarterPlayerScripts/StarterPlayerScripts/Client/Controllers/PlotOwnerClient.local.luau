--[[
	Shows the shack seller and sheep count only on this player's plot; every claimed plot's sign shows its owner's headshot and name.
]]--

--// Services
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Instances
local player = players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local SHACK_NAME = "UpgradePlotShack" -- matches UpgradeData.ShackName on the server
local SELLER_NAME = "PlayerCharacterTemplate" -- matches UpgradeData.SellerName on the server
local CENTER_NAME = "Center"
local SIGN_NAME = "PlayerBase"
local CAPACITY_NAME = "SheepCapacity" -- matches FarmData.CapacityGuiName on the server
local OWN_BASE_TEXT = "Your Base"
local WAIT_SECONDS = 10
local POP_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--// State
local headshots: { [number]: string } = {}

local function getHeadshot(userId: number): string?
	if not headshots[userId] then
		local success, result = pcall(players.GetUserThumbnailAsync, players, userId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		if success then
			headshots[userId] = result
		else
			warn(`PlotOwnerClient: couldn't load headshot for {userId}: {result}`)
		end
	end
	return headshots[userId]
end

-- The owner's UserId, or nil while the plot is unclaimed.
local function getOwnerId(plot: Instance): number?
	local owner = plot:GetAttribute("Owner")
	return if typeof(owner) == "number" and owner ~= 0 then owner else nil
end

local function isOwner(plot: Instance): boolean
	return getOwnerId(plot) == player.UserId
end

-- Calls onGui with the plot's Center gui now and with every copy that replaces it later (the server rebuilds plots on start).
local function watchCenterGui(plot: Instance, name: string, onGui: (LayerCollector) -> ())
	local function check(instance: Instance)
		local parent = instance.Parent
		if instance.Name == name and instance:IsA("LayerCollector") and parent and parent.Name == CENTER_NAME then
			onGui(instance)
		end
	end
	plot.DescendantAdded:Connect(check)
	for _, descendant in plot:GetDescendants() do
		check(descendant)
	end
end

-- Parented to nil (for this player only) when the plot isn't theirs, and put back when it is.
local function connectSeller(plot: Instance)
	local shack = plot:WaitForChild(SHACK_NAME, WAIT_SECONDS)
	local seller = shack and shack:WaitForChild(SELLER_NAME, WAIT_SECONDS)
	if not shack or not seller then
		return
	end

	local function update()
		seller.Parent = if isOwner(plot) then shack else nil
	end
	plot:GetAttributeChangedSignal("Owner"):Connect(update)
	update()
end

local function popIn(sign: Instance)
	local frame = sign:FindFirstChild("PlayerFrame")
	if not frame or not frame:IsA("GuiObject") then
		return
	end

	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = frame
	tweenService:Create(scale, POP_TWEEN, { Scale = 1 }):Play()
end

-- Shows "Your Base" on this player's plot and the owner's username on everyone else's; hidden while unclaimed.
local function connectSign(plot: Instance)
	local currentSign: LayerCollector? = nil

	local function update()
		local sign = currentSign
		if not sign then
			return
		end
		local ownerId = getOwnerId(plot)
		sign.Enabled = ownerId ~= nil
		if not ownerId then
			return
		end

		local label = sign:FindFirstChild("YourBase", true)
		if label and label:IsA("TextLabel") then
			local owner = players:GetPlayerByUserId(ownerId)
			label.Text = if ownerId == player.UserId then OWN_BASE_TEXT elseif owner then owner.Name else ""
		end
		popIn(sign)

		local headshot = getHeadshot(ownerId)
		local image = sign:FindFirstChild("PlayerImage", true)
		if image and image:IsA("ImageLabel") and getOwnerId(plot) == ownerId then -- the plot may change hands while it loads
			image.Image = headshot or ""
		end
	end

	watchCenterGui(plot, SIGN_NAME, function(sign)
		currentSign = sign
		sign.Enabled = false
		task.spawn(update)
	end)
	plot:GetAttributeChangedSignal("Owner"):Connect(update)
end

-- The current/max sheep label is only for the plot's owner.
local function connectCapacity(plot: Instance)
	local currentCapacity: LayerCollector? = nil

	local function update()
		if currentCapacity then
			currentCapacity.Enabled = isOwner(plot)
		end
	end

	watchCenterGui(plot, CAPACITY_NAME, function(capacity)
		currentCapacity = capacity
		update()
	end)
	plot:GetAttributeChangedSignal("Owner"):Connect(update)
end

local function connectPlot(plot: Instance)
	if plot:IsA("Folder") then
		task.spawn(connectSeller, plot)
		task.spawn(connectSign, plot)
		task.spawn(connectCapacity, plot)
	end
end

for _, plot in plotsFolder:GetChildren() do
	connectPlot(plot)
end
plotsFolder.ChildAdded:Connect(connectPlot)
