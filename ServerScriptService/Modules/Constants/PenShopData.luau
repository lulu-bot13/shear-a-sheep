--!strict

--[[
	Server-side (authoritative) data for the pen shop: which pen styles exist and what they cost.
	The client has a display-only copy in PenShopUIData - keep prices in sync when tuning.

	id         matches the model name in ReplicatedStorage.Assets.Models.Pens
	price      money cost (the classic pen is free, everyone owns it)
	robux      Robux price shown in the purchase options
	productId  developer product for the Robux option; 0 = not set up yet, so Robux purchases are refused

	Pen styles are cosmetic: they change how a player's pens look, not how they play.

	Location: ServerScriptService.Modules.Constants.PenShopData
]]--

export type PenSkinInfo = {
	id: string,
	price: number,
	robux: number,
	productId: number,
}

local penShopData = {}

penShopData.DefaultSkinId = "Base_Pen"

penShopData.Skins = {
	{ id = "Base_Pen",   price = 0,     robux = 0,   productId = 0 },
	{ id = "Oak_Pen",    price = 500,   robux = 49,  productId = 0 },
	{ id = "Stone_Pen",  price = 2000,  robux = 99,  productId = 0 },
	{ id = "Candy_Pen",  price = 5000,  robux = 149, productId = 0 },
	{ id = "Ice_Pen",    price = 10000, robux = 249, productId = 0 },
	{ id = "Golden_Pen", price = 25000, robux = 399, productId = 0 },
} :: { PenSkinInfo }

-- How far (studs) from the shop prompt a player may still buy.
penShopData.PurchaseRange = 25

penShopData.ShopPromptTag = "PenShop"

local indexById: { [string]: number } = {}
for index, info in penShopData.Skins do
	indexById[info.id] = index
end

function penShopData.get(id: any): PenSkinInfo?
	if type(id) ~= "string" then
		return nil
	end
	local index = indexById[id]
	return if index then penShopData.Skins[index] else nil
end

return penShopData
