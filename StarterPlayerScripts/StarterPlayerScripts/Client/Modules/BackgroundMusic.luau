--[[
	Plays every song in SoundService.BackgroundMusic one after another on loop, client side only.
	setEnabled / toggle turn the music on and off (for the settings menu).

	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.BackgroundMusic
]]--

--// Services
local soundService = game:GetService("SoundService")

--// Instances
local musicGroup = soundService:WaitForChild("BackgroundMusic") :: SoundGroup

--// State
local songs: { Sound } = {}
local currentIndex = 0
local enabled = true
local started = false

local BackgroundMusic = {}

local function playNext()
	if #songs == 0 then
		return
	end
	currentIndex = currentIndex % #songs + 1
	local song = songs[currentIndex]
	song.TimePosition = 0
	song:Play()
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
	elseif song then
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
