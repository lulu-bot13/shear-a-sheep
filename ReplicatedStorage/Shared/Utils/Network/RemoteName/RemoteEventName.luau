--!strict

--[[
	Specifies the names of all RemoteEvents. One RemoteEvent object gets
    generated for each name	in this list, and these names are used as enums when
    interacting with the Network module to tell it which remote event to fire
    without typing out typo-prone string literals.
]]

local StrictEnum = require("../Utility/StrictEnum")

export type EnumType = "ActivateShearing"
    | "DeactivateShearing"
    | "StartShearing"
    | "StopShearing"
    | "ShearAttempt"
    | "ShearPress"
    | "OpenPenMenu"
    | "ClosePenMenu"
    | "UpgradePen"
    | "SellPen"
    | "HireWorker"
    | "WoolSold"
    | "PurchaseShear"
    | "EquipShear"
    | "ShearPurchaseResult"
    | "PenSkinAction"
    | "PenSkinResult"
    | "ReplacePen"
    | "RequestRebirth"
    | "RequestRebirthState"
    | "RebirthState"
    | "RebirthResult"
    | "Teleport"

local RemoteEventName: StrictEnum.FromEnum<EnumType> = {
	ActivateShearing = "ActivateShearing",
    DeactivateShearing = "DeactivateShearing",
    StartShearing = "StartShearing",
    StopShearing = "StopShearing",
    ShearAttempt = "ShearAttempt",
    ShearPress = "ShearPress",
    OpenPenMenu = "OpenPenMenu",
    ClosePenMenu = "ClosePenMenu",
    UpgradePen = "UpgradePen",
    SellPen = "SellPen",
    HireWorker = "HireWorker",
    WoolSold = "WoolSold",
    PurchaseShear = "PurchaseShear",
    EquipShear = "EquipShear",
    ShearPurchaseResult = "ShearPurchaseResult",
    PenSkinAction = "PenSkinAction",
    PenSkinResult = "PenSkinResult",
    ReplacePen = "ReplacePen",
    RequestRebirth = "RequestRebirth",
    RequestRebirthState = "RequestRebirthState",
    RebirthState = "RebirthState",
    RebirthResult = "RebirthResult",
    Teleport = "Teleport"
}

return RemoteEventName
