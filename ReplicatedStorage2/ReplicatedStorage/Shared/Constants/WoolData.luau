--!strict

--[[
	How a sheep's wool looks as it is sheared, and the wool icon that flies to the wool counter.

	Location: ReplicatedStorage.Shared.Constants.WoolData
]]--

local woolData = {}

-- Image of one wool puff (an "rbxassetid://..." id) for the wool that flies to the wool counter. Empty = a plain white puff.
woolData.WoolIconImage = "rbxassetid://112199646421676"

--// Wool look on the sheep (server; the sheep's Torso mesh is its wool) -------------------

woolData.ShornTorsoScale = Vector3.new(0.9, 0.78, 0.78) -- Torso size at 0 wool, relative to full (X = body length)
woolData.ShornColor = Color3.fromRGB(240, 212, 196) -- bare-skin colour the wool fades towards
woolData.ShornColorBlend = 0.55 -- how far towards ShornColor the Torso gets at 0 wool

return woolData
