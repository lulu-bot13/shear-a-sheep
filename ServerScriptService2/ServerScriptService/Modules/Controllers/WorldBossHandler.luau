--!strict

--[[
	King Sheep world boss: rolled at Clear spells and Nights (likelier with Server Luck), warned 30 s ahead, then wanders the
	plaza arena for everyone to shear. Pays out by damage share and progression; /kingboss [now|end] for admins. Tuning in WorldBossData.

	Location: ServerScriptService.Modules.Controllers.WorldBossHandler
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)
local MonetizationData = require(replicatedStorage.Shared.Constants.MonetizationData)
local WoolData = require(replicatedStorage.Shared.Constants.WoolData)
local AdminCommands = require(script.Parent.Parent.Utils.AdminCommands)
local MutationData = require(script.Parent.Parent.Constants.MutationData)
local PrestigeData = require(script.Parent.Parent.Constants.PrestigeData)
local RebirthData = require(script.Parent.Parent.Constants.RebirthData)
local SheepData = require(script.Parent.Parent.Constants.SheepData)
local SheepSizeData = require(script.Parent.Parent.Constants.SheepSizeData)
local UpgradeData = require(script.Parent.Parent.Constants.UpgradeData)
local WeatherData = require(script.Parent.Parent.Constants.WeatherData)
local WorldBossData = require(script.Parent.Parent.Constants.WorldBossData)
local Analytics = require(script.Parent.Analytics)
local AnnouncementHandler = require(script.Parent.AnnouncementHandler)
local GamePassService = require(script.Parent.GamePassService)
local GemHandler = require(script.Parent.GemHandler)
local MonetizationHandler = require(script.Parent.MonetizationHandler)
local PlayerDataHandler = require(script.Parent.PlayerDataHandler)
local PlotHandler = require(script.Parent.PlotHandler)
local PodiumBonusHandler = require(script.Parent.PodiumBonusHandler)
local SheepHandler = require(script.Parent.SheepHandler)
local SheepWanderHandler = require(script.Parent.SheepWanderHandler)
local WeatherHandler = require(script.Parent.WeatherHandler)

--// Instances
local assets = replicatedStorage:WaitForChild("Assets")
local animationsFolder = assets:FindFirstChild("Animations")
local uiFolder = assets:FindFirstChild("UI")
local modelsFolder = assets:FindFirstChild("Models")
local walkAnimation = (if animationsFolder then animationsFolder:FindFirstChild("SheepWalking") else nil) :: Animation?
local healthBarTemplate = (if uiFolder then uiFolder:FindFirstChild("BossHealthBar") else nil) :: BillboardGui?
local sheepModels = if modelsFolder then modelsFolder:FindFirstChild("Sheeps") else nil

--// Configs
local STATE_ATTRIBUTE = "WorldBossState"
local AT_ATTRIBUTE = "WorldBossAt"
local SERVER_LUCK_ATTRIBUTE = "ServerLuckEndsAt"
local FRIEND_BOOST_ATTRIBUTE = "FriendBoost" -- FriendBoostHandler's wool multiplier, as ShearHandler reads it
local SCHEDULE_SOURCE = "KingSheep"
local EVENT_NAME = "King Sheep"
local COLLISION_GROUP = "Sheep" -- players walk through it like any sheep; only its root collides
local GROUND_RAY_HEIGHT = 40
local BAR_HEIGHT = 2 -- studs the health bar floats over its head
local STOMP_JUMP_LEAD = 0.45 -- seconds before the stomp lands that it hops
local KILL_FLASH_COLOR = Color3.fromRGB(255, 213, 74)
local KILL_FLASH_PULSES = 3

export type State = "None" | "Pending" | "Active"

type Contribution = { damage: number, hits: number }

type Fight = {
	boss: Model,
	root: BasePart,
	humanoid: Humanoid,
	torso: BasePart?,
	torsoSize: Vector3,
	woolColor: Color3,
	spawnPosition: Vector3,
	health: number,
	maxHealth: number,
	totalDamage: number, -- every hit's damage, including players who have since left
	contributions: { [Player]: Contribution }, -- kept for leavers too, so they still count towards the split
	vulnerableAt: number, -- os.clock() the intro ends
	timeout: thread?,
}

-- What ShearHandler sends the client for a hit (the same shape as its own hits).
export type Hit = {
	sheep: Model?,
	position: Vector3,
	damage: number,
	color: Color3,
	flashColor: Color3?,
	flashPulses: number?,
}

-- The exact numbers one rewarded player's popup shows (WorldBossEffect "Reward").
export type Reward = {
	damage: number,
	share: number, -- of all the damage dealt, 0-1
	rank: number,
	shearers: number, -- players rewarded
	wool: number,
	luck: number,
	gems: number,
	woolBonus: number, -- the player's own wool multipliers in it (Prestige, passes, podium, friends, More Wool)
	luckBonus: number,
	sheepName: string?,
	mutation: string?,
	mutationColor: Color3?,
}

type Ranked = { player: Player, damage: number, share: number }

--// State
local state: State = "None"
local fight: Fight? = nil
local pendingThread: thread? = nil
local lastEndedAt = -math.huge
local rollRound = 0 -- bumped on every weather change, so a Night's delayed roll doesn't outlive it
local random = Random.new()

local WorldBossHandler = {}

WorldBossHandler.ATTRIBUTE = WorldBossData.Attribute

--// Helpers -------------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function getNumber(player: Player, key: string): number
	local value = PlayerDataHandler.get(player, key)
	return if type(value) == "number" then value else 0
end

local function setState(newState: State, at: number?)
	state = newState
	workspace:SetAttribute(STATE_ATTRIBUTE, newState)
	workspace:SetAttribute(AT_ATTRIBUTE, at)
end

-- Wool for the player's next rebirth (their last one's cost once they're maxed).
local function getRebirthCost(player: Player): number
	return RebirthData.getWoolCost(getNumber(player, "Rebirths"))
		or RebirthData.getWoolCost(RebirthData.MAX_REBIRTHS - 1)
		or RebirthData.FIRST_COST
end

local function isServerLucky(): boolean
	local endsAt = workspace:GetAttribute(SERVER_LUCK_ATTRIBUTE)
	return type(endsAt) == "number" and endsAt > now()
end

local function getSpawnPart(): BasePart?
	for _, part in collectionService:GetTagged(WorldBossData.SpawnTag) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			return part
		end
	end
	return nil
end

-- The floor under `point`, ignoring the boss, players and non-collidable parts.
local function findGround(point: Vector3): Vector3
	local ignore: { Instance } = {}
	if fight then
		table.insert(ignore, fight.boss)
	end
	for _, player in players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = ignore

	local result = workspace:Raycast(point + Vector3.new(0, GROUND_RAY_HEIGHT, 0), Vector3.new(0, -GROUND_RAY_HEIGHT * 2, 0), params)
	return if result then result.Position else point
end

local function fireEffect(kind: string, data: { [string]: any })
	network.fireAllClients(network.RemoteEvents.WorldBossEffect, kind, data)
end

-- The torso shrinks and turns pink as the boss is shorn, like a normal sheep (KingCapeClient follows it).
local function updateWool(current: Fight)
	local torso = current.torso
	if not torso then
		return
	end
	local shorn = 1 - math.clamp(current.health / current.maxHealth, 0, 1)
	torso.Size = current.torsoSize * Vector3.new(1, 1, 1):Lerp(WoolData.ShornTorsoScale, shorn)
	torso.Color = current.woolColor:Lerp(WoolData.ShornColor, shorn * WoolData.ShornColorBlend)
end

-- Base health plus every player's shear damage times SwingsPerPlayer (the strongest MaxScaledPlayers count).
local function getMaxHealth(): number
	local damages: { number } = {}
	for _, player in players:GetPlayers() do
		local damage = player:GetAttribute("ShearDamage")
		table.insert(damages, if type(damage) == "number" and damage > 0 then damage else WorldBossData.DefaultShearDamage)
	end
	table.sort(damages, function(a: number, b: number): boolean
		return a > b
	end)

	local health = WorldBossData.BaseHealth
	for index = 1, math.min(#damages, WorldBossData.MaxScaledPlayers) do
		health += damages[index] * WorldBossData.SwingsPerPlayer
	end
	return math.floor(health)
end

--// Spawning ---------------------------------------------------------------------

local function playAnimations(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local walk = if walkAnimation then animator:LoadAnimation(walkAnimation) else nil
	local idle: AnimationTrack? = nil
	local idleId = SheepData.IdleAnimations.Adult
	if idleId ~= "" then
		local animation = Instance.new("Animation")
		animation.AnimationId = idleId
		idle = animator:LoadAnimation(animation)
	end
	if walk then
		walk.Looped = true
	end
	if idle then
		idle.Looped = true
		idle.Priority = Enum.AnimationPriority.Idle
		idle:Play()
	end

	humanoid.Running:Connect(function(speed: number)
		local walking = speed > 0.1
		if walk and walking ~= walk.IsPlaying then
			if walking then
				walk:Play()
			else
				walk:Stop()
			end
		end
		if idle and walking == idle.IsPlaying then
			if walking then
				idle:Stop(0.2)
			else
				idle:Play(0.2)
			end
		end
	end)
end

-- Clones and scales the King Sheep onto the arena's spawn; nil (with a warning) if Studio is missing a piece.
local function buildFight(): Fight?
	local template = if sheepModels then sheepModels:FindFirstChild(WorldBossData.ModelName) else nil
	local spawnPart = getSpawnPart()
	if not template or not template:IsA("Model") then
		warn(`WorldBossHandler: Assets.Models.Sheeps.{WorldBossData.ModelName} is missing; build it in Studio.`)
		return nil
	elseif not spawnPart then
		warn(`WorldBossHandler: no part tagged {WorldBossData.SpawnTag} in the workspace; build it in Studio.`)
		return nil
	end

	local boss = template:Clone()
	local root = boss:FindFirstChild("HumanoidRootPart")
	local humanoid = boss:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		warn("WorldBossHandler: the King Sheep model needs a HumanoidRootPart and a Humanoid.")
		boss:Destroy()
		return nil
	end

	boss:ScaleTo(boss:GetScale() * WorldBossData.Scale)
	for _, descendant in boss:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = COLLISION_GROUP
			descendant.CanCollide = descendant == root
		end
	end

	local torso = boss:FindFirstChild("Torso")
	local woolPart = if torso and torso:IsA("BasePart") then torso else nil
	if woolPart then
		woolPart:SetAttribute("WoolBaseSize", woolPart.Size) -- KingCapeClient settles the cape as it shrinks
	end

	local maxHealth = getMaxHealth()
	boss:SetAttribute(WorldBossData.Attribute, true)
	boss:SetAttribute("Health", maxHealth)
	boss:SetAttribute("MaxHealth", maxHealth)
	boss:SetAttribute("HitRadius", WorldBossData.HitRadius)

	-- Feet on the ground at the spawn, facing a random way.
	local spawnPosition = findGround(spawnPart.Position)
	local boxCFrame, boxSize = boss:GetBoundingBox()
	local footDepth = boss:GetPivot().Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
	boss:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, footDepth, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0))

	if healthBarTemplate then
		local bar = healthBarTemplate:Clone()
		bar.Adornee = root
		bar.StudsOffsetWorldSpace = Vector3.new(0, boxSize.Y - footDepth + BAR_HEIGHT, 0)
		bar.Parent = root
	else
		warn("WorldBossHandler: Assets.UI.BossHealthBar is missing; build it in Studio.")
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid.WalkSpeed = WorldBossData.WalkSpeed

	collectionService:AddTag(boss, WorldBossData.Tag)
	boss.Parent = workspace
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil) -- the server walks it
	end)
	playAnimations(humanoid)

	return {
		boss = boss,
		root = root,
		humanoid = humanoid,
		torso = woolPart,
		torsoSize = if woolPart then woolPart.Size else Vector3.one,
		woolColor = if woolPart then woolPart.Color else Color3.new(1, 1, 1),
		spawnPosition = spawnPosition,
		health = maxHealth,
		maxHealth = maxHealth,
		totalDamage = 0,
		contributions = {},
		vulnerableAt = os.clock() + WorldBossData.IntroSeconds,
		timeout = nil,
	}
