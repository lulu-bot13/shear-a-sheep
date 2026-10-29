--!strict

--[[
	Small helpers every ability module shares: liveness checks, the player's root and equipping the main shears.
	Location: ServerScriptService.Modules.Abilities.AbilityUtil
]]--

--// Modules
local ShearShopHandler = require(script.Parent.Parent.Controllers.ShearShopHandler)

local AbilityUtil = {}

function AbilityUtil.isAlive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- False once the player left, respawned (their character is no longer `character`) or died.
function AbilityUtil.isStillActive(player: Player, character: Model?): boolean
	return player.Parent ~= nil and character ~= nil and player.Character == character and AbilityUtil.isAlive(player)
end

function AbilityUtil.getRoot(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Puts the equipped shears in the player's main hand if they aren't already holding them.
function AbilityUtil.equipMainShears(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tool = ShearShopHandler.getTool(player)
	if humanoid and tool and tool.Parent ~= character then
		humanoid:EquipTool(tool)
	end
end

return AbilityUtil
