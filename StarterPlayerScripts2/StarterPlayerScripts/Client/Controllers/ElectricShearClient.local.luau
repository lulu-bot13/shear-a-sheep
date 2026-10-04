--[[
	Snip effect of the electric shears for OTHER players.

	The idle crackle and the arc are plain ParticleEmitter / Beam / PointLight objects on the
	tool, so they need no script. The burst on each snip is triggered here: the server bumps the
	tool's "Snips" attribute on every accepted hit, and every client watching a tool tagged
	"ElectricShear" bursts its sparks and flashes its light. The local player's own tool is
	handled instantly by ShearingClient (no waiting for the attribute to replicate), so it's skipped here.

	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.ElectricShearClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

--// Configs
local TAG = "ElectricShear"
local BURST_COUNT = 18
local FLASH_BRIGHTNESS = 3
local FLASH_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local player = players.LocalPlayer

local function isLocalPlayersTool(tool: Instance): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	return (backpack ~= nil and tool:IsDescendantOf(backpack))
		or (player.Character ~= nil and tool:IsDescendantOf(player.Character))
end

local function snip(tool: Instance)
	-- Only tools out in the world (held by a character) show anything; skips the template in ReplicatedStorage.
	if not tool:IsDescendantOf(workspace) or isLocalPlayersTool(tool) then
		return
	end

	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "ElectricBurst" then
			descendant:Emit(BURST_COUNT)
		elseif descendant:IsA("PointLight") and descendant.Name == "ElectricGlow" then
			local rest = (descendant:GetAttribute("RestBrightness") :: number?) or descendant.Brightness
			descendant:SetAttribute("RestBrightness", rest)
			descendant.Brightness = FLASH_BRIGHTNESS
			tweenService:Create(descendant, FLASH_TWEEN, { Brightness = rest }):Play()
		end
	end
end

local function watch(tool: Instance)
	tool:GetAttributeChangedSignal("Snips"):Connect(function()
		snip(tool)
	end)
end

for _, tool in collectionService:GetTagged(TAG) do
	watch(tool)
end
collectionService:GetInstanceAddedSignal(TAG):Connect(watch)