end

--// Behaviour ---------------------------------------------------------------------

local function isCurrent(current: Fight): boolean
	return fight == current and current.health > 0
end

local function isVulnerable(current: Fight): boolean
	return current.health > 0 and os.clock() >= current.vulnerableAt
end

local function walk(current: Fight)
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = WorldBossData.WanderRadius * math.sqrt(random:NextNumber())
	local target = findGround(current.spawnPosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance)
	current.humanoid:MoveTo(target)

	local travel = (target - current.root.Position).Magnitude / math.max(current.humanoid.WalkSpeed, 1)
	task.wait(math.min(travel, WorldBossData.MaxWalkSeconds))
	if isCurrent(current) then
		task.wait(random:NextNumber(WorldBossData.MinIdleSeconds, WorldBossData.MaxIdleSeconds))
	end
end

-- A short telegraph (ring on the ground and a hop), then players inside the ring get knocked back by their own client.
local function stomp(current: Fight)
	current.humanoid:MoveTo(current.root.Position)
	local ground = findGround(current.root.Position)
	fireEffect("StompWarn", { position = ground, radius = WorldBossData.StompRadius, seconds = WorldBossData.StompWarnSeconds })

	task.wait(math.max(WorldBossData.StompWarnSeconds - STOMP_JUMP_LEAD, 0))
	if not isCurrent(current) then
		return
	end
	current.humanoid.Jump = true
	task.wait(STOMP_JUMP_LEAD)
	if not isCurrent(current) then
		return
	end
	fireEffect("Stomp", { position = ground, radius = WorldBossData.StompRadius, power = WorldBossData.StompPower })
