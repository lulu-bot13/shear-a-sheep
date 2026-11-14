--!strict

--[[
	Specifies the names of all RemoteEvents. One RemoteEvent object gets
    generated for each name	in this list, and these names are used as enums when
    interacting with the Network module to tell it which remote event to fire
    without typing out typo-prone string literals.
]]

local StrictEnum = require("../Utility/StrictEnum")

export type EnumType = "ShearSwing"
	| "ShearHit"
	| "SheepSheared"
	| "PurchaseShear"
	| "EquipShear"
	| "ShearPurchaseResult"
	| "PurchaseUpgrade"
	| "UpgradeResult"
	| "RequestUpgradeState"
	| "UpgradeState"
	| "RequestRebirth"
	| "RequestRebirthState"
	| "RebirthState"
	| "RebirthResult"
	| "RequestPrestige"
	| "RequestPrestigeState"
	| "PrestigeState"
	| "PrestigeResult"
	| "PrestigeFinished"
	| "Teleport"
	| "ClaimIndexReward"
	| "ClaimAllIndexRewards"
	| "IndexClaimResult"
	| "RequestIndexState"
	| "IndexState"
	| "SheepUnlocked"
	| "UseAbility"
	| "TitleUnlocked"
	| "AbilityEffect"
	| "RollAbility"
	| "EquipAbility"
	| "AbilityRollResult"
	| "RequestAbilityState"
	| "AbilityState"
	| "CrookPickUp"
	| "CrookRelease"
	| "ServerAnnouncement"
	| "GemFound"
	| "HugeSheepSpawn"
	| "HalloweenSheepSpawn"
	| "AnalyticsEvent"
	| "RequestTutorialSheep"
	| "CrookTutorialDone"
	| "RequestSettings"
	| "SettingsState"
	| "ChangeSetting"
	| "RequestDailyRewardState"
	| "DailyRewardState"
	| "ClaimDailyReward"
	| "DailyRewardResult"
	| "ShowAlert"
	| "RequestShopState"
	| "ShopState"
	| "RequestProductPrompt"
	| "GlobalAnnouncement"
	-- Phase 4 (WorldBoss)
	| "WorldBossEffect"
	-- Phase 8 (Offers)
	| "ShowOffer"
	| "OfferResponse"
	-- Phase 9/10 (Progression + Goals)
	| "SheepPoof"
	| "RequestGoalState"
	| "GoalState"
	-- Offline earnings
	| "RequestOfflineEarnings"
	| "OfflineEarningsState"
	| "ClaimOfflineEarnings"
	-- Rebirth sheep reveal
	| "RebirthSheepSpawned"
	-- Group shear
	| "ClaimGroupShear"
	| "GroupShearResult"

local RemoteEventName: StrictEnum.FromEnum<EnumType> = {
	ShearSwing = "ShearSwing",
	ShearHit = "ShearHit",
	SheepSheared = "SheepSheared",
	PurchaseShear = "PurchaseShear",
	EquipShear = "EquipShear",
	ShearPurchaseResult = "ShearPurchaseResult",
	PurchaseUpgrade = "PurchaseUpgrade",
	UpgradeResult = "UpgradeResult",
	RequestUpgradeState = "RequestUpgradeState",
	UpgradeState = "UpgradeState",
	RequestRebirth = "RequestRebirth",
	RequestRebirthState = "RequestRebirthState",
	RebirthState = "RebirthState",
	RebirthResult = "RebirthResult",
	RequestPrestige = "RequestPrestige",
	RequestPrestigeState = "RequestPrestigeState",
	PrestigeState = "PrestigeState",
	PrestigeResult = "PrestigeResult",
	PrestigeFinished = "PrestigeFinished",
	Teleport = "Teleport",
	ClaimIndexReward = "ClaimIndexReward",
	ClaimAllIndexRewards = "ClaimAllIndexRewards",
	IndexClaimResult = "IndexClaimResult",
	RequestIndexState = "RequestIndexState",
	IndexState = "IndexState",
	SheepUnlocked = "SheepUnlocked",
	UseAbility = "UseAbility",
	TitleUnlocked = "TitleUnlocked",
	AbilityEffect = "AbilityEffect",
	RollAbility = "RollAbility",
	EquipAbility = "EquipAbility",
	AbilityRollResult = "AbilityRollResult",
	RequestAbilityState = "RequestAbilityState",
	AbilityState = "AbilityState",
	CrookPickUp = "CrookPickUp",
	CrookRelease = "CrookRelease",
	ServerAnnouncement = "ServerAnnouncement",
	GemFound = "GemFound",
	HugeSheepSpawn = "HugeSheepSpawn",
	HalloweenSheepSpawn = "HalloweenSheepSpawn",
	AnalyticsEvent = "AnalyticsEvent",
	RequestTutorialSheep = "RequestTutorialSheep",
	CrookTutorialDone = "CrookTutorialDone",
	RequestSettings = "RequestSettings",
	SettingsState = "SettingsState",
	ChangeSetting = "ChangeSetting",
	RequestDailyRewardState = "RequestDailyRewardState",
	DailyRewardState = "DailyRewardState",
	ClaimDailyReward = "ClaimDailyReward",
	DailyRewardResult = "DailyRewardResult",
	ShowAlert = "ShowAlert",
	RequestShopState = "RequestShopState",
	ShopState = "ShopState",
	RequestProductPrompt = "RequestProductPrompt",
	GlobalAnnouncement = "GlobalAnnouncement",
	-- Phase 4 (WorldBoss)
	WorldBossEffect = "WorldBossEffect",
	-- Phase 8 (Offers)
	ShowOffer = "ShowOffer",
	OfferResponse = "OfferResponse",
	-- Phase 9/10 (Progression + Goals)
	SheepPoof = "SheepPoof",
	RequestGoalState = "RequestGoalState",
	GoalState = "GoalState",
	-- Offline earnings
	RequestOfflineEarnings = "RequestOfflineEarnings",
	OfflineEarningsState = "OfflineEarningsState",
	ClaimOfflineEarnings = "ClaimOfflineEarnings",
	-- Rebirth sheep reveal
	RebirthSheepSpawned = "RebirthSheepSpawned",
	-- Group shear
	ClaimGroupShear = "ClaimGroupShear",
	GroupShearResult = "GroupShearResult",
}

return RemoteEventName
