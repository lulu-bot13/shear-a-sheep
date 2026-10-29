--[[
	Smash's effect for everyone: the ground erupts where the caster slammed it, with a thud; only the caster's camera shakes.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Abilities.Smash
]]--

--// Services
local players = game:GetService("Players")
local soundService = game:GetService("SoundService")

--// Modules
local GroundBurst = require(script.Parent.Parent.GroundBurst)

--// Instances
local localPlayer = players.LocalPlayer

--// Configs
local IMPACT_SOUND_NAME = "Smash"
local SOUND_LIFETIME = 4
local CHUNK_SPACING = 2.6 -- studs between chunks around each ring, so bigger smashes get more of them
local MAX_CHUNKS = 60

local Smash = {}

-- A copy of the impact sound at the hit, so nearby players hear it from the right place.
local function playImpactSound(position: Vector3)
	local abilitySounds = soundService:FindFirstChild("AbilitySounds")
	local template = abilitySounds and abilitySounds:FindFirstChild(IMPACT_SOUND_NAME)
	if not template or not template:IsA("Sound") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local sound = template:Clone()
	sound.Parent = attachment
	sound:Play()
	task.delay(math.max(sound.TimeLength, SOUND_LIFETIME), function()
		attachment:Destroy()
	end)
end

function Smash.onEffect(caster: Player, position: any, radius: any)
	if typeof(position) ~= "Vector3" or type(radius) ~= "number" then
		return
	end

	local outerRadius = radius * 0.7
	local innerRadius = 3.5
	local rings = 3
	local chunkCount = math.min(math.floor((innerRadius + outerRadius) / 2 * math.pi * 2 * rings / CHUNK_SPACING), MAX_CHUNKS)

	GroundBurst.play(position, {
		chunkCount = chunkCount,
		rings = rings,
		innerRadius = innerRadius,
		radius = outerRadius,
		height = 3.5,
		chunkSize = 2.8,
		lifetime = 1.8,
		waveSpeed = 55,
		debrisCount = 14,
		dustCount = 28,
		shockwaveRadius = radius,
		shake = if caster == localPlayer then 1.1 else 0,
		shakeRange = radius * 2,
	})
	playImpactSound(position)
end

return Smash
