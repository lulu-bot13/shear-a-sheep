--!strict

--[[
	The monetization kit's save-data adapter for ProfileService: data access, capped id records (purchase ids) confirmed through MetaTagsLatest,
	and messages to any player's save through GlobalUpdates, applied exactly once when that save is loaded.

	Location: ServerScriptService.Modules.Utils.ProfileServiceStore
]]--

--// Services
local players = game:GetService("Players")

--// Configs
local SAVE_POLL_SECONDS = 0.5

-- What the game hands over: its ProfileStore and loaded profiles, plus (optionally) its own get/set so its mirroring and Changed signals still run.
export type Options = {
	profileStore: any, -- from ProfileService.GetProfileStore
	profileKey: (userId: number) -> string, -- the key a player's profile is saved under
	getProfile: (player: Player) -> any, -- the player's loaded profile, or nil
	loaded: any, -- signal with :Connect, fired (player) once a profile is loaded
	changed: any?, -- signal with :Connect, fired (player, key, value) when a value changes
	get: ((player: Player, key: string) -> any)?, -- default: profile.Data[key]
	set: ((player: Player, key: string, value: any) -> ())?, -- default: profile.Data[key] = value
}

-- The interface every kit module uses; a game on another save system implements this same table.
export type Store = {
	isLoaded: (player: Player) -> boolean,
	waitForData: (player: Player) -> boolean, -- yields; false if they left first
	get: (player: Player, key: string) -> any,
	set: (player: Player, key: string, value: any) -> (),
	update: (player: Player, key: string, transform: (any) -> any) -> any,
	-- Capped id lists saved with the data, e.g. processed PurchaseIds.
	hasRecord: (player: Player, tag: string, id: string) -> boolean,
	addRecord: (player: Player, tag: string, id: string, cap: number) -> boolean,
	waitForRecordSaved: (player: Player, tag: string, id: string, timeout: number?) -> boolean, -- yields
	-- Offline delivery: a message saved into any user's data, handed to the handler once their save is loaded.
	sendToUser: (userId: number, message: { [string]: any }) -> boolean, -- yields
	setMessageHandler: (handler: (player: Player, message: any) -> boolean) -> (),
	onLoaded: (callback: (player: Player) -> ()) -> (),
	onChanged: (callback: (player: Player, key: string, value: any) -> ()) -> (),
}

local ProfileServiceStore = {}

