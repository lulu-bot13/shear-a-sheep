--!strict

--[[
	Where each pen sits on a plot. Pen N always goes in slot N, so the finished tycoon looks the same every time.

	A slot's position is set in one of two ways, checked in this order:
	  1. A Part named after the pen number (e.g. "2") inside the plot's "PenSlots" folder. Drop these in Studio
	     where each fenced pen should go; only their X/Z position is used (relative to the Base_Pen).
	  2. The fallback offsets below.

	Pen 1 is the Base_Pen already sitting in the plot, so its offset is always zero.

	Location: ServerScriptService.Modules.Constants.PenLayout
]]--

local PenLayout = {}

PenLayout.SlotsFolderName = "PenSlots"

--[[
	Fallback offsets in studs from the Base_Pen's pivot, in the Base_Pen's own space
	(+X right, -Z forward), so the layout follows the plot if it is rotated.
	Indexed by pen number. These are placeholders (a straight line); set them to match the map.
]]--
PenLayout.Offsets = {
	[1] = Vector3.zero,
	[2] = Vector3.new(0, 0, -15.8),
	[3] = Vector3.new(0, 0, -31.6),
	[4] = Vector3.new(0, 0, -47.4),
	[5] = Vector3.new(0, 0, -63.2),
	[6] = Vector3.new(0, 0, -79),
} :: { [number]: Vector3 }

PenLayout.SlotCount = #PenLayout.Offsets

--[[
	World-space offset from the Base_Pen to the slot for pen `penNumber`, or nil if the slot doesn't exist.

	@param plot The plot the pens belong to
	@param basePivot Pivot of the untouched Base_Pen
]]--
function PenLayout.getSlotOffset(plot: Instance, penNumber: number, basePivot: CFrame): Vector3?
	local slots = plot:FindFirstChild(PenLayout.SlotsFolderName)
	local marker = if slots then slots:FindFirstChild(tostring(penNumber)) else nil
	if marker and marker:IsA("BasePart") then
		local delta = marker.Position - basePivot.Position
		return Vector3.new(delta.X, 0, delta.Z)
	end

	local offset = PenLayout.Offsets[penNumber]
	return if offset then basePivot:VectorToWorldSpace(offset) else nil
end

return PenLayout
