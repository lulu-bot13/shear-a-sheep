--!strict

--[[
	Generic per-key object pool: acquire() hands back a previously released
	instance for that (poolName, key) if one is free, otherwise nil (the
	caller clones/creates a fresh one). release() parks an instance in a
	hidden ServerStorage holder instead of destroying it, ready for reuse.

	Used to avoid repeated Clone()/Destroy() churn for frequently spawned
	objects -- sheep models per species, SheepHUD billboards, etc.

	Location: ServerScriptService.Modules.Utils.ObjectPool
]]--

local serverStorage = game:GetService("ServerStorage")

local pools: { [string]: { [any]: { Instance } } } = {}
local holder: Folder? = nil

local ObjectPool = {}

local function getHolder(): Folder
	if holder and holder.Parent then
		return holder
	end

	local existing = serverStorage:FindFirstChild("_ObjectPoolHolder")
	if existing and existing:IsA("Folder") then
		holder = existing
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "_ObjectPoolHolder"
	folder.Parent = serverStorage
	holder = folder
	return folder
end

local function getBucket(poolName: string, key: any): { Instance }
	local pool = pools[poolName]
	if not pool then
		pool = {}
		pools[poolName] = pool
	end

	local bucket = pool[key]
	if not bucket then
		bucket = {}
		pool[key] = bucket
	end

	return bucket
end

--[[
	Returns a pooled instance for (poolName, key) if one is free, or nil if
	the pool is empty (caller should Clone/Instance.new a fresh one instead).
]]--
function ObjectPool.acquire(poolName: string, key: any): Instance?
	local bucket = getBucket(poolName, key)

	while #bucket > 0 do
		local instance = table.remove(bucket)
		if instance and instance.Parent then
			return instance
		end
		-- Instance was destroyed elsewhere while pooled; skip it and keep looking.
	end

	return nil
end

--[[
	Parks an instance in the pool for later reuse instead of destroying it.

	@param resetFn Optional cleanup run before parking (strip attributes,
		disconnect listeners, remove one-off children). If it errors, the
		instance is destroyed instead of pooled, so a bad reset never leaves a
		broken object waiting to be handed back out.
]]--
function ObjectPool.release(poolName: string, key: any, instance: Instance, resetFn: ((Instance) -> ())?)
	if resetFn then
		local ok = pcall(resetFn, instance)
		if not ok then
			instance:Destroy()
			return
		end
	end

	instance.Parent = getHolder()
	table.insert(getBucket(poolName, key), instance)
end

-- Number of idle instances currently waiting in a bucket (diagnostics/tests).
function ObjectPool.idleCount(poolName: string, key: any): number
	return #getBucket(poolName, key)
end

return ObjectPool
