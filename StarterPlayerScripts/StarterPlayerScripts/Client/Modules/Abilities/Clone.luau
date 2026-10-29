--[[
	Clone's effects for everyone: a poof where each clone appears and vanishes. The clones themselves are server models.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Abilities.Clone
]]--

--// Services
local debris = game:GetService("Debris")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")

--// Instances
local assets = replicatedStorage:WaitForChild("Assets")

--// Configs
local POOF_VFX_NAME = "ClonePoof" -- optional Attachment of ParticleEmitters in Assets.VFX ("EmitCount" attributes)
local FALLBACK_VFX_NAME = "PoofAttachment" -- the sheep poof, used when there is no ClonePoof
local SPAWN_SOUND_NAME = "CloneSpawn" -- optional Sounds in SoundService.UISounds
local DESPAWN_SOUND_NAME = "CloneDespawn"
local DESPAWN_SOUND_ID = "rbxassetid://111612755430719" -- used when there is no CloneDespawn Sound
local DEFAULT_EMIT_COUNT = 20

--// State
local poofAttachment: Attachment? = nil

local Clone = {}

-- One emitter attachment, moved to each clone: emitted particles stay where they were emitted.
local function getPoofAttachment(): Attachment?
	if poofAttachment and poofAttachment.Parent then
		return poofAttachment
	end

	local vfx = assets:FindFirstChild("VFX")
	local template = vfx and (vfx:FindFirstChild(POOF_VFX_NAME) or vfx:FindFirstChild(FALLBACK_VFX_NAME))
	if not template or not template:IsA("Attachment") then
		return nil
	end

	local attachment = template:Clone()
	for _, descendant in attachment:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end
	attachment.Name = "ClonePoof"
	attachment.Parent = workspace.Terrain
	poofAttachment = attachment
	return attachment
end

local function poof(position: Vector3)
	local attachment = getPoofAttachment()
	if not attachment then
		return
	end

	attachment.WorldPosition = position
	for _, descendant in attachment:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitCount = descendant:GetAttribute("EmitCount")
			descendant:Emit(if type(emitCount) == "number" then emitCount else DEFAULT_EMIT_COUNT)
		end
	end
end

local function playSoundAt(name: string, position: Vector3)
	local folder = soundService:FindFirstChild("UISounds")
	local template = folder and folder:FindFirstChild(name)
	local copy: Sound
	if template and template:IsA("Sound") then
		copy = template:Clone()
	elseif name == DESPAWN_SOUND_NAME then
		copy = Instance.new("Sound")
		copy.SoundId = DESPAWN_SOUND_ID
	else
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	copy.Parent = attachment
	copy:Play()
	debris:AddItem(attachment, math.max(copy.TimeLength, 1) + 0.5)
end

function Clone.onEffect(_caster: Player?, action: any, positions: any)
	if (action ~= "Spawn" and action ~= "Despawn") or type(positions) ~= "table" then
		return
	end

	local first: Vector3? = nil
	for _, position in positions do
		if typeof(position) == "Vector3" then
			first = first or position
			poof(position)
		end
	end
	if first then
		playSoundAt(if action == "Spawn" then SPAWN_SOUND_NAME else DESPAWN_SOUND_NAME, first)
	end
end

return Clone
