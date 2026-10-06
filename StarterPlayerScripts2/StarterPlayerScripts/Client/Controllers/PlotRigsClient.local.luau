--!strict

--[[
	Dresses the rigs in each plot's HireWorkersShack.PlayerCharacters as the local player. Only the owner of
	a plot sees its rigs: on every other plot the model is taken out of the world on this client.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PlotRigsClient
]]--

--// Services
local players = game:GetService("Players")

--// Instances
local player = players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// State
local description: HumanoidDescription? = nil
local hiddenRigs: { [Instance]: Instance } = {} -- rig model -> the HireWorkersShack it belongs in

local function dress(rigs: Instance)
	if not description then
		return
	end

	for _, humanoid in rigs:GetDescendants() do
		if humanoid:IsA("Humanoid") then
			task.spawn(function()
				local success, err = pcall(function()
					humanoid:ApplyDescription(description :: HumanoidDescription)
				end)
				if not success then
					warn(`PlotRigsClient: could not dress {humanoid:GetFullName()}: {err}`)
				end
			end)
		end
	end
end

local function refreshPlot(plot: Instance)
	local shack = plot:FindFirstChild("HireWorkersShack")
	if not shack then
		return
	end

	local owned = plot:GetAttribute("Owner") == player.UserId
	local rigs = shack:FindFirstChild("PlayerCharacters") or hiddenRigs[shack]
	if not rigs then
		return
	end

	if owned then
		if rigs.Parent ~= shack then
			rigs.Parent = shack
			hiddenRigs[shack] = nil
		end
		dress(rigs)
	elseif rigs.Parent == shack then
		hiddenRigs[shack] = rigs
		rigs.Parent = nil
	end
end

local function watchPlot(plot: Instance)
	plot:GetAttributeChangedSignal("Owner"):Connect(function()
		refreshPlot(plot)
	end)
	refreshPlot(plot)
end

--// Setup ---------------------------------------------------------------------------

-- Hide everything straight away so other people's rigs never show while the avatar loads.
for _, plot in plotsFolder:GetChildren() do
	local shack = plot:FindFirstChild("HireWorkersShack")
	local rigs = shack and shack:FindFirstChild("PlayerCharacters")
	if shack and rigs and plot:GetAttribute("Owner") ~= player.UserId then
		hiddenRigs[shack] = rigs
		rigs.Parent = nil
	end
end

local success, result = pcall(function()
	return players:GetHumanoidDescriptionFromUserId(player.UserId)
end)
if success then
	description = result
else
	warn(`PlotRigsClient: could not load {player.Name}'s avatar: {result}`)
end

for _, plot in plotsFolder:GetChildren() do
	watchPlot(plot)
end
plotsFolder.ChildAdded:Connect(watchPlot)