end

-- Wool flies off the King: everyone nearby gets a small share of their next rebirth's cost.
local function woolBurst(current: Fight)
	local position = current.root.Position
	local rewards: { [string]: number } = {}
	for _, player in players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or (root.Position - position).Magnitude > WorldBossData.WoolBurstRadius then
			continue
		end

		local amount = math.max(math.floor(getRebirthCost(player) * WorldBossData.WoolBurstFraction), WorldBossData.MinWoolBurst)
		if PlayerDataHandler.increment(player, "Wool", amount) then
			Analytics.woolEarned(player, amount, "WorldBossBurst")
			rewards[tostring(player.UserId)] = amount
		end
	end
	fireEffect("WoolBurst", { position = position, radius = WorldBossData.WoolBurstRadius, rewards = rewards })
end

-- Stands still through the intro cutscene, then wanders and uses its abilities until it's gone.
local function runBoss(current: Fight)
	task.wait(math.max(current.vulnerableAt - os.clock(), 0))
	local nextAbilityAt = os.clock() + random:NextNumber(WorldBossData.MinAbilitySeconds, WorldBossData.MaxAbilitySeconds)
	while isCurrent(current) do
		if os.clock() >= nextAbilityAt then
			if random:NextNumber() < WorldBossData.StompChance then
				stomp(current)
			else
				woolBurst(current)
			end
			nextAbilityAt = os.clock() + random:NextNumber(WorldBossData.MinAbilitySeconds, WorldBossData.MaxAbilitySeconds)
		else
			walk(current)
		end
	end
