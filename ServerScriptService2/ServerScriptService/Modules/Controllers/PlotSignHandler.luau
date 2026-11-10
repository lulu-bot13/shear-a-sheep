--!strict

--[[
	Writes each plot's EntranceArch.Sign.OwnerGui: "<DisplayName>'s Farm" and "Rebirth N • Prestige N" for its owner,
	"Empty Farm" and a blank line while nobody owns it. Follows the owner's Rebirths / Prestiges attributes.

	Location: ServerScriptService.Modules.Controllers.PlotSignHandler
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local PlotHandler = require(script.Parent.PlotHandler)

--// Instances
local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")

--// Configs
local SIGN_PATH = { "EntranceArch", "Sign", "OwnerGui" }
local NAME_LABEL = "OwnerName"
local PROGRESS_LABEL = "OwnerProgress"
local EMPTY_TEXT = "Empty Farm"
local WATCHED_ATTRIBUTES = { "Rebirths", "Prestiges" } -- mirrored onto the player by PlayerDataHandler

--// State
local ownerConnections: { [Player]: { RBXScriptConnection } } = {}

local PlotSignHandler = {}

local function getLabels(plot: Instance): (TextLabel?, TextLabel?)
	local current: Instance? = plot
	for _, name in SIGN_PATH do
		current = current and current:FindFirstChild(name)
	end
	if not current then
		warn(`PlotSignHandler: {plot.Name} has no {table.concat(SIGN_PATH, ".")}; build it in the TemplatePlot in Studio.`)
		return nil, nil
	end
	local nameLabel = current:FindFirstChild(NAME_LABEL)
	local progressLabel = current:FindFirstChild(PROGRESS_LABEL)
	return if nameLabel and nameLabel:IsA("TextLabel") then nameLabel else nil,
		if progressLabel and progressLabel:IsA("TextLabel") then progressLabel else nil
end

local function getCount(player: Player, attribute: string): number
	local value = player:GetAttribute(attribute)
	return if type(value) == "number" then value else 0
end

local function writeSign(plot: Instance, owner: Player?)
	local nameLabel, progressLabel = getLabels(plot)
	if nameLabel then
		nameLabel.Text = if owner then `{owner.DisplayName}'s Farm` else EMPTY_TEXT
	end
	if progressLabel then
		progressLabel.Text = if owner
			then `Rebirth {getCount(owner, "Rebirths")} • Prestige {getCount(owner, "Prestiges")}`
			else ""
	end
end

local function disconnectOwner(player: Player)
	local connections = ownerConnections[player]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		ownerConnections[player] = nil
	end
end

local function onPlotAssigned(player: Player, plot: Instance)
	disconnectOwner(player)
	local connections = {}
	for _, attribute in WATCHED_ATTRIBUTES do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(function()
			writeSign(plot, player)
		end))
	end
	ownerConnections[player] = connections
	writeSign(plot, player)
end

local function onPlotReleased(player: Player, plot: Instance)
	disconnectOwner(player)
	writeSign(plot, nil)
end

function PlotSignHandler.Start()
	PlotHandler.PlotAssigned:Connect(onPlotAssigned)
	PlotHandler.PlotReleased:Connect(onPlotReleased)

	for _, plot in plotsFolder:GetChildren() do
		if not plot:IsA("Folder") then
			continue
		end
		local ownerId = plot:GetAttribute("Owner")
		local owner = if type(ownerId) == "number" and ownerId ~= 0 then players:GetPlayerByUserId(ownerId) else nil
		if owner then
			onPlotAssigned(owner, plot)
		else
			writeSign(plot, nil)
		end
	end
end

return PlotSignHandler
