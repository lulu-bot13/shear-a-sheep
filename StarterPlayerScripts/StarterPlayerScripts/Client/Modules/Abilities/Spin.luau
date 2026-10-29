--[[
	Spin's local effect: turns the character on the spot while AbilityHandler keeps the ability active.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.Abilities.Spin
]]--

--// Services
local runService = game:GetService("RunService")

--// Configs
local SPIN_SPEED = math.rad(900) -- radians per second the character turns

local Spin = {}

Spin.loopAnimation = true

function Spin.start(character: Model, humanoid: Humanoid): () -> ()
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return function() end
	end

	-- AutoRotate off so the humanoid stops turning the character to face its walk direction.
	humanoid.AutoRotate = false
	local connection = runService.RenderStepped:Connect(function(deltaTime: number)
		if root.Parent then
			root.CFrame *= CFrame.Angles(0, SPIN_SPEED * deltaTime, 0)
		end
	end)

	return function()
		connection:Disconnect()
		humanoid.AutoRotate = true
	end
end

return Spin
