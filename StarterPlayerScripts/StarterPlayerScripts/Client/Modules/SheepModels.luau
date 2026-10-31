--[[
	Finds a sheep type's model in Assets.Models.Sheeps: Baby/Giant types in their folder (SheepHandler makes any missing), else the adult's.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.SheepModels
]]--

--// Services
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Instances
local sheepModels = replicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Sheeps")

--// Configs
local VARIANT_FOLDERS = { Baby = "BabySheeps", Giant = "GiantSheeps" } -- mirrors the server's SheepData.Variants

local SheepModels = {}

function SheepModels.find(sheepType: string): Model?
	for prefix, folderName in VARIANT_FOLDERS do
		local adultType = string.match(sheepType, `^{prefix}(%u.*)$`)
		if adultType then
			local folder = sheepModels:FindFirstChild(folderName)
			local model = (folder and folder:FindFirstChild(sheepType)) or sheepModels:FindFirstChild(adultType)
			return if model and model:IsA("Model") then model else nil
		end
	end

	local model = sheepModels:FindFirstChild(sheepType)
	return if model and model:IsA("Model") then model else nil
end

return SheepModels
