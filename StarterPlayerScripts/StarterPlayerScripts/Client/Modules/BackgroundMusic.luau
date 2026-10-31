--[[
	Plays every song in SoundService.BackgroundMusic one after another on loop (night-only songs just during Night), client side only.
	setEnabled / toggle turn the music on and off (for the settings menu).

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.BackgroundMusic
]]--

--// Services
local soundService = game:GetService("SoundService")

--// Configs
local WEATHER_ATTRIBUTE = "Weather"
local NIGHT = "Night"
local NIGHT_ONLY_SONGS = { ["Night of the Ghouls"] = true } -- skipped unless it's Night

--// Instances
local musicGroup = soundService:WaitForChild("BackgroundMusic") :: SoundGroup

--// State
local songs: { Sound } = {}
local currentIndex = 0
local enabled = true
local started = false

local BackgroundMusic = {}

local function canPlay(song: Sound): boolean
	return not NIGHT_ONLY_SONGS[song.Name] or workspace:GetAttribute(WEATHER_ATTRIBUTE) == NIGHT
end

local function playNext()
	for _ = 1, #songs do
		currentIndex = currentIndex % #songs + 1
		local song = songs[currentIndex]
		if canPlay(song) then
			song.TimePosition = 0
			song:Play()
			return
		end
	end
end

-- Night ending mid-song cuts a night-only song and moves on.
local function onWeatherChanged()
	local song = songs[currentIndex]
	if song and not canPlay(song) then
		song:Stop()
		if enabled then
			playNext()
		end
	end
end

function BackgroundMusic.start()
	if started then
		return
	end
	started = true

	for _, child in musicGroup:GetChildren() do
		if child:IsA("Sound") then
			table.insert(songs, child)
		end
	end
	table.sort(songs, function(a, b)
		return a.Name < b.Name
	end)

	for _, song in songs do
		-- Looped songs never fire Ended, so the playlist does the looping instead.
		song.Looped = false
		song.SoundGroup = musicGroup
		song.Ended:Connect(function()
			if enabled and song == songs[currentIndex] then
				playNext()
			end
		end)
	end

	workspace:GetAttributeChangedSignal(WEATHER_ATTRIBUTE):Connect(onWeatherChanged)

	if enabled then
		playNext()
	end
end

-- Pausing keeps the current song's spot, so turning music back on resumes it.
function BackgroundMusic.setEnabled(isEnabled: boolean)
	if enabled == isEnabled then
		return
	end
	enabled = isEnabled

	local song = songs[currentIndex]
	if not enabled then
		if song then
			song:Pause()
		end
	elseif song and canPlay(song) then
		song:Resume()
	elseif started then
		playNext()
	end
end

function BackgroundMusic.toggle(): boolean
	BackgroundMusic.setEnabled(not enabled)
	return enabled
end

function BackgroundMusic.isEnabled(): boolean
	return enabled
end

return BackgroundMusic
