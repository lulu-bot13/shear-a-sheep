--[[
	Fills StarterGui.Main.GoalTracker (Header, Title, Track.Fill, Track.Progress) from GoalHandler's GoalState and tweens the bar.
	Location: StarterPlayer.StarterPlayerScripts.Client.Controllers.GoalClient
]]--

--// Services
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

--// Modules
local network = require(replicatedStorage.Shared.Utils.Network)

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Configs
local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_SCALE = 1.12

type Tracker = {
	frame: Frame,
	header: TextLabel,
	title: TextLabel,
	fill: Frame,
	progress: TextLabel,
	scale: UIScale,
}

--// State
local ui: Tracker? = nil
local lastState: any = nil
local lastId: string? = nil

-- 1234 -> "1,234"
local function formatWithCommas(value: number): string
	local digits = tostring(math.floor(value))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function applyState(state: any)
	lastState = state
	local tracker = ui
	if not tracker then
		return
	end
	if type(state) ~= "table" or state.hidden then
		tracker.frame.Visible = false
		lastId = nil
		return
	end

	tracker.header.Text = state.header or "NEXT GOAL"
	tracker.title.Text = state.title or ""
	local target = math.max(tonumber(state.target) or 1, 1)
	local progress = math.clamp(tonumber(state.progress) or 0, 0, target)
	tracker.progress.Text = state.note or `{formatWithCommas(progress)} / {formatWithCommas(target)}`

	local fill = tracker.fill
	local isNew = state.id ~= lastId
	if isNew then
		fill.Size = UDim2.new(0, 0, fill.Size.Y.Scale, fill.Size.Y.Offset) -- each goal's bar starts empty
	end
	tweenService:Create(fill, FILL_TWEEN, { Size = UDim2.new(progress / target, 0, fill.Size.Y.Scale, fill.Size.Y.Offset) }):Play()

	tracker.frame.Visible = true
	if isNew then
		tracker.scale.Scale = POP_SCALE
		tweenService:Create(tracker.scale, POP_TWEEN, { Scale = 1 }):Play()
	end
	lastId = state.id
end

-- Main resets on spawn, so the tracker is found again in each new copy and shows the last state.
local function bind(gui: Instance)
	if gui.Name ~= "Main" or not gui:IsA("ScreenGui") then
		return
	end
	local frame = gui:WaitForChild("GoalTracker", 10)
	local header = frame and frame:WaitForChild("Header", 5)
	local title = frame and frame:WaitForChild("Title", 5)
	local track = frame and frame:WaitForChild("Track", 5)
	local fill = track and track:WaitForChild("Fill", 5)
	local progress = track and track:WaitForChild("Progress", 5)
	if not frame or not frame:IsA("Frame") or not header or not title or not fill or not fill:IsA("Frame") or not progress then
		warn("GoalClient: Main.GoalTracker needs Header, Title, Track.Fill and Track.Progress; build them in Studio.")
		return
	end

	local scale = frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = frame
	frame.Visible = false
	ui = {
		frame = frame,
		header = header :: TextLabel,
		title = title :: TextLabel,
		fill = fill,
		progress = progress :: TextLabel,
		scale = scale,
	}
	lastId = nil
	applyState(lastState)
end

playerGui.ChildAdded:Connect(bind)
local existing = playerGui:FindFirstChild("Main")
if existing then
	task.spawn(bind, existing)
end

network.waitUntilReadyAsync()

network.connectEvent(network.RemoteEvents.GoalState, applyState)
network.fireServer(network.RemoteEvents.RequestGoalState)
