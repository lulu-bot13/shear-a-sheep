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
    | "Shear"
    | "OpenPenMenu"
    | "ClosePenMenu"
    | "UpgradePen"
    | "SellPen"
    | "HireWorker"

local RemoteEventName: StrictEnum.FromEnum<EnumType> = {
	ActivateShearing = "ActivateShearing",
    DeactivateShearing = "DeactivateShearing",
    Shear = "Shear",
    OpenPenMenu = "OpenPenMenu",
    ClosePenMenu = "ClosePenMenu",
    UpgradePen = "UpgradePen",
    SellPen = "SellPen",
    HireWorker = "HireWorker"
}

return RemoteEventName
