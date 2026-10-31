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
}

return RemoteEventName
