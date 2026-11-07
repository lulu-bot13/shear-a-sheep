--[[
	Replaces Roblox's loading screen and preloads every UI image and font with ContentProvider before the player can play.
	ContextActionService holds movement and jump until it's done, then the screen fades out.

	Location: ReplicatedFirst.LoadingScreen
]]--

--// Services
local contentProvider = game:GetService("ContentProvider")
local contextActionService = game:GetService("ContextActionService")
local players = game:GetService("Players")
local replicatedFirst = game:GetService("ReplicatedFirst")
local starterGui = game:GetService("StarterGui")
local tweenService = game:GetService("TweenService")

--// Configs
local FREEZE_ACTION = "LoadingScreenFreeze"
local FREEZE_INPUTS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
	Enum.KeyCode.Space, Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA,
}
local BATCH_SIZE = 10 -- assets per PreloadAsync call, so the bar moves while they load
local MIN_SECONDS = 1.5 -- shown at least this long so it doesn't flash
local MAX_SECONDS = 25 -- let the player in anyway if an asset never finishes
local FADE_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BACKGROUND_COLOR = Color3.fromRGB(122, 196, 92)
local BAR_COLOR = Color3.fromRGB(255, 255, 255)
local TRACK_COLOR = Color3.fromRGB(60, 110, 45)
local BUTTON_IMAGE_PROPERTIES = { "Image", "HoverImage", "PressedImage" }

--// Instances
local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--// Loading screen ----------------------------------------------------------------------

local startedAt = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false -- the character spawns while this is up
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Active, so touches on the screen don't reach the touch thumbstick underneath.
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = BACKGROUND_COLOR
background.BorderSizePixel = 0
background.Active = true
background.Parent = gui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.Position = UDim2.fromScale(0.5, 0.52)
statusLabel.Size = UDim2.fromScale(0.6, 0.08)
statusLabel.BackgroundTransparency = 1
statusLabel.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
statusLabel.TextScaled = true
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.Text = "Loading..."
statusLabel.Parent = background
local statusStroke = Instance.new("UIStroke")
statusStroke.Thickness = 3
statusStroke.Color = TRACK_COLOR
statusStroke.Parent = statusLabel

local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.fromScale(0.5, 0.56)
track.Size = UDim2.fromScale(0.4, 0.03)
track.BackgroundColor3 = TRACK_COLOR
track.BorderSizePixel = 0
track.Parent = background
Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = BAR_COLOR
fill.BorderSizePixel = 0
fill.Parent = track
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

gui.Parent = playerGui
replicatedFirst:RemoveDefaultLoadingScreen()

-- Sinks the default controls (bound at Default priority) until the screen is gone.
contextActionService:BindActionAtPriority(FREEZE_ACTION, function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, table.unpack(FREEZE_INPUTS))

local function setProgress(done: number, total: number)
	local ratio = if total > 0 then done / total else 1
	tweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(ratio, 1) }):Play()
	statusLabel.Text = `Loading... {math.floor(ratio * 100)}%`
end

--// Collecting the UI's assets -----------------------------------------------------------

-- Every distinct image id, plus one text object per font so each font file loads once.
local function collectAssets(): { any }
	local assets: { any } = {}
	local seen: { [string]: boolean } = {}

	local function add(key: string, asset: any)
		if key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(assets, asset)
		end
	end

	for _, root in { starterGui, playerGui } do
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("ImageLabel") then
				add(descendant.Image, descendant.Image)
			elseif descendant:IsA("ImageButton") then
				for _, property in BUTTON_IMAGE_PROPERTIES do
					local id = (descendant :: any)[property]
					if type(id) == "string" then
						add(id, id)
					end
				end
			elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				local font = descendant.FontFace
				add(`{font.Family}|{font.Weight.Name}|{font.Style.Name}`, descendant)
			end
		end
	end
	return assets
end

--// Loading ------------------------------------------------------------------------------

local finished = false

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end

	local assets = collectAssets()
	setProgress(0, #assets)
	for first = 1, #assets, BATCH_SIZE do
		local batch = table.move(assets, first, math.min(first + BATCH_SIZE - 1, #assets), 1, {})
		pcall(contentProvider.PreloadAsync, contentProvider, batch)
		setProgress(math.min(first + BATCH_SIZE - 1, #assets), #assets)
	end
	finished = true
end)

while not finished and os.clock() - startedAt < MAX_SECONDS do
	task.wait(0.1)
end
if not finished then
	warn(`[LoadingScreen] UI assets still loading after {MAX_SECONDS}s; letting the player in`)
end
task.wait(math.max(MIN_SECONDS - (os.clock() - startedAt), 0))

contextActionService:UnbindAction(FREEZE_ACTION)

background.Active = false
tweenService:Create(background, FADE_TWEEN, { BackgroundTransparency = 1 }):Play()
tweenService:Create(statusLabel, FADE_TWEEN, { TextTransparency = 1 }):Play()
tweenService:Create(statusStroke, FADE_TWEEN, { Transparency = 1 }):Play()
tweenService:Create(track, FADE_TWEEN, { BackgroundTransparency = 1 }):Play()
tweenService:Create(fill, FADE_TWEEN, { BackgroundTransparency = 1 }):Play()
task.wait(FADE_TWEEN.Time)
gui:Destroy()
