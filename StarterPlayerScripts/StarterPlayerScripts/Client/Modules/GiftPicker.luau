--[[
	Drives a gift window: one row per other player cloned from PlayerList.Template, picking a row, rows that can't receive the item locked, and the gift price on Buy.
	Location: StarterPlayer.StarterPlayerScripts.Client.Modules.GiftPicker
]]--

--// Services
local players = game:GetService("Players")

--// Modules
local ShopCardBinder = require(script.Parent.ShopCardBinder)

--// Configs
local ROBUX_GLYPH = "\u{E002}"
local EMPTY_TEXT = "No one else is in this server to gift to!"
local SELECTED_STROKE_COLOR = Color3.fromRGB(85, 255, 85)
local SELECTED_STROKE_EXTRA = 2 -- added to the row's Studio UIStroke thickness while it's picked
local NEW_TEXT_COLOR = Color3.new(1, 1, 1)
local NEW_TEXT_STROKE_COLOR = Color3.new(0, 0, 0)

export type Options = {
	frame: GuiObject, -- the gift window: Exit, PlayerList (with Template), Buy (with Label) and Tip
	onConfirm: (item: ShopCardBinder.Item, recipientUserId: number) -> (),
	getLocksAsync: ((item: ShopCardBinder.Item) -> { [number]: string })?, -- userId -> text on the row of a player who can't receive it ("OWNED")
	formatPrice: ((price: number) -> string)?, -- default "Gift <glyph> <price>"
}

export type Picker = {
	open: (item: ShopCardBinder.Item) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	getItem: () -> ShopCardBinder.Item?,
}

type Row = {
	button: GuiButton,
	userName: TextLabel?,
	stroke: UIStroke?,
	strokeColor: Color3,
	strokeThickness: number,
	lockText: string?,
}

type TextLook = { text: string, color: Color3, stroke: UIStroke, strokeColor: Color3, strokeAdded: boolean }

local GiftPicker = {}

local function findChild(parent: Instance, name: string, className: string): any
	local child = parent:FindFirstChild(name)
	return if child and child:IsA(className) then child else nil
end

-- Text set from code is white with a black stroke; nil puts the label's Studio text, colour and stroke back.
local looks: { [TextLabel]: TextLook } = {}
local function setNewText(label: TextLabel, text: string?)
	local look = looks[label]
	if not look then
		local stroke = label:FindFirstChildOfClass("UIStroke")
		local added = stroke == nil
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Thickness = 1.5
			stroke.Enabled = false
			stroke.Parent = label
		end
		look = {
			text = label.Text,
			color = label.TextColor3,
			stroke = stroke :: UIStroke,
			strokeColor = (stroke :: UIStroke).Color,
			strokeAdded = added,
		}
		looks[label] = look
	end

	local isNew = text ~= nil
	label.Text = text or look.text
	label.TextColor3 = if isNew then NEW_TEXT_COLOR else look.color
	look.stroke.Color = if isNew then NEW_TEXT_STROKE_COLOR else look.strokeColor
	if look.strokeAdded then
		look.stroke.Enabled = isNew
	end
end