function ProfileServiceStore.new(options: Options): Store
	local attached: { [Player]: any } = {}
	local messageHandler: ((Player, any) -> boolean)? = nil

	local function getActiveProfile(player: Player): any
		local profile = options.getProfile(player)
		return if profile and profile:IsActive() then profile else nil
	end

	--// Global updates -------------------------------------------------------------

	-- A locked update is cleared in the same save as whatever the handler changed, so it's applied exactly once.
	local function handleLockedUpdate(player: Player, profile: any, updateId: number, updateData: any)
		if not messageHandler or not profile:IsActive() then
			return
		end
		local success, handled = pcall(messageHandler, player, updateData)
		if not success then
			warn(`ProfileServiceStore: applying a message to {player.Name}'s save failed: {handled}`)
		elseif handled then
			profile.GlobalUpdates:ClearLockedUpdate(updateId)
		end
	end

	local function processLockedUpdates(player: Player, profile: any)
		for _, update in profile.GlobalUpdates:GetLockedUpdates() do
			handleLockedUpdate(player, profile, update[1], update[2])
		end
	end

	local function attach(player: Player)
		local profile = getActiveProfile(player)
		if not profile or attached[player] == profile then
			return
		end
		attached[player] = profile

		local globalUpdates = profile.GlobalUpdates
		for _, update in globalUpdates:GetActiveUpdates() do
			globalUpdates:LockActiveUpdate(update[1])
		end
		processLockedUpdates(player, profile)

		globalUpdates:ListenToNewActiveUpdate(function(updateId: number)
			globalUpdates:LockActiveUpdate(updateId)
		end)
		globalUpdates:ListenToNewLockedUpdate(function(updateId: number, updateData: any)
			handleLockedUpdate(player, profile, updateId, updateData)
		end)
	end

	options.loaded:Connect(attach)
	players.PlayerRemoving:Connect(function(player: Player)
		attached[player] = nil
	end)
	for _, player in players:GetPlayers() do
		task.spawn(attach, player)
	end

	--// Store ------------------------------------------------------------------------

	local store = {} :: Store

	function store.isLoaded(player: Player): boolean
		return getActiveProfile(player) ~= nil
	end

	function store.waitForData(player: Player): boolean
		while player.Parent and not store.isLoaded(player) do
			task.wait()
		end
		return store.isLoaded(player)
	end

	function store.get(player: Player, key: string): any
		if options.get then
			return options.get(player, key)
		end
		local profile = getActiveProfile(player)
		return if profile then profile.Data[key] else nil
	end

	function store.set(player: Player, key: string, value: any)
		if options.set then
			options.set(player, key, value)
			return
		end
		local profile = getActiveProfile(player)
		if profile then
			profile.Data[key] = value
		end
	end

	-- Sets the key to transform(current value) and returns it; transform should return a new table, not edit the old one.
	function store.update(player: Player, key: string, transform: (any) -> any): any
		local value = transform(store.get(player, key))
		store.set(player, key, value)
		return value
	end

	function store.hasRecord(player: Player, tag: string, id: string): boolean
		local profile = getActiveProfile(player)
		local records = profile and profile:GetMetaTag(tag)
		return type(records) == "table" and table.find(records, id) ~= nil
	end

	-- Kept in MetaTags, which save with the data, so a record and the grant it guards can never be saved apart.
	function store.addRecord(player: Player, tag: string, id: string, cap: number): boolean
		local profile = getActiveProfile(player)
		if not profile then
			return false
		end
		local records = profile:GetMetaTag(tag)
		if type(records) ~= "table" then
			records = {}
		end
		if not table.find(records, id) then
			while #records >= cap do
				table.remove(records, 1)
			end
			table.insert(records, id)
			profile:SetMetaTag(tag, records)
		end
		return true
	end

	-- Asks for a save and yields until MetaTagsLatest has the record; false if the profile is released (or `timeout` passes) first.
	function store.waitForRecordSaved(player: Player, tag: string, id: string, timeout: number?): boolean
		local profile = getActiveProfile(player)
		if not profile then
			return false
		end
		local function isSaved(): boolean
			local latest = profile.MetaData.MetaTagsLatest
			local savedIds = latest and latest[tag]
			return type(savedIds) == "table" and table.find(savedIds, id) ~= nil
		end

		profile:Save()
		local deadline = if timeout then os.clock() + timeout else math.huge
		while not isSaved() do
			if not profile:IsActive() or os.clock() > deadline then
				return isSaved()
			end
			task.wait(SAVE_POLL_SECONDS)
		end
		return true
	end

	function store.sendToUser(userId: number, message: { [string]: any }): boolean
		local success, result = pcall(function()
			return options.profileStore:GlobalUpdateProfileAsync(options.profileKey(userId), function(globalUpdates: any)
				globalUpdates:AddActiveUpdate(message)
			end)
		end)
		if not success then
			warn(`ProfileServiceStore: sending a message to {userId} failed: {result}`)
		end
		return success and result ~= nil
	end

	function store.setMessageHandler(handler: (Player, any) -> boolean)
		messageHandler = handler
		for player, profile in attached do
			processLockedUpdates(player, profile)
		end
	end

	function store.onLoaded(callback: (Player) -> ())
		options.loaded:Connect(callback)
	end

	function store.onChanged(callback: (Player, string, any) -> ())
		if options.changed then
			options.changed:Connect(callback)
		else
			warn("ProfileServiceStore: onChanged needs the `changed` option")
		end
	end

	return store
end

return ProfileServiceStore
