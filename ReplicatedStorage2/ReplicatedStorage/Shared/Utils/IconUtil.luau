--!strict

--[[
	Sets icon images on ImageLabels/ImageButtons and keeps the wool image at its own aspect ratio so it isn't squashed.
	Location: ReplicatedStorage.Shared.Utils.IconUtil
]]--

local IconIds = require(script.Parent.Parent.Constants.IconIds)

local CONSTRAINT_NAME = "WoolAspect" -- a constraint IconUtil made itself, removed again when the image stops being wool
local ORIGINAL_RATIO_ATTRIBUTE = "OriginalAspectRatio" -- kept on a Studio-made constraint so its ratio can be put back

local IconUtil = {}

-- Creates or updates the image's UIAspectRatioConstraint so the wool icon keeps its shape.
function IconUtil.applyWoolAspect(imageObject: ImageLabel | ImageButton)
	local constraint = imageObject:FindFirstChildOfClass("UIAspectRatioConstraint")
	if constraint then
		if constraint.Name ~= CONSTRAINT_NAME and constraint:GetAttribute(ORIGINAL_RATIO_ATTRIBUTE) == nil then
			constraint:SetAttribute(ORIGINAL_RATIO_ATTRIBUTE, constraint.AspectRatio)
		end
		constraint.AspectRatio = IconIds.WoolAspectRatio
		return
	end

	local created = Instance.new("UIAspectRatioConstraint")
	created.Name = CONSTRAINT_NAME
	created.AspectRatio = IconIds.WoolAspectRatio
	created.Parent = imageObject
end

-- Undoes applyWoolAspect: removes the constraint it made, or gives a Studio-made one its old ratio back.
function IconUtil.clearWoolAspect(imageObject: ImageLabel | ImageButton)
	local constraint = imageObject:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not constraint then
		return
	end

	if constraint.Name == CONSTRAINT_NAME then
		constraint:Destroy()
		return
	end
	local original = constraint:GetAttribute(ORIGINAL_RATIO_ATTRIBUTE)
	if type(original) == "number" then
		constraint.AspectRatio = original
		constraint:SetAttribute(ORIGINAL_RATIO_ATTRIBUTE, nil)
	end
end

-- Sets the image; the wool image gets its aspect constraint, anything else loses it (for objects reused across icons).
function IconUtil.setImage(imageObject: ImageLabel | ImageButton, image: string)
	imageObject.Image = image
	if image == IconIds.Wool then
		IconUtil.applyWoolAspect(imageObject)
	else
		IconUtil.clearWoolAspect(imageObject)
	end
end

return IconUtil
