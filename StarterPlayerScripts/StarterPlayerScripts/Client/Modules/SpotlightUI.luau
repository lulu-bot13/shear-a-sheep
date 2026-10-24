--[[
	Tweens the Tutorial ScreenGui's Spotlight ring over a GuiObject, or follows a BasePart on screen.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.SpotlightUI
]]--

--// Services
local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")

local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local tutorialGui = playerGui:WaitForChild("Tutorial") :: ScreenGui
local spotlightFrame = tutorialGui:FindFirstChild("Spotlight") :: Frame
local stroke = spotlightFrame:FindFirstChild("UIStroke")
local corner = spotlightFrame:FindFirstChild("UICorner") :: UICorner

--// Configurations
local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local FRAME_SIZE_OFFSET = 0.01
local followSpeed = 12

local followConnection
local currentTarget = nil

local SpotlightUI = {}
local fadeInTween = tweenService:Create(stroke, tweenInfo, { Transparency = 0.5 })
local fadeOutTween = tweenService:Create(stroke, tweenInfo, { Transparency = 1 })

local function adjustSpotlight(shape: string)
	if shape == "Circle" then
		FRAME_SIZE_OFFSET = 0.02
		corner.CornerRadius = UDim.new(1,0)
	elseif shape == "Square" then
		corner.CornerRadius = UDim.new(0.1,0)
	end
end

function SpotlightUI:FocusUI(guiObject: GuiObject, shape: string?)
	if not guiObject then
		warn("No guiObject passed down")
		return
	end

	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end

	spotlightFrame.Visible = true

	if not shape then
		shape = "Square"
	end

	fadeInTween:Play()

	adjustSpotlight(shape)

	--[[
		This container holding the spotlight frame will
		be used as the reference point for the entire positioning
		of the spotlight.

		Getting the true position and size of each object
	]]
	local container = spotlightFrame.Parent :: GuiObject
	local containerPos = container.AbsolutePosition
	local containerSize = container.AbsoluteSize

	local targetPos = guiObject.AbsolutePosition
	local targetSize = guiObject.AbsoluteSize

	--[[
		This converts to the relative size of the guiObject
		to the container.
	]]
	local sizeX = targetSize.X / containerSize.X
	local sizeY = targetSize.Y / containerSize.Y

	--[[
		Getting the relative position of the target to the container.

		Subtracting because we need to figure out where the target
		is across the container not the whole screen.

		Dividing to get the scale oof the position.

		Subtracting first to get the position it is relative to the other object then
		dividing to normalize the value into scale.
	]]
	local relX = (targetPos.X - containerPos.X) / containerSize.X
	local relY = (targetPos.Y - containerPos.Y) / containerSize.Y

	-- Adding padding to the size of the spotlight frame
	local size = UDim2.fromScale(sizeX + FRAME_SIZE_OFFSET, sizeY + FRAME_SIZE_OFFSET)

	-- Recentering the spotlight so that the padding doesn't just go from the corner
	local pos = UDim2.fromScale(relX - FRAME_SIZE_OFFSET / 2, relY - FRAME_SIZE_OFFSET / 2)

	local goal = { Position = pos, Size = size }
	local tween = tweenService:Create(spotlightFrame, tweenInfo, goal)
	tween:Play()
end

function SpotlightUI:FollowPart(object: BasePart)
	if not object then
		warn(`No object was passed down.`)
		return
	end

	if currentTarget == object then
		print(`Same object`)
		return
	end
	currentTarget = object

	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end

	fadeInTween:Play()

	local container = spotlightFrame.Parent :: GuiObject

	followConnection = runService.RenderStepped:Connect(function(deltaTime: number)
		local camera = workspace.CurrentCamera
		local screenPoint, onScreen = camera:WorldToScreenPoint(object.Position)

		if not onScreen then
			print(`Off screen`)
			return
		end

		local containerPos = container.AbsolutePosition
		local containerSize = container.AbsoluteSize

		local relX = (screenPoint.X - containerPos.X) / containerSize.X

		-- Adjusting the position of the spotlight frame
		if object.Name == "IndicatorLine" then
			spotlightFrame.Size = UDim2.fromScale(0.1, 0.75)
		end
		local widthOffset = spotlightFrame.Size.X.Scale / 2
		local targetPosition = UDim2.fromScale(relX - widthOffset, 0.2)

		spotlightFrame.Position = targetPosition
	end)
end

function SpotlightUI:Cleanup()
	fadeOutTween:Play()
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

return SpotlightUI
