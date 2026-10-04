--!strict

--[[
	Backs the HireWorkers screen (opened by ProximityPrompts tagged "HireWorkers"):
		RequestHireWorkersState (client -> server)  "send me the current worker numbers"
		HireWorkersHire         (client -> server)  "hire me a worker" (checked here, including that the player is at a prompt)
		HireWorkersState        (server -> client)  hired / max / cost for drawing the screen

	Location: ServerScriptService.Server.HireWorkersServer
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local WorkerHandler = require(serverScriptService.Modules.Controllers.WorkerHandler)
local PenHandler = require(serverScriptService.Modules.Controllers.PenHandler)

--// Configs
local PEN_DISTANCE = 16 -- studs from a pen's PlayerPos that still counts as being at the pen
local PROMPT_TAG = "HireWorkers"
local EXTRA_DISTANCE = 10 -- studs past a prompt's activation range a press still counts
local STATE_COOLDOWN_SECONDS = 0.3
local HIRE_COOLDOWN_SECONDS = 0.5

local function getPromptPosition(prompt: ProximityPrompt): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

-- True when the player is standing at (or just past) any HireWorkers prompt.
local function isAtPrompt(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	for _, instance in collectionService:GetTagged(PROMPT_TAG) do
		if instance:IsA("ProximityPrompt") then
			local position = getPromptPosition(instance)
			if position and (root.Position - position).Magnitude <= instance.MaxActivationDistance + EXTRA_DISTANCE then
				return true
			end
		end
	end

	-- The pen menu also opens the screen (when a pen has no worker to give), so standing at a pen counts too.
	for _, pen in PenHandler.getPens(player) do
		local offset = root.Position - pen.playerPosition
		if Vector3.new(offset.X, 0, offset.Z).Magnitude <= PEN_DISTANCE then
			return true
		end
	end

	return false
end

local function pushState(player: Player, reason: string?)
	network.fireClient(network.RemoteEvents.HireWorkersState, player, WorkerHandler.getState(player), reason)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.RequestHireWorkersState, function(player: Player)
	if isAtPrompt(player) then
		pushState(player, nil)
	end
end, { network.Middleware.RateLimit(STATE_COOLDOWN_SECONDS) })

network.connectEvent(network.RemoteEvents.HireWorkersHire, function(player: Player)
	if not isAtPrompt(player) then
		return
	end

	local _, reason = WorkerHandler.buy(player)
	pushState(player, reason)
end, { network.Middleware.RateLimit(HIRE_COOLDOWN_SECONDS) })
