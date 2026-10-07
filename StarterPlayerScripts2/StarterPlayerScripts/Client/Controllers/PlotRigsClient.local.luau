--!strict

--[[
	Only the owner of a plot sees the rigs in its HireWorkersShack.PlayerCharacters: on every other plot the
	model is taken out of the world on this client. (The server dresses them, see PlotHandler.)

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.PlotRigsClient
]]--

--// Services
local players = game:GetService("Players")

--// Instances
local player = players.LocalPlayer
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// State
local hiddenRigs: { [Instance]: Instance } = {} -- rig model -> the HireWorkersShack it belongs in

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

for _, plot in plotsFolder:GetChildren() do
	watchPlot(plot)
end
plotsFolder.ChildAdded:Connect(watchPlot)
