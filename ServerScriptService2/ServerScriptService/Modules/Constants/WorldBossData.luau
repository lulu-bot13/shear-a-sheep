--!strict

--[[
	King Sheep world boss tuning: when it is rolled, how tough it is, what it does in the arena and what it pays out.

	Location: ServerScriptService.Modules.Constants.WorldBossData
]]--

local worldBossData = {}

worldBossData.ModelName = "KingSheep" -- in ReplicatedStorage.Assets.Models.Sheeps
worldBossData.SpawnTag = "WorldBossSpawn" -- the part it rises at (Base.BossArena.BossSpawn)
worldBossData.Tag = "WorldBoss" -- on the live boss model; ShearClient outlines it and WorldBossClient draws its bars
worldBossData.Attribute = "WorldBoss" -- true on the live boss model; ShearHandler forwards hits on it here

--// Rolls -----------------------------------------------------------------------------------
-- Rolled when a Clear spell starts (every ~3.5-4.5 min) and once during each Night.

worldBossData.ClearChance = 0.2
worldBossData.NightChance = 0.6
worldBossData.NightRollDelay = 90 -- seconds into the Night; with the warning it arrives 2 min after the Night began
worldBossData.ServerLuckChanceMultiplier = 3 -- while Server Luck is active
worldBossData.MaxChance = 0.9
worldBossData.CooldownSeconds = 360 -- after a boss leaves (defeated or escaped) before the next roll can hit
worldBossData.PendingSeconds = 30 -- warning before it arrives

--// Fight -----------------------------------------------------------------------------------

worldBossData.IntroSeconds = 4.5 -- the arrival cutscene: it stands still and can't be shorn, so nobody gets a head start
worldBossData.TimeLimit = 180 -- seconds after the intro before it escapes
worldBossData.DefeatSequenceSeconds = 2.2 -- it stays frozen this long after the last snip while clients play the burst
worldBossData.Scale = 2.5 -- times the Studio model's size
worldBossData.BaseHealth = 400
worldBossData.SwingsPerPlayer = 80 -- health added per player = their shear damage times this (~28 s of swinging each)
worldBossData.MaxScaledPlayers = 12
worldBossData.DefaultShearDamage = 20 -- for a player whose ShearDamage attribute isn't set yet
worldBossData.HitRadius = 6 -- extra flat studs a shear reaches, for its big body
worldBossData.HitHeight = 10 -- studs its root may be above or below a player and still be hit

--// Behaviour -------------------------------------------------------------------------------

worldBossData.WanderRadius = 18 -- studs around BossSpawn; the arena banners stand at ~25
worldBossData.WalkSpeed = 8
worldBossData.MinIdleSeconds = 1.5
worldBossData.MaxIdleSeconds = 3.5
worldBossData.MaxWalkSeconds = 5
worldBossData.MinAbilitySeconds = 10 -- between stomps / wool bursts
worldBossData.MaxAbilitySeconds = 16
worldBossData.StompChance = 0.55 -- the rest are wool bursts
worldBossData.StompWarnSeconds = 1.2
worldBossData.StompRadius = 14
worldBossData.StompPower = 55 -- knockback speed (studs/s), applied by each client to its own character
worldBossData.WoolBurstRadius = 22
worldBossData.WoolBurstFraction = 0.01 -- wool to everyone in range, as a share of their next rebirth cost
worldBossData.MinWoolBurst = 25

--// Rewards: contribution ---------------------------------------------------------------------
--[[
	Each reward = the player's progression base x their contribution x their rank bonus x their own multipliers.
	contribution = (damage share x rewarded players) ^ ContributionCurve, clamped to [ContributionFloor, ContributionCap].
	1 = an even split (a solo kill is 1 too, since its health was scaled for one). Players who left still count towards the
	split, so the ones who stayed aren't paid as if they did the leaver's part.
]]

worldBossData.MinDamageShare = 0.01 -- to be rewarded at all a player needs this share of all the damage dealt...
worldBossData.MinHits = 5 -- ...or this many hits, so someone who stood there (~0 damage) gets nothing
worldBossData.ContributionCurve = 0.75 -- under 1 narrows the gap: half an even share pays ~0.59, double pays ~1.68
worldBossData.ContributionFloor = 0.15 -- the least a rewarded player gets, in even shares (a few late snips)
worldBossData.ContributionCap = 2.5 -- the most anyone gets, however much they carried (reached at ~3.4 even shares)
worldBossData.RankBonus = { 1.3, 1.15, 1.1 } -- wool and Luck multiplier for the top 3 by damage
worldBossData.RankGems = { 4, 2, 1 } -- extra Gems for the top 3

--// Rewards: amounts ---------------------------------------------------------------------------

-- Wool: a share of the player's next rebirth cost (their last one's at max rebirths), which grows x1.4 a rebirth with the
-- economy. Times their Prestige, 2x WOOL pass, podium and friend multipliers, like shearing, so it keeps up after Prestiges.
worldBossData.WoolPerShare = 0.3 -- of the next rebirth cost, per even share (~30-90 s of play at that rebirth)
worldBossData.MoreWoolWeight = 0.25 -- More Wool's multiplier counts as multiplier ^ this; rebirth costs already track most of it
worldBossData.MinWool = 25 -- floor for any rewarded player, so a brand-new farm still sees a number

-- Luck works on a log scale (SpawnOdds), so a flat amount matters early and a share of the player's own Luck keeps the same
-- few-% luck factor bump later on. Times the 2x LUCK pass and the podium's Luck bonus.
worldBossData.LuckFlat = 30 -- per even share; ~+6% luck factor for a brand-new player
worldBossData.LuckPerShare = 0.05 -- of (their Luck + SpawnOdds.LUCK_SCALE), per even share; ~+1% luck factor at any stage
worldBossData.LuckScale = 100 -- SpawnOdds.LUCK_SCALE

-- Gems are the rare currency (an Ability Shack roll is 4), so they barely scale: 4 for an even share, ~10 for the top shearer.
worldBossData.GemsBase = 2
worldBossData.GemsPerShare = 2 -- times the contribution, rounded
worldBossData.GemsPerPrestige = 1 -- a small extra for veterans...
worldBossData.MaxPrestigeGems = 3 -- ...up to this many

-- A mutated sheep (rolled with the player's own Luck, never a baby) dropped into their pen.
worldBossData.MutatedSheepChance = 0.2 -- per even share of contribution; the top shearer always gets one
worldBossData.MaxMutatedSheepChance = 0.6
worldBossData.RewardSheepSize = "Normal"
worldBossData.RewardMutationWeights = { Shiny = 60, Rainbow = 25, Haunted = 10, Galaxy = 5 }

return worldBossData
