--!strict

--[[
	Assigns each joining player to an open plot and marks them as its owner

	Location: ServerScriptService.Modules.Controllers.PlotHandler
]]--

--// Services
local players = game:GetService("Players")

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local NO_OWNER = 0

local PlotHandler = {}

local function getOwnerId(plot: Instance): number
	local owner = plot:GetAttribute("Owner")
	return if typeof(owner) == "number" then owner else 0
end

local function isBasePlot(plot: Instance): boolean
	return plot:IsA("Folder") and not plot:GetAttribute("Purchased")
end

-- A plot is open when it is a base plot with no owner yet.
local function findOpenPlot(): Folder?
	for _, plot in plotsFolder:GetChildren() do
		if isBasePlot(plot) and getOwnerId(plot) == NO_OWNER then
			return plot :: Folder
		end
	end
	return nil
end

local function getOwnedPlot(player: Player): Folder?
	for _, plot in plotsFolder:GetChildren() do
		if isBasePlot(plot) and getOwnerId(plot) == player.UserId then
			return plot :: Folder
		end
	end
	return nil
end

-- Dresses the plot's HireWorkersShack rigs as the owner. ApplyDescription only works on the server;
-- PlotRigsClient hides the rigs from everyone but the owner.
local function dressRigs(plot: Folder, player: Player)
	local shack = plot:FindFirstChild("HireWorkersShack")
	local rigs = shack and shack:FindFirstChild("PlayerCharacters")
	if not rigs then
		return
	end

	local success, description = pcall(function()
		return players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not success then
		warn(`PlotHandler: could not load {player.Name}'s avatar: {description}`)
		return
	end

	for _, humanoid in rigs:GetDescendants() do
		if humanoid:IsA("Humanoid") then
			task.spawn(function()
				local applied, err = pcall(function()
					humanoid:ApplyDescription(description)
				end)
				if not applied then
					warn(`PlotHandler: could not dress {humanoid:GetFullName()}: {err}`)
				end
			end)
		end
	end
end

local function assignPlot(player: Player)
	if getOwnedPlot(player) then
		return
	end

	local plot = findOpenPlot()
	if not plot then
		warn(`PlotHandler: no open plot for {player.Name}.`)
		return
	end

	plot:SetAttribute("Owner", player.UserId)
	player:SetAttribute("PlotName", plot.Name)
	task.spawn(dressRigs, plot, player)

	-- Position player to plot
	local character = player.Character or player.CharacterAdded:Wait()
	local plotSpawnArea = plot and plot:FindFirstChild("SpawnArea") :: BasePart
	if plotSpawnArea then
		character:PivotTo(plotSpawnArea.CFrame * CFrame.new(0, 2, 0))
	end
end

-- Frees the player's base plot and every pen they bought.
local function releasePlots(player: Player)
	for _, plot in plotsFolder:GetChildren() do
		if getOwnerId(plot) == player.UserId then
			plot:SetAttribute("Owner", NO_OWNER)
		end
	end
end

--[[
	Returns the plot Folder the player owns, or nil if they haven't been given one (yet).
	Every plot-bound system (sheep, pens, buttons) should look the plot up through this.
]]--
function PlotHandler.getPlayerPlot(player: Player): Folder?
	return getOwnedPlot(player)
end

function PlotHandler.Setup()
	players.PlayerAdded:Connect(assignPlot)
	players.PlayerRemoving:Connect(releasePlots)

	-- Players who joined before Setup ran.
	for _, player in players:GetPlayers() do
		assignPlot(player)
	end
end

return PlotHandler
