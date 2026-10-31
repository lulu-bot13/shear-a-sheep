--[[
	Plays the songs in SoundService.BackgroundMusic on loop, client side only: Halloween songs during Night, the rest otherwise.
	setEnabled / toggle turn the music on and off (for the settings menu).

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.BackgroundMusic
]]--

--// Services
local soundService = game:GetService("SoundService")

--// Configs
local WEATHER_ATTRIBUTE = "Weather"
local NIGHT = "Night"
local NIGHT_ONLY_SONGS = { ["Night of the Ghouls"] = true } -- the Halloween songs; only these play during Night

--// Instances
local musicGroup = soundService:WaitForChild("BackgroundMusic") :: SoundGroup

--// State
local songs: { Sound } = {}
local currentIndex = 0
local enabled = true
local started = false
local wasNight = false

local BackgroundMusic = {}

local function isNight(): boolean
	return workspace:GetAttribute(WEATHER_ATTRIBUTE) == NIGHT
end

local function canPlay(song: Sound): boolean
	return (NIGHT_ONLY_SONGS[song.Name] == true) == isNight()
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

-- Night starting or ending cuts the current song so the Halloween music swaps in (or out) straight away.
local function onWeatherChanged()
	local night = isNight()
	if night == wasNight then
		return
	end
	wasNight = night

	local song = songs[currentIndex]
	if song then
		song:Stop()
	end
	if enabled then
		playNext()
	end
end

function BackgroundMusic.start()
	if started then
		return
	end
	started = true
	wasNight = isNight()

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
