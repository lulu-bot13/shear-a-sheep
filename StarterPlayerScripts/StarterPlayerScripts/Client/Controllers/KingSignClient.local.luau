--[[
	Counts down to the next King Sheep on the plaza's KingSign (WorldBossHandler's workspace attributes) and slowly spins it.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.KingSignClient
]]--

--// Services
local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")

--// Configs
local TAG = "KingSign"
local STATE_ATTRIBUTE = "WorldBossState" -- "None" | "Pending" | "Active"
local AT_ATTRIBUTE = "WorldBossAt" -- Pending: when it arrives; Active: when it escapes
local NEXT_AT_ATTRIBUTE = "WorldBossNextAt" -- when the next one is due
local TICK_SECONDS = 0.25
local SPIN_SECONDS = 24 -- per full turn
local BOB_HEIGHT = 0.6
local BOB_SECONDS = 4
local NORMAL_STATUS_COLOR = Color3.fromRGB(240, 236, 250)
local ALERT_STATUS_COLOR = Color3.fromRGB(255, 120, 90)

type Sign = { model: Model, basePivot: CFrame }

--// State
local signs: { [Model]: Sign } = {}

local function formatTime(seconds: number): string
	local whole = math.max(math.ceil(seconds), 0)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

local function getNumber(name: string): number?
	local value = workspace:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

-- The status line, the big timer and whether it's urgent, for the boss's current state.
local function getText(): (string, string, boolean)
	local now = workspace:GetServerTimeNow()
	local state = workspace:GetAttribute(STATE_ATTRIBUTE)
	local at = getNumber(AT_ATTRIBUTE)
	if state == "Active" then
		return "is HERE! Shear it!", if at then formatTime(at - now) else "NOW", true
	elseif state == "Pending" then
		return "ARRIVING IN", if at then formatTime(at - now) else "SOON", true
	end
	local nextAt = getNumber(NEXT_AT_ATTRIBUTE)
	return "arrives in", if nextAt and nextAt > now then formatTime(nextAt - now) else "SOON", false
end

local function updateText()
	local status, timer, urgent = getText()
	for _, sign in signs do
		-- Looked up each tick: with streaming the SurfaceGuis can arrive after the model.
		for _, gui in sign.model:GetDescendants() do
			if not gui:IsA("SurfaceGui") then
				continue
			end
			local statusLabel = gui:FindFirstChild("Status")
			local timerLabel = gui:FindFirstChild("Timer")
			if statusLabel and statusLabel:IsA("TextLabel") then
				statusLabel.Text = status
				statusLabel.TextColor3 = if urgent then ALERT_STATUS_COLOR else NORMAL_STATUS_COLOR
			end
			if timerLabel and timerLabel:IsA("TextLabel") then
				timerLabel.Text = timer
			end
		end
	end
end

local function addSign(instance: Instance)
	if not instance:IsA("Model") or signs[instance] then
		return
	end
	signs[instance] = { model = instance, basePivot = instance:GetPivot() }
	updateText()
end

collectionService:GetInstanceAddedSignal(TAG):Connect(addSign)
collectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance: Instance)
	signs[instance :: Model] = nil
end)
for _, instance in collectionService:GetTagged(TAG) do
	addSign(instance)
end

-- Only this client sees the spin; the server copy stays put.
runService.RenderStepped:Connect(function()
	local t = os.clock()
	local spin = CFrame.Angles(0, (t / SPIN_SECONDS) * math.pi * 2, 0)
	local bob = Vector3.new(0, math.sin(t / BOB_SECONDS * math.pi * 2) * BOB_HEIGHT, 0)
	for _, sign in signs do
		sign.model:PivotTo((sign.basePivot + bob) * spin)
	end
end)

while true do
	updateText()
	task.wait(TICK_SECONDS)
end
