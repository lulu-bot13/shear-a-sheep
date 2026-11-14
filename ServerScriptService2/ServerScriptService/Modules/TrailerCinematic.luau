--[[
	One-off ~20 second cinematic trailer for recording with OBS: in Studio or a live server, an owner presses F7 (or chats /trailer) and it directs itself.
	The server half stages the progression and puts the save back after; it copies this module into ReplicatedStorage.Source so the client half runs too.
	Location: ServerScriptService.Modules.TrailerCinematic
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")

--// Shared configs
local REMOTE_NAME = "TrailerCinematicRemote"
local PENS_FOLDER_NAME = "TrailerCinematicPens" -- ReplicatedStorage: every pen style, already moved onto the player's plot
local DEFAULT_SHEAR = "DefaultShear"
local BOSS_TAG = "WorldBoss" -- WorldBossData.Tag
local ALLOWED_ATTRIBUTE = "TrailerAllowed" -- set on the player by the server for the game's owners (anyone in Studio)

local TrailerCinematic = {}

--=====================================================================================
--// Server half: stages the save for each scene, then restores it
--=====================================================================================

local function runServer()
	local serverScriptService = game:GetService("ServerScriptService")
	local serverStorage = game:GetService("ServerStorage")

	-- The client's ModuleLoader requires everything in ReplicatedStorage.Source, so a copy there runs the client half.
	local sourceFolder = replicatedStorage:WaitForChild("Source")
	if not sourceFolder:FindFirstChild(script.Name) then
		script:Clone().Parent = sourceFolder
	end

	local modules = serverScriptService:WaitForChild("Modules")
	local controllers = modules:WaitForChild("Controllers")
	local constants = modules:WaitForChild("Constants")
	local network = require(replicatedStorage.Shared.Utils.Network)
	local PlayerDataHandler = require(controllers.PlayerDataHandler)
	local PlotHandler = require(controllers.PlotHandler)
	local SheepHandler = require(controllers.SheepHandler)
	local SheepSpawnHandler = require(controllers.SheepSpawnHandler)
	local ShearShopHandler = require(controllers.ShearShopHandler)
	local WeatherHandler = require(controllers.WeatherHandler)
	local PenStyleData = require(constants.PenStyleData)
	local ShearData = require(constants.ShearData)
	local UpgradeData = require(constants.UpgradeData)
	local WeatherData = require(constants.WeatherData)
	local WorldBossData = require(constants.WorldBossData)
	local AdminCommands = require(modules:WaitForChild("Utils"):WaitForChild("AdminCommands"))

	-- Only the game's owners (AdminCommands.isOwner: everyone in Studio) may stage their save; their client is told so.
	local function markAllowed(player: Player)
		if AdminCommands.isOwner(player) then
			player:SetAttribute(ALLOWED_ATTRIBUTE, true)
		end
	end
	players.PlayerAdded:Connect(markAllowed)
	for _, player in players:GetPlayers() do
		markAllowed(player)
	end

	type Session = { snapshot: { [string]: any }, data: { [string]: any } }
	local sessions: { [Player]: Session } = {}

	local function deepCopy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local copy = {}
		for key, inner in value do
			copy[deepCopy(key)] = deepCopy(inner)
		end
		return copy
	end

	local function deepEqual(a: any, b: any): boolean
		if a == b then
			return true
		elseif type(a) ~= "table" or type(b) ~= "table" then
			return false
		end
		for key, value in a do
			if not deepEqual(value, b[key]) then
				return false
			end
		end
		for key in b do
			if a[key] == nil then
				return false
			end
		end
		return true
	end

	-- The Shear Damage level at which the equipped shear takes `health` off in `swings` hits.
	local function getDamageLevel(player: Player, health: number, swings: number): number
		local base = ShearShopHandler.getShear(player).damage
		local needed = math.ceil(health / math.max(swings, 1))
		return math.max(math.ceil((needed / base - 1) / UpgradeData.ShearDamagePerLevel), 0)
	end

	local function poof(positions: { Vector3 })
		if #positions > 0 then
			network.fireAllClients(network.RemoteEvents.SheepPoof, positions)
		end
	end

	-- Copies every ServerStorage.PenStyles tier onto the player's plot (as PlotLayoutHandler places them) for the client's montage.
	local function copyPens(player: Player): boolean
		local plot = PlotHandler.getPlayerPlot(player)
		local anchor = plot and plot:FindFirstChild("SpawnArea")
		local template = serverStorage:FindFirstChild("TemplatePlot")
		local templateAnchor = template and template:FindFirstChild("SpawnArea")
		local styles = serverStorage:FindFirstChild(PenStyleData.FolderName)
		if not anchor or not templateAnchor or not styles then
			warn("TrailerCinematic: couldn't find the plot, ServerStorage.TemplatePlot or ServerStorage.PenStyles; the pen montage is skipped.")
			return false
		end

		local folder = replicatedStorage:FindFirstChild(PENS_FOLDER_NAME) or Instance.new("Folder")
		folder:ClearAllChildren()
		folder.Name = PENS_FOLDER_NAME
		for index, tier in PenStyleData.Tiers do
			local style = styles:FindFirstChild(tier.template)
			if style and style:IsA("Model") then
				local copy = style:Clone()
				copy.Name = tostring(index)
				copy:SetAttribute("PenName", tier.name)
				copy:PivotTo(anchor.CFrame * templateAnchor.CFrame:ToObjectSpace(copy:GetPivot()))
				copy.Parent = folder
			end
		end
		folder.Parent = replicatedStorage
		return true
	end

	local actions = {}

	-- A brand-new farm: no rebirths (wooden pen), basic shears, an empty pen with no refills, every shear "owned" for the shop shot.
	function actions.Prepare(player: Player)
		local data = PlayerDataHandler.getData(player)
		if not data then
			return nil
		end
		if not sessions[player] then
			sessions[player] = { snapshot = deepCopy(data), data = data } -- a retake keeps the original save
		end

		pcall(WeatherHandler.setWeather, WeatherData.Clear)
		local allShears = {}
		for _, info in ShearData.Shears do
			table.insert(allShears, info.id)
		end
		PlayerDataHandler.set(player, "Rebirths", 0)
		PlayerDataHandler.set(player, "Prestiges", 0)
		PlayerDataHandler.set(player, "DamageLevel", 5) -- the basic shear then takes a basic sheep in 3 snips, so the first shot lands
		PlayerDataHandler.set(player, "MaxSheep", 0) -- no refills: every sheep on camera is dropped in by the trailer
		PlayerDataHandler.set(player, "OwnedShears", allShears)
		ShearShopHandler.grantShear(player, DEFAULT_SHEAR)
		SheepHandler.clearSheep(player)
		copyPens(player)

		local arena = collectionService:GetTagged(WorldBossData.SpawnTag)[1]
		return { arena = if arena and arena:IsA("BasePart") then arena.Position else nil }
	end

	-- Drops sheep of these types into the pen with a poof; returns their ids in order.
	function actions.Spawn(player: Player, sheepTypes: { string })
		local ids, positions = {}, {}
		for _, sheepType in sheepTypes do
			local sheep = SheepSpawnHandler.spawnForced(player, { sheepType = sheepType, size = "Normal", noMutation = true })
			if sheep then
				table.insert(ids, sheep:GetAttribute("id"))
				table.insert(positions, sheep:GetPivot().Position)
			end
		end
		poof(positions)
		return ids
	end

	-- The client's own teleport takes a few frames to reach the server, which judges shear range, so it's mirrored here.
	function actions.Place(player: Player, cframe: CFrame)
		local character = player.Character
		if character and typeof(cframe) == "CFrame" then
			character:PivotTo(cframe)
		end
		return true
	end

	-- Every sheep in the pen goes up in a poof, like a real rebirth.
	function actions.ClearPen(player: Player)
		local positions = {}
		for _, sheep in SheepHandler.getAllSheep() do
			if SheepHandler.getOwnerId(sheep) == player.UserId then
				table.insert(positions, sheep:GetPivot().Position)
			end
		end
		SheepHandler.clearSheep(player)
		poof(positions)
		return true
	end

	-- One montage cut: equips `shearId` and sets Shear Damage so the sheep with this id is shorn in `swings` hits.
	function actions.Arm(player: Player, shearId: string, sheepId: number?, swings: number)
		ShearShopHandler.grantShear(player, shearId)
		local sheep = if type(sheepId) == "number" then SheepHandler.getSheep(sheepId) else nil
		local health = sheep and sheep:GetAttribute("MaxShearHealth")
		if type(health) == "number" then
			PlayerDataHandler.set(player, "DamageLevel", getDamageLevel(player, health, swings))
		end
		return true
	end

	-- Equips `shearId` and sets Shear Damage so the live King Sheep goes down in `swings` hits.
	function actions.ArmKing(player: Player, shearId: string, swings: number)
		ShearShopHandler.grantShear(player, shearId)
		local boss = collectionService:GetTagged(BOSS_TAG)[1]
		local health = boss and boss:GetAttribute("Health")
		if type(health) == "number" then
			PlayerDataHandler.set(player, "DamageLevel", getDamageLevel(player, health, swings))
		end
		return boss ~= nil
	end

	-- Puts every save field the trailer touched back as it was, then refills the pen.
	function actions.Restore(player: Player)
		local session = sessions[player]
		sessions[player] = nil
		local data = PlayerDataHandler.getData(player)
		if session and data then
			local snapshot = session.snapshot
			local keys = {}
			for key in snapshot do
				keys[key] = true
			end
			for key in data do
				keys[key] = true
			end
			for key in keys do
				if key ~= "ShearId" and not deepEqual(data[key], snapshot[key]) then
					PlayerDataHandler.set(player, key, deepCopy(snapshot[key]))
				end
			end
			local shearId = snapshot.ShearId
			ShearShopHandler.grantShear(player, if type(shearId) == "string" and ShearShopHandler.ownsShear(player, shearId) then shearId else DEFAULT_SHEAR)
		end
		SheepSpawnHandler.resetFarm(player)
		local pens = replicatedStorage:FindFirstChild(PENS_FOLDER_NAME)
		if pens then
			pens:Destroy()
		end
		return true
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = REMOTE_NAME
	remote.OnServerInvoke = function(player: Player, action: any, ...: any)
		if not AdminCommands.isOwner(player) then
			return nil
		end
		local handler = if type(action) == "string" then actions[action] else nil
		-- Anything but Prepare needs a live session, so a call still in flight after Restore can't stage the save again.
		if not handler or (action ~= "Prepare" and action ~= "Restore" and not sessions[player]) then
			return nil
		end
		local success, result = pcall(handler, player, ...)
		if not success then
			warn(`TrailerCinematic: {action} failed: {result}`)
			return nil
		end
		return result
	end
	remote.Parent = replicatedStorage

	-- Leaving mid-trailer (stopping the playtest) writes the original save straight back before the profile saves.
	players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		sessions[player] = nil
		if not session then
			return
		end
		for key in session.data do
			if session.snapshot[key] == nil then
				session.data[key] = nil
			end
		end
		for key, value in session.snapshot do
			session.data[key] = deepCopy(value)
		end
	end)
end

--=====================================================================================
--// Client half: camera, post FX, UI and the game events, all on one timeline
--=====================================================================================

local function runClient()
	local contextActionService = game:GetService("ContextActionService")
	local debris = game:GetService("Debris")
	local lighting = game:GetService("Lighting")
	local proximityPromptService = game:GetService("ProximityPromptService")
	local soundService = game:GetService("SoundService")
	local starterGui = game:GetService("StarterGui")
	local textChatService = game:GetService("TextChatService")
	local tweenService = game:GetService("TweenService")
	local userInputService = game:GetService("UserInputService")

	local player = players.LocalPlayer
	-- Everyone else's copy stops here: no overlay, key or chat command for players who aren't owners.
	while player:GetAttribute(ALLOWED_ATTRIBUTE) ~= true do
		player:GetAttributeChangedSignal(ALLOWED_ATTRIBUTE):Wait()
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local clientModules = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Modules")
	local remote = replicatedStorage:WaitForChild(REMOTE_NAME) :: RemoteFunction
	local plotsFolder = workspace:WaitForChild("Base"):WaitForChild("Plots")
	local uiSounds = soundService:FindFirstChild("UISounds")

	--// Configs ---------------------------------------------------------------------------

	local TRIGGER_KEY = Enum.KeyCode.F7 -- starts the trailer; press again to abort
	local CHAT_COMMAND = "/trailer"
	local GAME_TITLE = "SHEAR A SHEEP"
	local END_SUBTITLE = "PLAY NOW!"
	local SHOW_CAPTIONS = true -- set false to cut the kinetic text and add your own in the edit
	local MUTE_MUSIC = true -- the game's music would clash with the trailer track you add in the edit
	local ALLOWED_GUIS = { DamageNumbers = true, SheepScreenEffects = true } -- juice that stays on screen; every other ScreenGui is hidden

	local LETTERBOX = 0.07 -- of the screen, each black bar (0 = none)
	local HANDHELD_DEGREES = 0.35 -- subtle camera sway
	local WHIP_SECONDS = 0.14 -- each half of a whip pan
	local WHIP_DEGREES = 38
	local WHIP_BLUR = 22
	local SWING_GAP = 0.4 -- real seconds between swings, over ShearData.SwingCooldown (0.35) so ShearClient never drops one

	local START_SHEEP = { "Basic", "Basic", "Basic" }
	local MONTAGE = { -- one cut each: the shear, the sheep it shears and the caption
		{ shear = "SteelShears", sheep = "Grey", caption = "SHEAR SHEEP" },
		{ shear = "LargeShears", sheep = "Fluffy", caption = "COLLECT WOOL" },
		{ shear = "ElectricShears", sheep = "Golden", caption = "GET STRONGER" },
	}
	local MONTAGE_SWINGS = 2 -- each montage sheep is shorn on this hit (the cut allows one spare)
	local FANCY_SHEEP = { "Rainbow", "Diamond", "Golden", "Alien", "Ruby", "Princess", "Wizard" } -- poofs in on the last rebirth
	local KING_SHEAR = "ShadowShear"
	local KING_SWINGS = 4
	local TELEPORT_SETTLE = 0.2 -- seconds after a teleport before swinging, so the server already has the new position

	local GOLD = Color3.fromRGB(255, 211, 77)
	local INK = Color3.fromRGB(28, 18, 8)
	local FONT = Enum.Font.FredokaOne

	local RENDER_NAME = "TrailerCinematic"
	local PREP_SETTLE_SECONDS = 1.6 -- black screen after staging: the fence swap, the shear tool and streaming settle
	local RESTORE_HOLD_SECONDS = 1.8 -- black after restoring, long enough that PenUnlockClient's cutscene can't take the camera

	local UP = Vector3.yAxis

	--// State -----------------------------------------------------------------------------

	local running = false
	local aborted = false
	local startClock = 0
	local frameDt = 1 / 60
	local camera = workspace.CurrentCamera

	local plot: Instance? = nil
	local penCenter = Vector3.zero
	local penSize = 30
	local penFront = Vector3.new(0, 0, -1)
	local penRight = Vector3.new(1, 0, 0)
	local groundY = 0
	local arenaPosition = Vector3.zero
	local arenaGroundY = 0
	local kingHeight = 14

	local target: Model? = nil -- the sheep being sheared right now
	local lastTargetPosition: Vector3? = nil
	local king: Model? = nil
	local lastKingPosition: Vector3? = nil
	local chase: (() -> Vector3?)? = nil -- while set, the character walks up to this and stops in shearing range
	local chaseStop = 4
	local nextChaseAt = 0
	local placedAt = 0

	local tracked: { [string]: Vector3 } = {}
	local shotState: { [string]: any } = {}
	local fovPunch = 0
	local trauma = 0

	local cleanups: { () -> () } = {}
	local hiddenFence: { [Instance]: any } = {}
	local penClone: Model? = nil
	local shopWindow: any = nil
	local shopScroll: ScrollingFrame? = nil
	local allowedNow: { [string]: boolean } = {}

	--// Helpers ---------------------------------------------------------------------------

	local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
		local created = tweenService:Create(instance, info, goal)
		created:Play()
		return created
	end

	local function ease(alpha: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): number
		return tweenService:GetValue(math.clamp(alpha, 0, 1), style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut)
	end

	local function flat(vector: Vector3): Vector3
		return Vector3.new(vector.X, 0, vector.Z)
	end

	local function unitFlat(vector: Vector3, fallback: Vector3?): Vector3
		local flattened = flat(vector)
		return if flattened.Magnitude > 1e-3 then flattened.Unit else fallback or penFront
	end

	local function sideOf(direction: Vector3): Vector3
		return direction:Cross(UP)
	end

	local function around(angle: number): Vector3
		return Vector3.new(math.cos(angle), 0, math.sin(angle))
	end

	local function angleOf(direction: Vector3): number
		return math.atan2(direction.Z, direction.X)
	end

	local function aboveGround(position: Vector3, floorY: number, clearance: number): Vector3
		return Vector3.new(position.X, math.max(position.Y, floorY + clearance), position.Z)
	end

	-- Smooths a moving subject so the camera never jitters; cleared on every cut, so a new shot starts locked on.
	local function track(key: string, position: Vector3, sharpness: number?): Vector3
		local current = tracked[key]
		if not current then
			tracked[key] = position
			return position
		end
		current = current:Lerp(position, 1 - math.exp(-(sharpness or 8) * frameDt))
		tracked[key] = current
		return current
	end

	-- The farmer-to-sheep direction, eased so the camera follows a wandering sheep round instead of ending up behind the farmer.
	local function pairDirection(character: Vector3, sheep: Vector3): Vector3
		local raw = unitFlat(sheep - character, shotState.direction)
		local direction = unitFlat(track("direction", raw, 3), raw)
		shotState.direction = direction
		return direction
	end

	local function getCharacterRoot(): BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root else nil
	end

	local function getHumanoid(): Humanoid?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return if humanoid and humanoid.Health > 0 then humanoid else nil
	end

	local function getModelPosition(model: Model?): Vector3?
		if not model or not model.Parent then
			return nil
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else model:GetPivot().Position
	end

	local function playerPosition(): Vector3
		local root = getCharacterRoot()
		return if root then root.Position else penCenter + UP * 3
	end

	-- The sheep being sheared (its last spot once it's shorn and gone, so the camera doesn't jump).
	local function targetPosition(): Vector3
		local current = target
		if current and current.Parent and current.Parent.Name == "Sheeps" then
			lastTargetPosition = getModelPosition(current)
		end
		return lastTargetPosition or playerPosition()
	end

	local function findKing(): Model?
		for _, boss in collectionService:GetTagged(BOSS_TAG) do
			if boss:IsA("Model") and boss:IsDescendantOf(workspace) then
				return boss
			end
		end
		return nil
	end

	local function kingPosition(): Vector3
		if not king or not king.Parent then
			king = findKing()
		end
		local position = getModelPosition(king)
		if position then
			lastKingPosition = position
		end
		return lastKingPosition or arenaPosition + UP * 5
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.RespectCanCollide = true

	local function groundAt(position: Vector3): Vector3
		local ignore: { Instance } = {}
		if player.Character then
			table.insert(ignore, player.Character)
		end
		local sheepFolder = plot and plot:FindFirstChild("Sheeps")
		if sheepFolder then
			table.insert(ignore, sheepFolder)
		end
		for _, boss in collectionService:GetTagged(BOSS_TAG) do
			table.insert(ignore, boss)
		end
		rayParams.FilterDescendantsInstances = ignore
		local result = workspace:Raycast(position + UP * 30, -UP * 90, rayParams)
		return if result then result.Position else position
	end

	local function playSound(name: string, speed: number?, volume: number?)
		local template = uiSounds and uiSounds:FindFirstChild(name)
		if template and template:IsA("Sound") then
			local sound = template:Clone()
			sound.PlaybackSpeed = speed or 1
			sound.Volume = template.Volume * (volume or 1)
			sound.Parent = uiSounds
			sound:Play()
			debris:AddItem(sound, 4)
		end
	end

	local function poofAt(position: Vector3)
		local vfx = replicatedStorage:FindFirstChild("Assets") and replicatedStorage.Assets:FindFirstChild("VFX")
		local template = vfx and vfx:FindFirstChild("PoofAttachment")
		if not template or not template:IsA("Attachment") then
			return
		end
		local attachment = template:Clone()
		attachment.WorldPosition = position
		attachment.Parent = workspace.Terrain
		for _, emitter in attachment:GetDescendants() do
			if emitter:IsA("ParticleEmitter") then
				local count = emitter:GetAttribute("EmitCount")
				emitter:Emit(if type(count) == "number" then count else 10)
			end
		end
		debris:AddItem(attachment, 3)
	end

	local function invoke(action: string, ...: any): any
		local success, result = pcall(remote.InvokeServer, remote, action, ...)
		if not success then
			warn(`TrailerCinematic: {action} failed: {result}`)
			return nil
		end
		return result
	end

	--// Character -------------------------------------------------------------------------

	-- Stands the character on the ground at `position`, facing `lookAt`, and cancels any walk.
	local function placeCharacter(position: Vector3, lookAt: Vector3)
		local character = player.Character
		local root = getCharacterRoot()
		local humanoid = getHumanoid()
		if not character or not root or not humanoid then
			return
		end
		local floor = groundAt(position)
		local height = if humanoid.RigType == Enum.HumanoidRigType.R6 then 3 else humanoid.HipHeight + root.Size.Y / 2
		local standAt = Vector3.new(position.X, floor.Y + height, position.Z)
		local faceAt = Vector3.new(lookAt.X, standAt.Y, lookAt.Z)
		local cframe = if (faceAt - standAt).Magnitude > 0.1 then CFrame.lookAt(standAt, faceAt) else CFrame.new(standAt)
		character:PivotTo(cframe)
		task.spawn(invoke, "Place", cframe)
		root.AssemblyLinearVelocity = Vector3.zero
		humanoid:MoveTo(standAt)
		placedAt = os.clock()
	end

	local function face(position: Vector3)
		local root = getCharacterRoot()
		if not root then
			return
		end
		local from = root.Position
		local at = Vector3.new(position.X, from.Y, position.Z)
		if (at - from).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(from, at)
		end
	end

	-- Holds out the shear once ShearShopHandler has put it in the Backpack.
	local function equipShear(id: string, timeout: number?)
		local deadline = os.clock() + (timeout or 2)
		while os.clock() < deadline and running do
			local character = player.Character
			local humanoid = getHumanoid()
			local held = character and character:FindFirstChild(id)
			if held and held:IsA("Tool") then
				return
			end
			local backpack = player:FindFirstChildOfClass("Backpack")
			local tool = backpack and backpack:FindFirstChild(id)
			if humanoid and tool and tool:IsA("Tool") then
				humanoid:EquipTool(tool)
				return
			end
			task.wait()
		end
	end

	-- A real swing: ShearClient plays the animation and ring, the server deals the damage.
	local function swing(at: Vector3)
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		face(at)
		if tool then
			tool:Activate()
		end
	end

	local function updateChase()
		local getTarget = chase
		local root = getCharacterRoot()
		local humanoid = getHumanoid()
		if not getTarget or not root or not humanoid or os.clock() < nextChaseAt then
			return
		end
		nextChaseAt = os.clock() + 0.1
		local goal = getTarget()
		if not goal then
			return
		end
		local offset = flat(goal - root.Position)
		if offset.Magnitude > chaseStop then
			humanoid:MoveTo(goal - offset.Unit * chaseStop * 0.6)
		else
			humanoid:MoveTo(root.Position)
		end
	end

	-- Finds the sheep the server just dropped (by its "id"), waiting for it to replicate.
	local function findSheep(id: number?, timeout: number): Model?
		if not id or not plot then
			return nil
		end
		local deadline = os.clock() + timeout
		repeat
			local folder = plot:FindFirstChild("Sheeps")
			if folder then
				for _, sheep in folder:GetChildren() do
					if sheep:IsA("Model") and sheep:GetAttribute("id") == id then
						return sheep
					end
				end
			end
			task.wait()
		until os.clock() > deadline or not running
		return nil
	end

	local function nearestSheep(from: Vector3): Model?
		local folder = plot and plot:FindFirstChild("Sheeps")
		local best, bestDistance = nil, math.huge
		for _, sheep in (if folder then folder:GetChildren() else {}) do
			local position = sheep:IsA("Model") and getModelPosition(sheep)
			local health = sheep:GetAttribute("ShearHealth")
			if position and (type(health) ~= "number" or health > 0) then
				local distance = (position - from).Magnitude
				if distance < bestDistance then
					best, bestDistance = sheep, distance
				end
			end
		end
		return best
	end

	--// Overlay UI --------------------------------------------------------------------------

	local overlay = Instance.new("ScreenGui")
	overlay.Name = "TrailerCinematic"
	overlay.IgnoreGuiInset = true
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 10000
	overlay.Enabled = false
	overlay.Parent = playerGui

	local function newFrame(name: string, color: Color3, transparency: number, zIndex: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
		frame.BorderSizePixel = 0
		frame.ZIndex = zIndex
		frame.Parent = overlay
		return frame
	end

	-- Soft dark edges, built from gradients so no image asset is needed.
	local function newVignetteEdge(name: string, size: UDim2, position: UDim2, rotation: number)
		local edge = newFrame(name, Color3.new(0, 0, 0), 0, 1)
		edge.Size = size
		edge.Position = position
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.65),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge
	end
	newVignetteEdge("VignetteTop", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0), 90)
	newVignetteEdge("VignetteBottom", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.78), -90)
	newVignetteEdge("VignetteLeft", UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0), 0)
	newVignetteEdge("VignetteRight", UDim2.fromScale(0.16, 1), UDim2.fromScale(0.84, 0), 180)

	local topBar = newFrame("TopBar", Color3.new(0, 0, 0), 0, 20)
	topBar.Size = UDim2.fromScale(1, 0)
	local bottomBar = newFrame("BottomBar", Color3.new(0, 0, 0), 0, 20)
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position = UDim2.fromScale(0, 1)
	bottomBar.Size = UDim2.fromScale(1, 0)

	local flashFrame = newFrame("Flash", Color3.new(1, 1, 1), 1, 15) -- under the bars, so they stay black
	local fadeFrame = newFrame("Fade", Color3.new(0, 0, 0), 1, 50)

	local prepLabel = Instance.new("TextLabel")
	prepLabel.Name = "Preparing"
	prepLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	prepLabel.Position = UDim2.fromScale(0.5, 0.5)
	prepLabel.Size = UDim2.fromScale(0.5, 0.04)
	prepLabel.BackgroundTransparency = 1
	prepLabel.Font = FONT
	prepLabel.Text = "Setting up the trailer..."
	prepLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
	prepLabel.TextScaled = true
	prepLabel.TextTransparency = 1
	prepLabel.ZIndex = 51
	prepLabel.Parent = overlay

	local function newText(name: string, text: string, parent: Instance, position: UDim2, size: UDim2, color: Color3, stroke: number): TextLabel
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = position
		label.Size = size
		label.BackgroundTransparency = 1
		label.Font = FONT
		label.Text = text
		label.TextColor3 = color
		label.TextScaled = true
		label.TextTransparency = 1
		label.ZIndex = 40
		local outline = Instance.new("UIStroke")
		outline.Color = INK
		outline.Thickness = stroke
		outline.Transparency = 1
		outline.Parent = label
		label.Parent = parent
		return label
	end

	local function setTextTransparency(label: TextLabel, transparency: number, info: TweenInfo)
		tween(label, info, { TextTransparency = transparency })
		local outline = label:FindFirstChildOfClass("UIStroke")
		if outline then
			tween(outline, info, { Transparency = transparency })
		end
	end

	local endCard = Instance.new("Frame")
	endCard.Name = "EndCard"
	endCard.Size = UDim2.fromScale(1, 1)
	endCard.BackgroundColor3 = Color3.new(0, 0, 0)
	endCard.BackgroundTransparency = 1
	endCard.BorderSizePixel = 0
	endCard.ZIndex = 35
	endCard.Visible = false
	endCard.Parent = overlay
	local endTitle = newText("Title", GAME_TITLE, endCard, UDim2.fromScale(0.5, 0.44), UDim2.fromScale(0.86, 0.2), Color3.new(1, 1, 1), 6)
	local titleGradient = Instance.new("UIGradient")
	titleGradient.Rotation = 90
	titleGradient.Color = ColorSequence.new(Color3.fromRGB(255, 244, 170), Color3.fromRGB(255, 176, 30))
	titleGradient.Parent = endTitle
	local endTitleScale = Instance.new("UIScale")
	endTitleScale.Parent = endTitle
	local endSubtitle = newText("Subtitle", END_SUBTITLE, endCard, UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.5, 0.08), Color3.new(1, 1, 1), 4)
	local endSubtitleScale = Instance.new("UIScale")
	endSubtitleScale.Parent = endSubtitle
	local subtitlePulse: Tween? = nil

	local activeCaption: TextLabel? = nil
	local captionToken = 0

	-- Big kinetic text above the bottom bar: punches in, drifts, then pops away. A new caption replaces the last at once.
	local function caption(text: string, seconds: number?, color: Color3?)
		if not SHOW_CAPTIONS then
			return
		end
		captionToken += 1
		local token = captionToken
		local previous = activeCaption
		if previous then
			activeCaption = nil
			setTextTransparency(previous, 1, TweenInfo.new(0.08))
			debris:AddItem(previous, 0.1)
		end

		local label = newText("Caption", text, overlay, UDim2.fromScale(0.5, 1 - LETTERBOX - 0.085), UDim2.fromScale(0.9, 0.1), color or GOLD, 4)
		label.Rotation = -4
		local scale = Instance.new("UIScale")
		scale.Scale = 1.55
		scale.Parent = label
		activeCaption = label

		local hold = seconds or 1
		setTextTransparency(label, 0, TweenInfo.new(0.1))
		tween(label, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 })
		tween(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }).Completed:Once(function()
			if label.Parent then
				tween(scale, TweenInfo.new(math.max(hold - 0.32, 0.05), Enum.EasingStyle.Linear), { Scale = 1.06 })
			end
		end)
		task.delay(hold, function()
			if captionToken ~= token or not label.Parent then
				return
			end
			activeCaption = nil
			local out = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			setTextTransparency(label, 1, out)
			tween(scale, out, { Scale = 1.2 })
			debris:AddItem(label, 0.2)
		end)
	end

	local function flash(strength: number, color: Color3?)
		flashFrame.BackgroundColor3 = color or Color3.new(1, 1, 1)
		flashFrame.BackgroundTransparency = 1 - strength
		tween(flashFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
	end

	local function fade(toBlack: boolean, seconds: number): Tween
		return tween(fadeFrame, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = if toBlack then 0 else 1 })
	end

	local function setLetterbox(shown: boolean, seconds: number)
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local height = if shown then LETTERBOX else 0
		tween(topBar, info, { Size = UDim2.fromScale(1, height) })
		tween(bottomBar, info, { Size = UDim2.fromScale(1, height) })
	end

	local function punch(amount: number)
		fovPunch += amount
	end

	local function shake(amount: number)
		trauma = math.min(trauma + amount, 1)
	end

	local function showEndCard()
		endCard.Visible = true
		tween(endCard, TweenInfo.new(0.5), { BackgroundTransparency = 0.35 })
		endTitleScale.Scale = 2.2
		setTextTransparency(endTitle, 0, TweenInfo.new(0.15))
		tween(endTitleScale, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		task.delay(0.45, function()
			if not running then
				return
			end
			endSubtitleScale.Scale = 0.4
			setTextTransparency(endSubtitle, 0, TweenInfo.new(0.15))
			tween(endSubtitleScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }).Completed:Once(function()
				if endCard.Visible then
					subtitlePulse = tween(endSubtitleScale, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.08 })
				end
			end)
			playSound("Pop", 1.1)
		end)
	end

	--// Hiding the game's UI ----------------------------------------------------------------

	local function addCleanup(callback: () -> ())
		table.insert(cleanups, callback)
	end

	-- Hides every other ScreenGui (and keeps it hidden if a script turns it back on), except ALLOWED_GUIS and allowedNow.
	local function hideGameUi()
		local original: { [ScreenGui]: boolean } = {}
		local connections: { RBXScriptConnection } = {}

		local function guard(gui: Instance)
			if not gui:IsA("ScreenGui") or gui == overlay or original[gui] ~= nil then
				return
			end
			original[gui] = gui.Enabled
			local function enforce()
				if running and gui.Enabled and not ALLOWED_GUIS[gui.Name] and not allowedNow[gui.Name] then
					gui.Enabled = false
				end
			end
			table.insert(connections, gui:GetPropertyChangedSignal("Enabled"):Connect(enforce))
			enforce()
		end
		for _, gui in playerGui:GetChildren() do
			guard(gui)
		end
		table.insert(connections, playerGui.ChildAdded:Connect(guard))

		local coreStates: { [Enum.CoreGuiType]: boolean } = {}
		for _, coreType in Enum.CoreGuiType:GetEnumItems() do
			if coreType ~= Enum.CoreGuiType.All then
				local success, enabled = pcall(starterGui.GetCoreGuiEnabled, starterGui, coreType)
				if success then
					coreStates[coreType] = enabled
				end
			end
		end
		starterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		pcall(starterGui.SetCore, starterGui, "TopbarEnabled", false)
		local mouseIcon = userInputService.MouseIconEnabled
		userInputService.MouseIconEnabled = false
		local promptsEnabled = proximityPromptService.Enabled
		pcall(function()
			proximityPromptService.Enabled = false
		end)

		-- World labels that clutter the shots: the plot's owner and capacity signs (the latter reads "3/0" with refills off)
		-- and the farmer's overhead title.
		local hiddenSigns: { LayerCollector } = {}
		local function hideSign(sign: Instance?)
			if sign and sign:IsA("LayerCollector") and sign.Enabled then
				sign.Enabled = false
				table.insert(hiddenSigns, sign)
			end
		end
		local center = plot and plot:FindFirstChild("Center")
		if center then
			hideSign(center:FindFirstChild("PlayerBase"))
			hideSign(center:FindFirstChild("SheepCapacity"))
		end
		for _, descendant in (if player.Character then player.Character:GetDescendants() else {}) do
			if descendant:IsA("BillboardGui") then
				hideSign(descendant)
			end
		end

		addCleanup(function()
			for _, connection in connections do
				connection:Disconnect()
			end
			for gui, enabled in original do
				if gui.Parent then
					gui.Enabled = enabled
				end
			end
			for coreType, enabled in coreStates do
				pcall(starterGui.SetCoreGuiEnabled, starterGui, coreType, enabled)
			end
			pcall(starterGui.SetCore, starterGui, "TopbarEnabled", true)
			userInputService.MouseIconEnabled = mouseIcon
			pcall(function()
				proximityPromptService.Enabled = promptsEnabled
			end)
			for _, hidden in hiddenSigns do
				if hidden.Parent then
					hidden.Enabled = true
				end
			end
		end)
	end

	local function muteMusic()
		local group = soundService:FindFirstChild("BackgroundMusic")
		if not MUTE_MUSIC or not group or not group:IsA("SoundGroup") then
			return
		end
		local volume = group.Volume
		tween(group, TweenInfo.new(0.5), { Volume = 0 })
		addCleanup(function()
			tween(group, TweenInfo.new(1), { Volume = volume })
		end)
	end

	local function getControls(): any
		local playerModule = player:FindFirstChild("PlayerScripts") and player.PlayerScripts:FindFirstChild("PlayerModule")
		if not playerModule then
			return nil
		end
		local success, controls = pcall(function()
			return (require(playerModule) :: any):GetControls()
		end)
		return if success then controls else nil
	end

	local function lockPlayer()
		local controls = getControls()
		if controls then
			pcall(controls.Disable, controls)
		end
		-- Nothing the player presses reaches the game (the trigger key still aborts).
		contextActionService:BindActionAtPriority("TrailerCinematicSink", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 50, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.Space)
		addCleanup(function()
			contextActionService:UnbindAction("TrailerCinematicSink")
			if controls then
				pcall(controls.Enable, controls)
			end
		end)
	end

	-- A light grade, bloom and a depth of field that follows each shot's subject. The game's own DoF steps aside meanwhile.
	local depthOfField: DepthOfFieldEffect? = nil
	local whipBlur: BlurEffect? = nil
	local function addPostEffects()
		local disabled: { PostEffect } = {}
		for _, effect in lighting:GetChildren() do
			if effect:IsA("DepthOfFieldEffect") and effect.Enabled then
				effect.Enabled = false
				table.insert(disabled, effect)
			end
		end

		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "TrailerGrade"
		grade.Contrast = 0.08
		grade.Saturation = 0.14
		grade.TintColor = Color3.fromRGB(255, 249, 238)
		grade.Parent = lighting

		local bloom = Instance.new("BloomEffect")
		bloom.Name = "TrailerBloom"
		bloom.Intensity = 0.35
		bloom.Size = 28
		bloom.Threshold = 1.6
		bloom.Parent = lighting

		local dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "TrailerDepthOfField"
		dof.FarIntensity = 0.28
		dof.NearIntensity = 0.12
		dof.InFocusRadius = 12
		dof.FocusDistance = 20
		dof.Parent = lighting
		depthOfField = dof

		local blur = Instance.new("BlurEffect")
		blur.Name = "TrailerWhipBlur"
		blur.Size = 0
		blur.Parent = lighting
		whipBlur = blur

		addCleanup(function()
			for _, effect in { grade, bloom, dof, blur } :: { Instance } do
				effect:Destroy()
			end
			depthOfField, whipBlur = nil, nil
			for _, effect in disabled do
				if effect.Parent then
					effect.Enabled = true
				end
			end
		end)
	end

	--// Pen montage ---------------------------------------------------------------------------

	local PEN_SINK_SECONDS = 0.22
	local PEN_SINK_DEPTH = 6
	local PEN_RISE_SECONDS = 0.42
	local PEN_SPREAD = 0.3 -- seconds the sweep around the pen takes

	local function sweepOf(position: Vector3, startAngle: number): number
		local angle = math.atan2(position.Z - penCenter.Z, position.X - penCenter.X) - startAngle
		return (angle % (2 * math.pi)) / (2 * math.pi)
	end

	local function isVisual(instance: Instance): boolean
		return instance:IsA("Decal") or instance:IsA("Texture")
	end

	local function isToggle(instance: Instance): boolean
		return instance:IsA("Light") or instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") or instance:IsA("LayerCollector")
	end

	-- The real fence goes invisible locally (the server keeps it); a copy of it is what sinks on screen.
	local function hideRealFence(): Model?
		local fence = plot and plot:FindFirstChild("PlotFence1")
		if not fence or not fence:IsA("Model") then
			return nil
		end
		fence.Archivable = true
		local copy = fence:Clone()
		for _, descendant in fence:GetDescendants() do
			if descendant:IsA("BasePart") or isVisual(descendant) then
				hiddenFence[descendant] = (descendant :: any).Transparency
				;(descendant :: any).Transparency = 1
			elseif isToggle(descendant) then
				hiddenFence[descendant] = (descendant :: any).Enabled
				;(descendant :: any).Enabled = false
			end
		end
		return copy
	end

	local function restoreRealFence()
		for instance, value in hiddenFence do
			if instance.Parent then
				if instance:IsA("BasePart") or isVisual(instance) then
					(instance :: any).Transparency = value
				else
					(instance :: any).Enabled = value
				end
			end
		end
		table.clear(hiddenFence)
		if penClone then
			penClone:Destroy()
			penClone = nil
		end
	end

	local function prepareLocalModel(model: Model)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
			end
		end
	end

	local function sinkAway(model: Model, startAngle: number)
		prepareLocalModel(model)
		model.Parent = workspace
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				local info = TweenInfo.new(PEN_SINK_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, sweepOf(descendant.Position, startAngle) * PEN_SPREAD * 0.5)
				tween(descendant, info, { CFrame = descendant.CFrame - UP * PEN_SINK_DEPTH, Transparency = 1 })
			elseif isVisual(descendant) then
				tween(descendant, TweenInfo.new(PEN_SINK_SECONDS), { Transparency = 1 })
			elseif isToggle(descendant) then
				(descendant :: any).Enabled = false
			end
		end
		debris:AddItem(model, PEN_SINK_SECONDS + PEN_SPREAD + 0.1)
	end

	local function riseUp(model: Model, startAngle: number)
		prepareLocalModel(model)
		local looks: { [BasePart]: { cframe: CFrame, transparency: number } } = {}
		local visuals: { [Instance]: number } = {}
		local toggles: { [Instance]: boolean } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				looks[descendant] = { cframe = descendant.CFrame, transparency = descendant.Transparency }
				descendant.Transparency = 1
				descendant.CFrame = descendant.CFrame - UP * PEN_SINK_DEPTH
			elseif isVisual(descendant) then
				visuals[descendant] = (descendant :: any).Transparency
				;(descendant :: any).Transparency = 1
			elseif isToggle(descendant) then
				toggles[descendant] = (descendant :: any).Enabled
				;(descendant :: any).Enabled = false
			end
		end
		model.Parent = workspace

		for part, look in looks do
			local info = TweenInfo.new(PEN_RISE_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, sweepOf(look.cframe.Position, startAngle) * PEN_SPREAD)
			tween(part, info, { CFrame = look.cframe, Transparency = look.transparency })
		end
		for visual, transparency in visuals do
			tween(visual, TweenInfo.new(PEN_RISE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, PEN_SPREAD * 0.5), { Transparency = transparency })
		end
		task.delay(PEN_RISE_SECONDS + PEN_SPREAD, function()
			for toggle, enabled in toggles do
				if toggle.Parent then
					(toggle :: any).Enabled = enabled
				end
			end
		end)

		-- Puffs and rising pops as it goes up around the pen.
		for index = 0, 5 do
			local angle = startAngle + index / 6 * math.pi * 2
			task.delay(index / 6 * PEN_SPREAD, function()
				poofAt(penCenter + around(angle) * penSize * 0.48 + UP * 1.5)
				playSound("Pop", 0.95 + index * 0.07, 0.8)
			end)
		end
	end

	-- Swaps the fence to this PenStyleData tier, old one sinking and new one popping up, and names it.
	local function showPen(tier: number)
		local pens = replicatedStorage:FindFirstChild(PENS_FOLDER_NAME)
		local style = pens and pens:FindFirstChild(tostring(tier))
		if not style or not style:IsA("Model") then
			return
		end
		local from = camera.CFrame.Position
		local startAngle = math.atan2(from.Z - penCenter.Z, from.X - penCenter.X)

		local old: Model? = penClone
		if not old then
			old = hideRealFence()
		end
		if old then
			sinkAway(old, startAngle)
		end

		local new = style:Clone()
		penClone = new
		riseUp(new, startAngle)
		local name = new:GetAttribute("PenName")
		caption(string.upper(if type(name) == "string" then name else "New Pen"), 0.62)
		punch(-4)
		task.delay(PEN_SPREAD + PEN_RISE_SECONDS * 0.6, function()
			playSound("UnlockedSheep", 1, 0.7)
		end)
	end

	--// Shear shop ------------------------------------------------------------------------------

	local function openShop()
		local success, windowsManager = pcall(require, clientModules:WaitForChild("WindowsManager"))
		local window = success and windowsManager.get("ShearShop")
		local shopGui = playerGui:FindFirstChild("Shop")
		if not window or not shopGui then
			warn("TrailerCinematic: the ShearShop window isn't registered; the shop shot is skipped.")
			return
		end
		allowedNow.Shop = true
		window.open()
		shopWindow = window
		local scroll = shopGui:FindFirstChild("Main") and shopGui.Main:FindFirstChild("ScrollingFrame")
		if scroll and scroll:IsA("ScrollingFrame") then
			scroll.CanvasPosition = Vector2.zero
			shopScroll = scroll
		end
	end

	local function scrollShop(seconds: number)
		local scroll = shopScroll
		if not scroll then
			return
		end
		local maxX = math.max(scroll.AbsoluteCanvasSize.X - scroll.AbsoluteWindowSize.X, 0)
		local maxY = math.max(scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y, 0)
		tween(scroll, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CanvasPosition = Vector2.new(maxX, maxY) })
	end

	local function closeShop()
		if shopWindow and shopWindow.isOpen() then
			shopWindow.close()
		end
		shopWindow, shopScroll = nil, nil
		allowedNow.Shop = nil
	end

	--// Health watching (so the camera hits land on the real damage) ---------------------------

	local function watchHealth(model: Model?, attribute: string, onKill: () -> ())
		if not model then
			return
		end
		local last = model:GetAttribute(attribute)
		local connection
		connection = model:GetAttributeChangedSignal(attribute):Connect(function()
			local health = model:GetAttribute(attribute)
			if not running or type(health) ~= "number" then
				connection:Disconnect()
				return
			end
			if type(last) == "number" and health < last then
				if health <= 0 then
					connection:Disconnect()
					onKill()
				else
					punch(-2.5)
					shake(0.18)
				end
			end
			last = health
		end)
		addCleanup(function()
			connection:Disconnect()
		end)
	end

	local function onSheepShorn()
		punch(-7)
		shake(0.35)
		flash(0.25)
	end

	--// The trailer -------------------------------------------------------------------------------

	type Shot = {
		from: number,
		to: number,
		enter: "cut" | "whip" | "flash",
		camera: (alpha: number, elapsed: number) -> (CFrame, number),
		focus: (() -> Vector3)?,
	}
	type Cue = { at: number, run: () -> () }
	-- While open, the farmer swings at `getAt` whenever a shear is held, it's within `reach` and SWING_GAP has passed.
	type SwingWindow = { from: number, to: number, getAt: () -> Vector3, reach: number, left: number }

	local shots: { Shot } = {}
	local cues: { Cue } = {}
	local swingWindows: { SwingWindow } = {}
	local lastSwingAt = 0
	local TOTAL = 0

	local function shot(from: number, to: number, enter: "cut" | "whip" | "flash", cameraFn: (number, number) -> (CFrame, number), focus: (() -> Vector3)?)
		table.insert(shots, { from = from, to = to, enter = enter, camera = cameraFn, focus = focus })
	end

	local function at(time: number, run: () -> ())
		table.insert(cues, { at = time, run = run })
	end

	local function swingWindow(from: number, to: number, count: number, reach: number, getAt: () -> Vector3)
		table.insert(swingWindows, { from = from, to = to, getAt = getAt, reach = reach, left = count })
	end

	local function updateSwings(elapsed: number)
		if os.clock() - lastSwingAt < SWING_GAP or os.clock() - placedAt < TELEPORT_SETTLE then
			return
		end
		for _, window in swingWindows do
			if elapsed >= window.from and elapsed < window.to and window.left > 0 then
				local character = player.Character
				local root = getCharacterRoot()
				local goal = window.getAt()
				if root and character and character:FindFirstChildOfClass("Tool") and flat(goal - root.Position).Magnitude <= window.reach then
					window.left -= 1
					lastSwingAt = os.clock()
					swing(goal)
				end
				return
			end
		end
	end

	local function buildTimeline()
		table.clear(shots)
		table.clear(cues)
		table.clear(swingWindows)
		lastSwingAt = 0
		local frontAngle = angleOf(penFront)

		--// 1. Every farm starts small (0 - 4.2) ---------------------------------------------------
		-- A wide, low push into the empty wooden pen while three basic sheep poof in; the farmer waits in the foreground.
		shot(0, 1.4, "cut", function(alpha)
			local push = ease(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			local fromEye = penCenter + penFront * penSize * 0.95 + penRight * penSize * 0.4 + UP * 5
			local toEye = penCenter + penFront * penSize * 0.78 + penRight * penSize * 0.3 + UP * 4
			return CFrame.lookAt(fromEye:Lerp(toEye, push), penCenter + penFront * penSize * 0.12 + UP * 1.5), 60
		end, function()
			return penCenter
		end)
		at(0.05, function()
			caption("EVERY FARM STARTS SMALL", 1.2, Color3.new(1, 1, 1))
		end)
		for index, sheepType in START_SHEEP do
			at(0.25 + (index - 1) * 0.3, function()
				invoke("Spawn", { sheepType })
			end)
		end

		-- Over the shoulder as the farmer walks up to the nearest sheep.
		at(1.4, function()
			target = nearestSheep(playerPosition())
			lastTargetPosition = nil
			watchHealth(target, "ShearHealth", onSheepShorn)
			chaseStop = 4.5 -- room between them on screen, still well inside the shear's range
			chase = targetPosition
		end)
		shot(1.4, 2.25, "cut", function(alpha)
			local character = track("player", playerPosition(), 10)
			local sheep = track("sheep", targetPosition(), 6)
			local direction = unitFlat(sheep - character)
			local eye = character - direction * 9.5 + sideOf(direction) * 3.2 + UP * 4.2
			return CFrame.lookAt(eye, character:Lerp(sheep, 0.6) + UP * 0.5), 62 - 4 * alpha
		end, targetPosition)

		-- Low beside the farmer and the sheep, wide enough to see the whole sheep, through the snips until it's bare.
		at(2.25, function()
			local sheepAt = targetPosition()
			if (flat(sheepAt - playerPosition())).Magnitude > 5.5 then
				placeCharacter(sheepAt - unitFlat(sheepAt - playerPosition()) * 4, sheepAt)
			end
		end)
		shot(2.25, 4.2, "cut", function(alpha)
			local character = track("player", playerPosition(), 10)
			local sheep = track("sheep", targetPosition(), 8)
			local direction = pairDirection(character, sheep)
			local middle = character:Lerp(sheep, 0.6)
			local eye = middle + sideOf(direction) * (13 - 1.5 * ease(alpha)) - direction * 2 + UP * 2.6
			return CFrame.lookAt(aboveGround(eye, groundY, 2.2), middle + UP * 0.2), 60
		end, targetPosition)
		swingWindow(2.32, 4.06, 5, 6.5, targetPosition) -- a basic sheep goes bare on the third snip, before the whip

		--// 2. Shearing montage: three whip-panned cuts, a better shear and a fancier sheep each time (4.2 - 7.35) -----
		local cutLength = 1.05
		local cutLooks = {
			-- Low dutch angle from the side, drifting round.
			function(alpha: number, character: Vector3, sheep: Vector3, direction: Vector3): (CFrame, number)
				local middle = character:Lerp(sheep, 0.5)
				local angle = angleOf(sideOf(direction)) + math.rad(14) * alpha
				local eye = aboveGround(middle + around(angle) * 12 + UP * 2, groundY, 2)
				return CFrame.lookAt(eye, middle + UP * 0.5) * CFrame.Angles(0, 0, math.rad(9)), 60
			end,
			-- High and looking down, slowly turning.
			function(alpha: number, character: Vector3, sheep: Vector3, direction: Vector3): (CFrame, number)
				local middle = character:Lerp(sheep, 0.5)
				local angle = angleOf(-direction) + math.rad(25) * alpha
				return CFrame.lookAt(middle + around(angle) * 8 + UP * 15, middle), 60
			end,
			-- From behind the sheep towards the farmer, high enough to see over it, pushing in.
			function(alpha: number, character: Vector3, sheep: Vector3, direction: Vector3): (CFrame, number)
				local eye = aboveGround(sheep + direction * 10 + sideOf(direction) * 3 + UP * 3, groundY, 2.5)
				return CFrame.lookAt(eye, character:Lerp(sheep, 0.35) + UP * 0.4), 58 - 6 * ease(alpha)
			end,
		}
		for index, step in MONTAGE do
			local from = 4.2 + (index - 1) * cutLength
			-- The sheep poofs into the pen a beat early; the shear swap waits for the whip so it hides in the blur.
			local sheepId: number? = nil
			at(from - 0.5, function()
				local ids = invoke("Spawn", { step.sheep })
				sheepId = if type(ids) == "table" then ids[1] else nil
			end)
			at(from - WHIP_SECONDS, function()
				chase = nil
				local sheep = findSheep(sheepId, 0.4)
				if not running then
					return
				end
				task.spawn(function()
					invoke("Arm", step.shear, sheepId, MONTAGE_SWINGS)
					equipShear(step.shear, 0.6)
				end)
				if sheep then
					target = sheep
					lastTargetPosition = nil
					watchHealth(sheep, "ShearHealth", onSheepShorn)
					-- On the pen-centre side of the sheep, so the farmer never lands on the fence.
					local sheepAt = targetPosition()
					placeCharacter(sheepAt + unitFlat(penCenter - sheepAt) * 4, sheepAt)
				end
				chaseStop = 4.5
				chase = targetPosition
			end)
			at(from + 0.05, function()
				caption(step.caption, cutLength - 0.15)
			end)
			shot(from, from + cutLength, "whip", function(alpha)
				local character = track("player", playerPosition(), 10)
				local sheep = track("sheep", targetPosition(), 8)
				return cutLooks[(index - 1) % #cutLooks + 1](alpha, character, sheep, pairDirection(character, sheep))
			end, targetPosition)
			swingWindow(from + 0.08, from + cutLength - 0.1, MONTAGE_SWINGS + 1, 6.5, targetPosition)
		end

		--// 3. Rebirth: the camera circles the farmer as rebirth after rebirth bursts (7.35 - 10.65) -----------------
		local rebirthStart = 4.2 + #MONTAGE * cutLength
		at(rebirthStart, function()
			chase = nil
			target = nil
			placeCharacter(penCenter + penFront * 2, penCenter + penFront * 10)
			invoke("ClearPen")
		end)
		shot(rebirthStart, rebirthStart + 3.3, "flash", function(alpha)
			local character = track("player", playerPosition(), 12)
			shotState.angle = shotState.angle or (frontAngle + 0.5)
			local angle = shotState.angle + math.rad(320) * (0.65 * alpha + 0.35 * ease(alpha))
			local eye = character + around(angle) * (10 - 2.6 * alpha) + UP * (1.2 + 3.6 * alpha)
			return CFrame.lookAt(eye, character + UP * 0.6), 62 - 9 * alpha
		end, playerPosition)
		local bursts = { 0.35, 1.1, 1.7, 2.2, 2.6, 2.93 } -- quickening
		for count, offset in bursts do
			at(rebirthStart + offset, function()
				local character = player.Character
				if character then
					local success, rebirthVfx = pcall(require, clientModules:WaitForChild("RebirthVFX"))
					if success then
						pcall(rebirthVfx.play, character)
					end
				end
				playSound("Rebirthed", 0.92 + count * 0.05)
				flash(0.35 + count * 0.04, Color3.fromRGB(255, 238, 170))
				punch(-6)
				shake(0.25 + count * 0.05)
				caption(`REBIRTH x{count}`, 0.5)
				if count == #bursts then
					local humanoid = getHumanoid()
					if humanoid then
						humanoid.Jump = true
					end
					invoke("Spawn", FANCY_SHEEP)
				end
			end)
		end

		--// 4. The pen levels up: wooden to picket, stone, marble and crystal (10.65 - 13.95) ------------------------
		local penStart = rebirthStart + 3.3
		-- The King is called now: its 4.5 s intro (it can't be hurt during it) is long over by the last scene.
		at(penStart, function()
			local channels = textChatService:FindFirstChild("TextChannels")
			local general = channels and channels:FindFirstChild("RBXGeneral")
			if not findKing() and general and general:IsA("TextChannel") then
				pcall(general.SendAsync, general, "/kingboss now")
			end
		end)
		shot(penStart, penStart + 3.3, "whip", function(alpha)
			shotState.angle = shotState.angle or (frontAngle + 0.45)
			local angle = shotState.angle - math.rad(50) * ease(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			-- Steep enough that the props around the plot drop out of the bottom of the frame.
			local eye = penCenter + around(angle) * penSize * (0.78 - 0.1 * alpha) + UP * penSize * 0.88
			return CFrame.lookAt(eye, penCenter - penFront * penSize * 0.05), 60
		end, function()
			return penCenter
		end)
		for index, tier in { 2, 3, 4, 5 } do
			at(penStart + 0.2 + (index - 1) * 0.7, function()
				showPen(tier)
			end)
		end

		--// 5. The shears, in the shop UI (13.95 - 16.55) ----------------------------------------------------------
		local shopStart = penStart + 3.3
		at(shopStart, function()
			openShop()
			pcall(player.RequestStreamAroundAsync, player, arenaPosition, 3)
		end)
		at(shopStart + 0.08, function()
			caption("UNLOCK NEW SHEARS", 1.4, Color3.new(1, 1, 1))
		end)
		at(shopStart + 0.4, function()
			scrollShop(1.75)
		end)
		at(shopStart + 2.32, function()
			closeShop()
			invoke("ArmKing", KING_SHEAR, KING_SWINGS)
		end)
		shot(shopStart, shopStart + 2.6, "flash", function(alpha)
			local character = playerPosition()
			local eye = character + penFront * (12 - 3 * alpha) + penRight * 3 + UP * (3.5 - 0.8 * alpha)
			return CFrame.lookAt(eye, character + UP * 0.5), 60
		end, playerPosition)

		--// 6. Shear the King Sheep: hero angle, side angle, then a crane as it bursts (16.55 - 19.9) ---------------
		local kingStart = shopStart + 2.6
		at(kingStart, function()
			king = findKing()
			local kingAt = kingPosition()
			if king then
				local _, size = king:GetBoundingBox()
				kingHeight = math.max(size.Y, 6)
				watchHealth(king, "Health", function()
					flash(0.6)
					punch(-11)
					shake(0.7)
				end)
			else
				warn("TrailerCinematic: the King Sheep didn't arrive (is a King already fighting, or BossArena missing?).")
			end
			arenaGroundY = groundAt(kingAt).Y
			local away = unitFlat(kingAt - arenaPosition, penFront)
			if (flat(kingAt - arenaPosition)).Magnitude < 2 then
				away = penFront
			end
			placeCharacter(kingAt - away * 11, kingAt)
			equipShear(KING_SHEAR, 0.6)
			chaseStop = 9
			chase = kingPosition
		end)
		at(kingStart + 0.1, function()
			caption("DEFEAT THE KING SHEEP", 1.5)
		end)
		shot(kingStart, kingStart + 1.1, "whip", function(alpha)
			local character = track("player", playerPosition(), 10)
			local boss = track("king", kingPosition(), 6)
			shotState.direction = shotState.direction or unitFlat(boss - character)
			local direction = shotState.direction
			local eye = character - direction * (7 - 1.6 * ease(alpha)) + sideOf(direction) * 3 + UP * 0.2
			return CFrame.lookAt(aboveGround(eye, arenaGroundY, 1), boss + UP * kingHeight * 0.3), 60 - 8 * ease(alpha)
		end, kingPosition)
		shot(kingStart + 1.1, kingStart + 1.9, "cut", function(alpha)
			local character = track("player", playerPosition(), 10)
			local boss = track("king", kingPosition(), 6)
			shotState.direction = shotState.direction or unitFlat(boss - character)
			local direction = shotState.direction
			local middle = character:Lerp(boss, 0.5)
			local reach = (flat(boss - character)).Magnitude
			local distance = math.max(reach * 0.9 + 8, kingHeight * 1.9) -- far enough that its huge body doesn't fill the frame
			local eye = middle - sideOf(direction) * distance + direction * (-2 + 4 * alpha) + UP * (2.5 + kingHeight * 0.15)
			return CFrame.lookAt(eye, middle + UP * kingHeight * 0.2), 55
		end, kingPosition)
		local function orbitKing(alpha: number, degrees: number, startRadius: number, endRadius: number, startRise: number, endRise: number): CFrame
			local boss = track("king", kingPosition(), 5)
			shotState.angle = shotState.angle or angleOf(unitFlat(playerPosition() - boss))
			local angle = shotState.angle + math.rad(degrees) * ease(alpha, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			local radius = kingHeight * (startRadius + (endRadius - startRadius) * alpha)
			local rise = kingHeight * (startRise + (endRise - startRise) * alpha)
			return CFrame.lookAt(boss + around(angle) * radius + UP * rise, boss + UP * kingHeight * 0.15)
		end
		shot(kingStart + 1.9, kingStart + 3.35, "cut", function(alpha)
			return orbitKing(alpha, 55, 1.7, 2.5, 0.35, 0.95), 58 + 6 * alpha
		end, kingPosition)
		-- Down on the fourth snip; its burst lands ~1.6 s later, right on the end card's flash.
		swingWindow(kingStart + 0.2, kingStart + 3.1, KING_SWINGS + 1, 16, kingPosition)

		--// End card (19.9 - 22.5) ------------------------------------------------------------------------------
		local endStart = kingStart + 3.35
		at(endStart, function()
			chase = nil
			flash(0.9)
			showEndCard()
		end)
		shot(endStart, endStart + 2.6, "cut", function(alpha)
			return orbitKing(alpha, 18, 2.6, 2.9, 1, 1.15), 64
		end, kingPosition)

		TOTAL = endStart + 2.6
		table.sort(cues, function(a: Cue, b: Cue): boolean
			return a.at < b.at
		end)
	end

	--// Render loop ---------------------------------------------------------------------------------

	local nextCue = 1
	local shotIndex = 0

	local function render(deltaTime: number)
		frameDt = math.min(deltaTime, 0.1)
		local elapsed = os.clock() - startClock

		while nextCue <= #cues and cues[nextCue].at <= elapsed do
			local cue = cues[nextCue]
			nextCue += 1
			task.spawn(function()
				if running then
					local success, err = pcall(cue.run)
					if not success then
						warn(`TrailerCinematic: cue at {cue.at}s failed: {err}`)
					end
				end
			end)
		end
		updateChase()
		updateSwings(elapsed)

		local index = math.max(shotIndex, 1)
		while index < #shots and elapsed >= shots[index].to do
			index += 1
		end
		local current = shots[index]
		if not current then
			return
		end
		if index ~= shotIndex then
			shotIndex = index
			table.clear(tracked)
			table.clear(shotState)
			if current.enter == "flash" then
				flash(0.85)
			end
		end

		local length = current.to - current.from
		local inShot = math.max(elapsed - current.from, 0)
		local cframe, fov = current.camera(math.clamp(inShot / length, 0, 1), inShot)

		-- Whip pan: the outgoing shot swings away and the incoming one swings in from the other side, under a blur.
		local whip, blurAmount = 0, 0
		local upcoming = shots[index + 1]
		if upcoming and upcoming.enter == "whip" and current.to - elapsed < WHIP_SECONDS then
			local k = 1 - (current.to - elapsed) / WHIP_SECONDS
			whip, blurAmount = k * k * WHIP_DEGREES, k
		end
		if current.enter == "whip" and inShot < WHIP_SECONDS then
			local k = 1 - inShot / WHIP_SECONDS
			whip, blurAmount = -k * k * WHIP_DEGREES, math.max(blurAmount, k)
		end

		local now = os.clock()
		local sway = math.rad(HANDHELD_DEGREES)
		local handheld = CFrame.Angles(math.noise(now * 0.55, 1.3) * sway, math.noise(now * 0.55, 7.1) * sway, math.noise(now * 0.4, 3.7) * sway * 0.5)
		local shakeAngle = math.rad(1.6) * trauma * trauma
		local shaken = CFrame.Angles(math.noise(now * 22, 11) * shakeAngle, math.noise(now * 22, 23) * shakeAngle, math.noise(now * 22, 37) * shakeAngle)
		trauma = math.max(trauma - frameDt * 1.8, 0)
		fovPunch *= math.exp(-frameDt * 9)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cframe * CFrame.Angles(0, math.rad(whip), 0) * handheld * shaken
		camera.FieldOfView = math.clamp(fov + fovPunch, 20, 100)
		if whipBlur then
			whipBlur.Size = blurAmount * WHIP_BLUR
		end
		if depthOfField and current.focus then
			depthOfField.FocusDistance = math.clamp((current.focus() - camera.CFrame.Position).Magnitude, 2, 200)
		end
	end

	--// Start / stop ----------------------------------------------------------------------------------

	local function findPlot(): Instance?
		for _, candidate in plotsFolder:GetChildren() do
			if candidate:GetAttribute("Owner") == player.UserId then
				return candidate
			end
		end
		return nil
	end

	local function readPen(): boolean
		plot = findPlot()
		local area = plot and plot:FindFirstChild("SheepArea")
		if not area or not area:IsA("BasePart") then
			warn("TrailerCinematic: couldn't find your plot's SheepArea.")
			return false
		end
		penSize = math.max(area.Size.X, area.Size.Z)
		local ground = groundAt(area.Position)
		groundY = ground.Y
		penCenter = Vector3.new(area.Position.X, groundY, area.Position.Z)
		local spawnArea = plot:FindFirstChild("SpawnArea")
		penFront = unitFlat(if spawnArea and spawnArea:IsA("BasePart") then spawnArea.Position - penCenter else area.CFrame.LookVector, Vector3.new(0, 0, -1))
		penRight = sideOf(penFront)
		return true
	end

	local savedCamera: { cframe: CFrame, fov: number, subject: Instance?, cameraType: Enum.CameraType }? = nil
	local savedSpot: CFrame? = nil -- where the farmer stood when the trailer started; put back afterwards

	local function teardown()
		if not running then
			return
		end
		running = false
		runService:UnbindFromRenderStep(RENDER_NAME)
		chase = nil
		target, king = nil, nil
		closeShop()
		if activeCaption then
			activeCaption:Destroy()
			activeCaption = nil
		end

		fadeFrame.BackgroundTransparency = 0
		endCard.Visible = false
		if subtitlePulse then
			subtitlePulse:Cancel()
			subtitlePulse = nil
		end
		setLetterbox(false, 0)
		restoreRealFence()
		invoke("Restore")
		-- The King's reward popup opened (hidden) during the trailer; its rewards were just undone with the save.
		pcall(function()
			local popup = require(clientModules:FindFirstChild("KingSheepRewardPopup") :: ModuleScript) :: any
			if popup.isOpen() then
				popup.close()
			end
		end)
		task.wait(RESTORE_HOLD_SECONDS)

		for index = #cleanups, 1, -1 do
			pcall(cleanups[index])
		end
		table.clear(cleanups)

		local humanoid = getHumanoid()
		if savedSpot and player.Character then
			player.Character:PivotTo(savedSpot)
		end
		if savedCamera then
			camera.FieldOfView = savedCamera.fov
			camera.CameraSubject = if savedCamera.subject and savedCamera.subject.Parent then savedCamera.subject else humanoid
			camera.CameraType = Enum.CameraType.Custom
		end
		fade(false, 0.6).Completed:Wait()
		overlay.Enabled = false
		print("TrailerCinematic: done, your save has been put back.")
	end

	local function play()
		if running then
			return
		end
		running, aborted = true, false
		camera = workspace.CurrentCamera
		savedCamera = { cframe = camera.CFrame, fov = camera.FieldOfView, subject = camera.CameraSubject, cameraType = camera.CameraType }
		local startRoot = getCharacterRoot()
		savedSpot = if startRoot then startRoot.CFrame else nil

		-- Black first, so the staging never shows on the recording.
		overlay.Enabled = true
		fadeFrame.BackgroundTransparency = 0
		flashFrame.BackgroundTransparency = 1
		endCard.Visible = false
		endCard.BackgroundTransparency = 1
		setTextTransparency(endTitle, 1, TweenInfo.new(0))
		setTextTransparency(endSubtitle, 1, TweenInfo.new(0))
		prepLabel.TextTransparency = 0
		camera.CameraType = Enum.CameraType.Scriptable

		local success, err = pcall(function()
			if not readPen() then
				error("no plot", 0)
			end
			hideGameUi()
			muteMusic()
			lockPlayer()
			local info = invoke("Prepare")
			if not info then
				error("the server couldn't stage the save", 0)
			end
			arenaPosition = if typeof(info.arena) == "Vector3" then info.arena else penCenter
			arenaGroundY = arenaPosition.Y

			placeCharacter(penCenter + penFront * penSize * 0.32, penCenter)
			pcall(player.RequestStreamAroundAsync, player, penCenter, 2)
			equipShear(DEFAULT_SHEAR, 3)
			addPostEffects()
			buildTimeline()
		end)
		if not success then
			warn(`TrailerCinematic: couldn't start: {err}`)
			teardown()
			return
		end

		task.wait(PREP_SETTLE_SECONDS - 0.8)
		prepLabel.TextTransparency = 1
		task.wait(0.8)
		if aborted then
			teardown()
			return
		end

		nextCue, shotIndex = 1, 0
		fovPunch, trauma = 0, 0
		startClock = os.clock()
		runService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, render)
		fade(false, 0.7)
		setLetterbox(true, 0.6)

		while running and not aborted and os.clock() - startClock < TOTAL do
			task.wait()
		end
		if not aborted then
			fade(true, 0.6).Completed:Wait()
		end
		teardown()
	end

	local function onTrigger()
		if running then
			aborted = true
		else
			task.spawn(play)
		end
	end

	-- Not gated on gameProcessed (Studio can flag function keys as processed); only skipped while typing in a box.
	userInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == TRIGGER_KEY and not userInputService:GetFocusedTextBox() then
			onTrigger()
		end
	end)

	local command = Instance.new("TextChatCommand")
	command.Name = "TrailerCinematicCommand"
	command.PrimaryAlias = CHAT_COMMAND
	command.Triggered:Connect(function(source: TextSource)
		if source.UserId == player.UserId then
			onTrigger()
		end
	end)
	command.Parent = textChatService

	print(`TrailerCinematic: ready. Press {TRIGGER_KEY.Name} or chat {CHAT_COMMAND} to roll the trailer (again to abort).`)
end

if runService:IsServer() then
	runServer()
else
	task.spawn(runClient)
end

return TrailerCinematic
