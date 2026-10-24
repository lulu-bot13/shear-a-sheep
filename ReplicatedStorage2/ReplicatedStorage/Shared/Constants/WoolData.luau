--!strict

--[[
	How a sheep's wool looks as it is sheared, and the wool icon that flies to the wool counter.

	Location: ReplicatedStorage.Shared.Constants.WoolData
]]--

local woolData = {}

-- Image of one wool puff (an "rbxassetid://..." id) for the wool that flies to the wool counter. Empty = a plain white puff.
woolData.WoolIconImage = "rbxassetid://112199646421676"

--// Wool look on the sheep (server; a "Wool" part if the sheep has one, else its Torso mesh) -----

woolData.ShornWoolScale = Vector3.new(0.75, 0.6, 0.6) -- Wool part size just before it comes off at 0 wool

woolData.ShornTorsoScale = Vector3.new(0.9, 0.78, 0.78) -- Torso size at 0 wool, relative to full (X = body length)
woolData.ShornColor = Color3.fromRGB(255, 160, 185) -- pink bare-skin colour the wool fades towards
woolData.ShornColorBlend = 1 -- how far towards ShornColor the Torso gets at 0 wool (1 = fully pink)

--// Bare sheep vanishing (server; plays once a sheep reaches 0 wool) ----------------------

woolData.VanishDelay = 1 -- seconds the bare sheep stands still before it is gone

return woolData