function GiftPicker.new(options: Options): Picker
	local frame = options.frame
	local list = frame:WaitForChild("PlayerList")
	local template = list:WaitForChild("Template") :: GuiButton
	local buyButton = frame:WaitForChild("Buy") :: GuiButton
	local buyLabel = findChild(buyButton, "Label", "TextLabel") :: TextLabel?
	local tipLabel = findChild(frame, "Tip", "TextLabel") :: TextLabel?
	local exitButton = findChild(frame, "Exit", "GuiButton") :: GuiButton?
	local buyText = if buyLabel then buyLabel.Text else ""
	local formatPrice = options.formatPrice or function(price: number): string
		return `{buyText} {ROBUX_GLYPH} {price}`
	end

	local rows: { [Player]: Row } = {}
	local currentItem: ShopCardBinder.Item? = nil
	local selected: Player? = nil
	local openToken = 0

	template.Visible = false
	frame.Visible = false

	local function render()
		local count = 0
		for rowPlayer, row in rows do
			count += 1
			local isPicked = rowPlayer == selected
			if row.stroke then
				row.stroke.Color = if isPicked then SELECTED_STROKE_COLOR else row.strokeColor
				row.stroke.Thickness = if isPicked then row.strokeThickness + SELECTED_STROKE_EXTRA else row.strokeThickness
			end
			if row.userName then
				setNewText(row.userName, row.lockText)
			end
			ShopCardBinder.setButtonEnabled(row.button, row.lockText == nil)
		end

		if tipLabel then
			setNewText(tipLabel, if count == 0 then EMPTY_TEXT else nil)
		end
		ShopCardBinder.setButtonEnabled(buyButton, selected ~= nil and rows[selected] ~= nil)
	end

	local function pickRow(rowPlayer: Player)
		local row = rows[rowPlayer]
		if row and not row.lockText then
			selected = rowPlayer
			render()
		end
	end

	local function addRow(rowPlayer: Player)
		if rowPlayer == players.LocalPlayer or rows[rowPlayer] then
			return
		end

		local button = template:Clone()
		button.Name = rowPlayer.Name
		local display = findChild(button, "PlayerDisplay", "TextLabel") :: TextLabel?
		local userName = findChild(button, "UserName", "TextLabel") :: TextLabel?
		local headshot = findChild(button, "PlayerHeadshot", "ImageLabel") :: ImageLabel?
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if display then
			display.Text = rowPlayer.DisplayName
		end
		if userName then
			userName.Text = `@{rowPlayer.Name}`
		end

		local row: Row = {
			button = button,
			userName = userName,
			stroke = stroke,
			strokeColor = if stroke then stroke.Color else SELECTED_STROKE_COLOR,
			strokeThickness = if stroke then stroke.Thickness else 0,
			lockText = nil,
		}
		rows[rowPlayer] = row

		button.Activated:Connect(function()
			pickRow(rowPlayer)
		end)
		button.Visible = true
		button.Parent = list

		if headshot then
			task.spawn(function()
				local success, image = pcall(
					players.GetUserThumbnailAsync,
					players,
					rowPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
				if success and headshot.Parent then
					headshot.Image = image
				end
			end)
		end
	end

	local function removeRow(rowPlayer: Player)
		local row = rows[rowPlayer]
		if not row then
			return
		end
		rows[rowPlayer] = nil
		if row.userName then
			looks[row.userName] = nil
		end
		row.button:Destroy()
		if selected == rowPlayer then
			selected = nil
		end
	end

	-- Locks the rows of players who can't receive the item (asked again each time, as passes can be bought meanwhile).
	local function refreshLocks()
		local item = currentItem
		if not item or not options.getLocksAsync then
			return
		end
		local token = openToken
		local locks = options.getLocksAsync(item)
		if token ~= openToken then
			return
		end
		for rowPlayer, row in rows do
			row.lockText = locks[rowPlayer.UserId]
			if row.lockText and selected == rowPlayer then
				selected = nil
			end
		end
		render()
	end

	local function showPrice(item: ShopCardBinder.Item)
		if buyLabel then
			buyLabel.Text = buyText
		end
		local token = openToken
		task.spawn(function()
			local price = ShopCardBinder.getPriceAsync(item.giftProductId, "DevProduct")
			if price and buyLabel and token == openToken then
				buyLabel.Text = formatPrice(price)
			end
		end)
	end

	local function close()
		openToken += 1
		currentItem = nil
		selected = nil
		frame.Visible = false
	end

	local picker: Picker = {
		open = function(item: ShopCardBinder.Item)
			openToken += 1
			currentItem = item
			selected = nil
			for _, row in rows do
				row.lockText = nil
			end
			render()
			showPrice(item)
			frame.Visible = true
			task.spawn(refreshLocks)
		end,
		close = close,
		isOpen = function()
			return frame.Visible
		end,
		getItem = function()
			return currentItem
		end,
	}

	buyButton.Activated:Connect(function()
		local item = currentItem
		if item and selected and rows[selected] and not rows[selected].lockText then
			options.onConfirm(item, selected.UserId)
		end
	end)
	if exitButton then
		exitButton.Activated:Connect(close)
	end

	players.PlayerAdded:Connect(function(newPlayer: Player)
		addRow(newPlayer)
		if currentItem then
			render()
			task.spawn(refreshLocks)
		end
	end)
	players.PlayerRemoving:Connect(function(leavingPlayer: Player)
		removeRow(leavingPlayer)
		if currentItem then
			render()
		end
	end)
	for _, otherPlayer in players:GetPlayers() do
		addRow(otherPlayer)
	end

	return picker
end

return GiftPicker
