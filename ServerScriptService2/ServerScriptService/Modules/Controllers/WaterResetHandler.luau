--!strict

--[[
	A player touching a "WaterReset" part (the sea) gets a splash and is sent back to their plot (or the SpawnLocation);
	a farm sheep that touches it goes back to its pen.

	Location: ServerScriptService.Modules.Controllers.WaterResetHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")

--// Modules
local PlotHandler = require(script.Parent.PlotHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)

--// Configs
local WATER_TAG = "WaterReset"
local PLAYER_COOLDOWN = 1.5 -- seconds before the same player can splash again
local SPLASH_SOUND_ID = "rbxasset://sounds/impact_water.mp3" -- ships with Roblox (the default character splash)
local SPLASH_COLOR = Color3.fromRGB(170, 220, 255)
local SPLASH_COUNT = 30
local SPLASH_LIFETIME = 2 -- seconds the splash part lives

--// State
local lastSplash: { [Player]: number } = {}
local watched: { [BasePart]: boolean } = {}

local WaterResetHandler = {}

-- A droplet burst and a splash sound at `position`, on a throwaway invisible part.
local function playSplash(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "WaterSplash"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.CFrame = CFrame.new(position)

	local drops = Instance.new("ParticleEmitter")
	drops.Enabled = false
	drops.Color = ColorSequence.new(SPLASH_COLOR)
	drops.LightEmission = 0.3
	drops.Lifetime = NumberRange.new(0.6, 1)
	drops.Speed = NumberRange.new(14, 24)
	drops.SpreadAngle = Vector2.new(35, 35)
	drops.Acceleration = Vector3.new(0, -50, 0)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	drops.Transparency = NumberSequence.new(0.2, 1)
	drops.Parent = part

	local sound = Instance.new("Sound")
	sound.SoundId = SPLASH_SOUND_ID
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 120
	sound.Parent = part

	part.Parent = workspace
	drops:Emit(SPLASH_COUNT)
	sound:Play()
	debris:AddItem(part, SPLASH_LIFETIME)
end

local function resetPlayer(player: Player, character: Model, contact: Vector3)
	local now = os.clock()
	if now - (lastSplash[player] or 0) < PLAYER_COOLDOWN then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	lastSplash[player] = now

	playSplash(contact)
	local target = PlotHandler.getRespawnCFrame(player)
	if target then
		character:PivotTo(target)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- A registered farm sheep (not one being carried) goes back to its pen.
local function resetSheep(sheep: Model, contact: Vector3)
	local id = sheep:GetAttribute("id")
	if type(id) ~= "number" or SheepHandler.getSheep(id) ~= sheep then
		return
	end
	playSplash(contact)
	SheepWanderHandler.returnToPen(sheep)
end

local function onTouched(water: BasePart, hit: BasePart)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return
	end
	local contact = Vector3.new(hit.Position.X, water.Position.Y + water.Size.Y / 2, hit.Position.Z)

	local player = players:GetPlayerFromCharacter(model)
	if player then
		resetPlayer(player, model, contact)
	elseif model:GetAttribute("SheepType") ~= nil then
		resetSheep(model, contact)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("BasePart") or watched[instance] then
		return
	end
	watched[instance] = true
	if not instance.CanTouch then
		warn(`WaterResetHandler: {instance:GetFullName()} has CanTouch off, so it can't send swimmers back; turn it on in Studio.`)
	end
	instance.Touched:Connect(function(hit: BasePart)
		onTouched(instance, hit)
	end)
	instance.Destroying:Once(function()
		watched[instance] = nil
	end)
end

function WaterResetHandler.Start()
	collectionService:GetInstanceAddedSignal(WATER_TAG):Connect(watch)
	for _, water in collectionService:GetTagged(WATER_TAG) do
		watch(water)
	end
	players.PlayerRemoving:Connect(function(player: Player)
		lastSplash[player] = nil
	end)
end

return WaterResetHandler