end

--// Rewards ------------------------------------------------------------------------

-- Even shares a player earned: (share x rewarded players) eased by ContributionCurve, between the floor and the cap.
local function getContribution(share: number, shearers: number): number
	local relative = math.max(share * shearers, 0)
	return math.clamp(relative ^ WorldBossData.ContributionCurve, WorldBossData.ContributionFloor, WorldBossData.ContributionCap)
end

-- The wool multipliers shearing uses (More Wool softened, see WorldBossData.MoreWoolWeight).
local function getWoolBonus(player: Player): number
	local friendBoost = player:GetAttribute(FRIEND_BOOST_ATTRIBUTE)
	return PrestigeData.getWoolMultiplier(getNumber(player, "Prestiges"))
		* UpgradeData.getMoreWoolMultiplier(getNumber(player, "MoreWoolLevel")) ^ WorldBossData.MoreWoolWeight
		* MonetizationHandler.getWoolMultiplier(player)
		* PodiumBonusHandler.getWoolMultiplier(player)
		* (if type(friendBoost) == "number" and friendBoost > 0 then friendBoost else 1)
end

-- The 2x LUCK pass and the podium's Luck bonus (not the timed boosts, which would make it swing wildly).
local function getLuckBonus(player: Player): number
	local passMultiplier = if GamePassService.ownsPass(player, "DoubleLuck")
		then MonetizationData.Items.DoubleLuck.multiplier or 1
		else 1
	return passMultiplier * PodiumBonusHandler.getLuckMultiplier(player)
end

local function pickRewardMutation(): MutationData.MutationInfo?
	local total = 0
	for _, weight in WorldBossData.RewardMutationWeights do
		total += weight
	end
	local roll = random:NextNumber() * total
	for id, weight in WorldBossData.RewardMutationWeights do
		roll -= weight
		if roll <= 0 then
			return MutationData.get(id)
		end
	end
	return nil
end

