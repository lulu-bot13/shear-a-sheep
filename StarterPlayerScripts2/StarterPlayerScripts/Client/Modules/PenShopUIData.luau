--!strict

--[[
	Client-side display data for the pen shop UI: names, descriptions and prices as shown on the cards.
	The server (ServerScriptService.Modules.Constants.PenShopData) is the authority on what a purchase
	costs - keep the prices here in sync with it when tuning.

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.PenShopUIData
]]--

export type PenUI = {
	id: string, -- Model name in ReplicatedStorage.Assets.Models.Pens
	displayName: string,
	description: string,
	price: number,
	robux: number,
	robuxAvailable: boolean, -- false until the server has a developer product for it
}

local penShopUIData = {}

-- Card order in the shop, cheapest first.
penShopUIData.Pens = {
	{ id = "Base_Pen",   displayName = "Classic Pen", description = "The trusty wooden pen every farm starts with.",                 price = 0,     robux = 0,   robuxAvailable = false },
	{ id = "Oak_Pen",    displayName = "Oak Pen",     description = "Sturdy dark oak posts with warm, polished rails.",              price = 500,   robux = 49,  robuxAvailable = false },
	{ id = "Stone_Pen",  displayName = "Stone Pen",   description = "Cobblestone posts and slate rails, built to last.",             price = 2000,  robux = 99,  robuxAvailable = false },
	{ id = "Candy_Pen",  displayName = "Candy Pen",   description = "Sweet pink and white stripes on a sugary pink floor.",          price = 5000,  robux = 149, robuxAvailable = false },
	{ id = "Ice_Pen",    displayName = "Ice Pen",     description = "Frosty glass rails on shimmering ice. Cool and clear.",         price = 10000, robux = 249, robuxAvailable = false },
	{ id = "Golden_Pen", displayName = "Golden Pen",  description = "Gleaming gold posts and rails for the fanciest flock.",         price = 25000, robux = 399, robuxAvailable = false },
} :: { PenUI }

--// Preview (the spinning 3D pen on each card)
penShopUIData.SpinSpeed = 0.8 -- radians per second
penShopUIData.PreviewPitch = math.rad(28)
penShopUIData.PreviewFieldOfView = 35

--// Button colours
penShopUIData.ButtonColors = {
	Ready = Color3.fromRGB(110, 220, 120),
	Poor = Color3.fromRGB(205, 120, 120),
	Equipped = Color3.fromRGB(255, 200, 70),
	Owned = Color3.fromRGB(120, 190, 255),
	Robux = Color3.fromRGB(90, 170, 255),
	Disabled = Color3.fromRGB(160, 160, 165),
}

-- 1500 -> "$1,500"
function penShopUIData.formatMoney(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. formatted:gsub("^,", "")
end

return penShopUIData
