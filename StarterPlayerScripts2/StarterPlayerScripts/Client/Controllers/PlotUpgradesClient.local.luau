--!strict

--[[
	Fades in the plot expansions (Upgrades/RebirthN children) that PlotBuildHandler flags Unlocked, and hides locked ones.
	Expansions already unlocked when first seen just appear.
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local tweenService = game:GetService("TweenService")

--// Configs
local UPGRADE_TAG = "RebirthUpgrade"
local UNLOCKED_ATTRIBUTE = "Unlocked"
local FADE_INFO = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Upgrade = {
	parts: { [BasePart | Decal]: number }, -- item -> its real Transparency
	guis: { SurfaceGui | BillboardGui },
	tweens: { Tween },
	connection: RBXScriptConnection,
}

--// State
local upgrades: { [Instance]: Upgrade } = {}

local function cancelTweens(upgrade: Upgrade)
	for _, tween in upgrade.tweens do
		tween:Cancel()
	end
	table.clear(upgrade.tweens)
end

local function setGuisEnabled(upgrade: Upgrade, enabled: boolean)
	for _, gui in upgrade.guis do
		gui.Enabled = enabled
	end
end

local function hide(upgrade: Upgrade)
	cancelTweens(upgrade)
	for item in upgrade.parts do
		item.Transparency = 1
	end
	setGuisEnabled(upgrade, false)
end

local function show(upgrade: Upgrade, animate: boolean)
	cancelTweens(upgrade)
	setGuisEnabled(upgrade, true)
	for item, base in upgrade.parts do
		if animate then
			local tween = tweenService:Create(item, FADE_INFO, { Transparency = base })
			table.insert(upgrade.tweens, tween)
			tween:Play()
		else
			item.Transparency = base
		end
	end
end

local function refresh(instance: Instance, upgrade: Upgrade, animate: boolean)
	if instance:GetAttribute(UNLOCKED_ATTRIBUTE) == true then
		show(upgrade, animate)
	else
		hide(upgrade)
	end
end

local function register(instance: Instance)
	if upgrades[instance] then
		return
	end

	local upgrade: Upgrade
	upgrade = {
		parts = {},
		guis = {},
		tweens = {},
		connection = instance:GetAttributeChangedSignal(UNLOCKED_ATTRIBUTE):Connect(function()
			refresh(instance, upgrade, true)
		end),
	}

	local items = instance:GetDescendants()
	table.insert(items, instance)
	for _, descendant in items do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			upgrade.parts[descendant] = descendant.Transparency
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			table.insert(upgrade.guis, descendant)
		end
	end

	upgrades[instance] = upgrade
	refresh(instance, upgrade, false)
end

local function unregister(instance: Instance)
	local upgrade = upgrades[instance]
	if upgrade then
		upgrade.connection:Disconnect()
		cancelTweens(upgrade)
		upgrades[instance] = nil
	end
end

--// Setup ---------------------------------------------------------------------------

collectionService:GetInstanceAddedSignal(UPGRADE_TAG):Connect(register)
collectionService:GetInstanceRemovedSignal(UPGRADE_TAG):Connect(unregister)
for _, instance in collectionService:GetTagged(UPGRADE_TAG) do
	register(instance)
end
