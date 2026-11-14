--!strict

--[[
	Camera shake from "trauma" (0-1) that decays on its own: add() bumps it, and the shake (trauma squared) wobbles the camera after it updates.
	Skipped while a cutscene owns the camera (Scriptable) or the Screen Shake setting is off.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.ScreenShake
]]--

--// Services
local runService = game:GetService("RunService")

--// Modules
local settings = require(script.Parent.Settings)

--// Configs
local BIND_NAME = "ScreenShake"
local DECAY_PER_SECOND = 1.6 -- trauma lost each second
local MAX_ROLL = math.rad(2.2) -- at full trauma
local MAX_OFFSET = 0.45 -- studs the camera moves at full trauma
local FREQUENCY = 22 -- noise speed; higher is a tighter rattle

--// State
local trauma = 0
local bound = false
local seed = math.random() * 1000

local ScreenShake = {}

local function step(deltaTime: number)
	trauma = math.max(trauma - DECAY_PER_SECOND * deltaTime, 0)
	if trauma <= 0 then
		runService:UnbindFromRenderStep(BIND_NAME)
		bound = false
		return
	end

	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return
	end

	-- Only sideways / up-down movement and roll: the default camera reads its look direction back from CFrame next
	-- frame, so pitch or yaw here would drift the view, while these are rebuilt from the subject every frame.
	local shake = trauma * trauma
	local t = os.clock() * FREQUENCY
	local roll = MAX_ROLL * shake * math.noise(seed, t)
	local offset = Vector3.new(math.noise(seed + 10, t), math.noise(seed + 20, t), 0) * (MAX_OFFSET * shake)
	camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(0, 0, roll)
end

-- Adds `amount` of trauma (0.1 is a nudge, 0.5 a big hit, 1 the most there is).
function ScreenShake.add(amount: number)
	if not settings.get("ScreenShake") then
		return
	end
	trauma = math.clamp(trauma + amount, 0, 1)
	if not bound then
		bound = true
		-- Just after the camera scripts, so their CFrame is the one shaken (and it's set fresh again next frame).
		runService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, step)
	end
end

return ScreenShake