--[[
	Drops a mutated sheep (rolled with the player's Luck, never a baby) into their pen. There is no forced-mutation spawn,
	so it is built like a saved podium sheep (SheepHandler.loadSheep) and put on the farm with returnSheep.
]]
local function grantMutatedSheep(player: Player): (string?, MutationData.MutationInfo?)
	local plot = PlotHandler.getPlayerPlot(player)
	local position = plot and SheepWanderHandler.getSpawnPosition(plot)
	if not position then
		return nil, nil
	end

	local luck, rebirths, prestiges = getNumber(player, "Luck"), getNumber(player, "Rebirths"), getNumber(player, "Prestiges")
	local halloween = WeatherHandler.isHalloween()
	local sheepType = SheepData.roll(luck, rebirths, prestiges, random, nil, halloween)
	local info = if sheepType then SheepData.Sheep[sheepType] else nil
	if info and info.baby and info.adult then
		sheepType = info.adult
		info = SheepData.Sheep[info.adult]
	end
	local size = SheepSizeData.get(WorldBossData.RewardSheepSize)
	local mutation = pickRewardMutation()
	if not sheepType or not info or not size or not mutation then
		return nil, nil
	end

	local variant = SheepData.getVariant(sheepType)
	local weight = SheepSizeData.rollWeight(size, if variant then variant.weight else 1, random)
	local maxHealth = math.max(math.floor(info.ShearHealth * size.health + 0.5), 1)
	local sheep = SheepHandler.loadSheep(player, {
		type = sheepType,
		size = size.id,
		weight = weight,
		wool = math.max(math.floor(info.WoolAmount * size.wool * mutation.wool + 0.5), 1),
		health = maxHealth,
		maxHealth = maxHealth,
		odds = SheepData.getOddsText(sheepType, luck, rebirths, prestiges, nil, halloween),
		mutation = mutation.id,
	})
	if not sheep or not SheepHandler.returnSheep(player, sheep, position) then
		return nil, nil
	end
	return `{mutation.id} {info.name}`, mutation
end

-- Works out and pays one rewarded player's share; the returned numbers are exactly what was granted.
local function grantReward(player: Player, entry: Ranked, rank: number, shearers: number): Reward
	local contribution = getContribution(entry.share, shearers)
	local rankBonus = WorldBossData.RankBonus[rank] or 1
	local woolBonus = getWoolBonus(player)
	local luckBonus = getLuckBonus(player)

	local woolBase = getRebirthCost(player) * WorldBossData.WoolPerShare
	local wool = math.max(math.floor(woolBase * contribution * rankBonus * woolBonus), WorldBossData.MinWool)

	local luckBase = WorldBossData.LuckFlat + (getNumber(player, "Luck") + WorldBossData.LuckScale) * WorldBossData.LuckPerShare
	local luck = math.max(math.floor(luckBase * contribution * rankBonus * luckBonus), 1)

	local prestigeGems = math.min(getNumber(player, "Prestiges") * WorldBossData.GemsPerPrestige, WorldBossData.MaxPrestigeGems)
	local gems = WorldBossData.GemsBase
		+ math.floor(WorldBossData.GemsPerShare * contribution + 0.5)
		+ (WorldBossData.RankGems[rank] or 0)
		+ prestigeGems

	PlayerDataHandler.increment(player, "Wool", wool)
	PlayerDataHandler.increment(player, "Luck", luck)
	GemHandler.give(player, gems)

	local sheepChance = math.min(WorldBossData.MutatedSheepChance * contribution, WorldBossData.MaxMutatedSheepChance)
	local sheepName, mutation = nil, nil
	if rank == 1 or random:NextNumber() < sheepChance then
		sheepName, mutation = grantMutatedSheep(player)
	end

	Analytics.worldBossReward(player, wool, luck, gems, if mutation then mutation.id else nil)
	return {
		damage = entry.damage,
		share = entry.share,
		rank = rank,
		shearers = shearers,
		wool = wool,
		luck = luck,
		gems = gems,
		woolBonus = woolBonus,
		luckBonus = luckBonus,
		sheepName = sheepName,
		mutation = if mutation then mutation.id else nil,
		mutationColor = if mutation then mutation.color else nil,
	}
end

-- Players who did at least MinDamageShare of the damage or MinHits hits (leavers included), most damage first.
local function getEligible(current: Fight): { Ranked }
	local eligible: { Ranked } = {}
	local total = math.max(current.totalDamage, 1)
	for player, contribution in current.contributions do
		local share = contribution.damage / total
		if share >= WorldBossData.MinDamageShare or contribution.hits >= WorldBossData.MinHits then
			table.insert(eligible, { player = player, damage = contribution.damage, share = share })
		end
	end
	table.sort(eligible, function(a: Ranked, b: Ranked): boolean
		return a.damage > b.damage
	end)
	return eligible
end

-- Pays everyone still here and returns their rewards, the top shearer (nil if they left) and how many were rewarded.
local function payOut(current: Fight): ({ [Player]: Reward }, Player?, number)
	local eligible = getEligible(current)
	local shearers = #eligible
	local rewards: { [Player]: Reward } = {}
	local top: Player? = nil
	local rank = 0
	for _, entry in eligible do
		rank += 1
		local player = entry.player
		if not player.Parent then
			continue
		elseif rank == 1 then
			top = player
		end
		local success, reward = pcall(grantReward, player, entry, rank, shearers)
		if success then
			rewards[player] = reward
		else
			warn(`WorldBossHandler: couldn't reward {player.Name}: {reward}`)
		end
		Analytics.worldBossDefeated(player, rank, entry.share)
	end

	for player in current.contributions do
		if player.Parent and not rewards[player] then
			network.fireClient(network.RemoteEvents.ShowAlert, player, "Shear the King Sheep more to earn a reward next time!", "info")
		end
	end
	return rewards, top, shearers
end

--// Fight lifecycle ------------------------------------------------------------------

local function finish(current: Fight, defeated: boolean)
	if fight ~= current then
		return
	end
	fight = nil -- stops runBoss
	if current.timeout and coroutine.status(current.timeout) == "suspended" then
		task.cancel(current.timeout)
	end
	lastEndedAt = now()
	setState("None", nil)

	local boss = current.boss
	local boxCFrame, boxSize = boss:GetBoundingBox()
	if not defeated then
		fireEffect("Escaped", { position = boxCFrame.Position, size = boxSize.Magnitude })
		boss:Destroy()
		AnnouncementHandler.worldBossEscaped()
		for player, contribution in current.contributions do
			if player.Parent then
				Analytics.worldBossEscaped(player, contribution.damage / math.max(current.totalDamage, 1))
			end
		end
		return
	end

	-- Frozen where it fell while every client plays the burst and the ending shot; it's removed once that's done.
	current.humanoid:MoveTo(current.root.Position)
	current.humanoid.WalkSpeed = 0
	current.root.Anchored = true
	local bar = current.root:FindFirstChildOfClass("BillboardGui")
	if bar then
		bar:Destroy()
	end

	local rewards, top, shearers = payOut(current)
	fireEffect("Defeated", {
		position = boxCFrame.Position,
		size = boxSize.Magnitude,
		height = boxSize.Y,
		pivot = boss:GetPivot(),
		boss = boss,
		seconds = WorldBossData.DefeatSequenceSeconds,
	})
	AnnouncementHandler.worldBossDefeated(top, shearers)
	for player, reward in rewards do
		network.fireClient(network.RemoteEvents.WorldBossEffect, player, "Reward", reward)
	end
	task.delay(WorldBossData.DefeatSequenceSeconds, function()
		boss:Destroy()
	end)
end

local function spawnBoss(source: string)
	pendingThread = nil
	WeatherHandler.setScheduled(SCHEDULE_SOURCE, nil, nil)
	local current = buildFight()
	if not current then
		lastEndedAt = now()
		setState("None", nil)
		return
	end

	fight = current
	setState("Active", now() + WorldBossData.IntroSeconds + WorldBossData.TimeLimit)
	WeatherHandler.markNotable()
	AnnouncementHandler.worldBossSpawn(WorldBossData.TimeLimit, WorldBossData.IntroSeconds)
	local boxCFrame, boxSize = current.boss:GetBoundingBox()
	fireEffect("Spawn", {
		position = current.spawnPosition,
		pivot = current.boss:GetPivot(),
		center = boxCFrame.Position,
		height = boxSize.Y,
		seconds = WorldBossData.IntroSeconds,
	})
	for _, player in players:GetPlayers() do
		Analytics.worldBossSpawned(player, source, WeatherHandler.getWeather())
	end

	current.timeout = task.delay(WorldBossData.IntroSeconds + WorldBossData.TimeLimit, finish, current, false)
	task.spawn(runBoss, current)
end

-- Warns everyone, then the King arrives PendingSeconds later; the next weather waits a while after it.
local function startPending(source: string)
	local arrivesAt = now() + WorldBossData.PendingSeconds
	setState("Pending", arrivesAt)
	AnnouncementHandler.worldBossPending(WorldBossData.PendingSeconds)
	WeatherHandler.setScheduled(SCHEDULE_SOURCE, EVENT_NAME, arrivesAt)
	WeatherHandler.delayNextWeather(arrivesAt + WeatherData.MinEventGap)
	pendingThread = task.delay(WorldBossData.PendingSeconds, spawnBoss, source)
end

local function tryRoll(chance: number)
	if state ~= "None" or now() - lastEndedAt < WorldBossData.CooldownSeconds or #players:GetPlayers() == 0 then
		return
	end
	local boosted = if isServerLucky() then chance * WorldBossData.ServerLuckChanceMultiplier else chance
	if random:NextNumber() < math.min(boosted, WorldBossData.MaxChance) then
		startPending("Roll")
	end
end

local function onWeatherChanged(weather: string)
	rollRound += 1
	if weather == WeatherData.Clear then
		tryRoll(WorldBossData.ClearChance)
	elseif weather == WeatherData.Halloween then
		local round = rollRound
		task.delay(WorldBossData.NightRollDelay, function()
			if round == rollRound then
				tryRoll(WorldBossData.NightChance)
			end
		end)
	end
end

-- "/kingboss" warns and spawns it, "/kingboss now" skips the warning, "/kingboss end" sends it away. Ignores the cooldown.
local function onCommand(_speaker: Player, message: string)
	local option = string.lower(string.match(message, "^%S+%s+(%S+)") or "")
	if option == "end" or option == "stop" then
		if fight then
			finish(fight, false)
		elseif pendingThread then
			task.cancel(pendingThread)
			pendingThread = nil
			WeatherHandler.setScheduled(SCHEDULE_SOURCE, nil, nil)
			setState("None", nil)
		end
	elseif state == "None" then
		if option == "now" then
			spawnBoss("Admin")
		else
			startPending("Admin")
		end
	elseif state == "Pending" and option == "now" and pendingThread then
		task.cancel(pendingThread)
		spawnBoss("Admin")
	end
end

--// Public API ------------------------------------------------------------------

function WorldBossHandler.getState(): State
	return state
end

function WorldBossHandler.isActive(): boolean
	return state == "Active"
end

-- The live boss if it is within a shear's reach (`range` plus its HitRadius, flat) of `center`; used by ShearHandler.shearAround.
function WorldBossHandler.getBossInRange(center: Vector3, range: number): Model?
	local current = fight
	if not current or not isVulnerable(current) then
		return nil
	end
	local offset = current.root.Position - center
	if math.abs(offset.Y) > WorldBossData.HitHeight then
		return nil
	end
	return if Vector3.new(offset.X, 0, offset.Z).Magnitude <= range + WorldBossData.HitRadius then current.boss else nil
end

-- Takes `amount` off the shared health for `player` and returns the hit for the client; nil when there's no live boss.
function WorldBossHandler.applyDamage(player: Player, amount: number): Hit?
	local current = fight
	if not current or not isVulnerable(current) then
		return nil
	end

	local damage = math.min(math.max(math.floor(amount), 1), current.health)
	current.health -= damage
	current.totalDamage += damage
	local contribution = current.contributions[player] or { damage = 0, hits = 0 }
	contribution.damage += damage
	contribution.hits += 1
	current.contributions[player] = contribution

	current.boss:SetAttribute("Health", current.health)
	updateWool(current)

	local defeated = current.health <= 0
	if defeated then
		task.defer(finish, current, true)
	end
	return {
		sheep = if defeated then nil else current.boss,
		position = current.root.Position,
		damage = damage,
		color = current.woolColor,
		flashColor = if defeated then KILL_FLASH_COLOR else nil,
		flashPulses = if defeated then KILL_FLASH_PULSES else nil,
	}
end

--// Lifecycle -----------------------------------------------------------------------

function WorldBossHandler.Start()
	setState("None", nil)
	WeatherHandler.WeatherChanged:Connect(onWeatherChanged)
	AdminCommands.register("KingBossCommand", "/kingboss", "/kingsheep", onCommand)
end

return WorldBossHandler
