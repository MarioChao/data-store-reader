--!strict

-- Data Store Reader


---------- Services ----------

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")


---------- Constants ----------

local Constants = {}

Constants.allScopesDataStoreOptions = Instance.new("DataStoreOptions")
Constants.allScopesDataStoreOptions.AllScopes = true

Constants.dataStoreFailRetryTime = 10

Constants.memoryStoreKeyNames = {
    getKeys = "_GetKeys",
}
Constants.memoryStoreStates = {
    waitForData = "_WaitForData",
}
Constants.memoryStoreRetryTime = 2
Constants.memoryStoreFetchTime = 32

Constants.maxThreadsCount = 10

table.freeze(Constants)


---------- Local functions ----------

local getDataStoreKeys_raw

local getMemoryStoreHashMap
local getSecondsUntilNextHour
local waitAndGetValueFromMemoryStoreHashMap
local setMemoryStoreValue

local cached_dataStore_getKeys
local cached_dataStore_getAsync


----- Data store api -----

getDataStoreKeys_raw = function(dataStore: DataStore)
    local success, dataStoreKeyPages = pcall(function()
        return dataStore:ListKeysAsync()
    end)
    local result = {}
    if success then
        while true do
            local currentPage = dataStoreKeyPages:GetCurrentPage()
            for _, dataStoreKey: DataStoreKey in currentPage do
                table.insert(result, dataStoreKey.KeyName)
            end
            if dataStoreKeyPages.IsFinished then
                break
            end
            dataStoreKeyPages:AdvanceToNextPageAsync()
            task.wait()
        end
    end
    return success, result
end


----- Memory store -----

getMemoryStoreHashMap = function(dataStore: DataStore)
    local name = `DataStore_{dataStore.Name}`
    return MemoryStoreService:GetHashMap(name)
end

getSecondsUntilNextHour = function()
    local unixTimestamp = DateTime.now().UnixTimestamp
    return 3600 - unixTimestamp % 3600
end

waitAndGetValueFromMemoryStoreHashMap = function(memoryStoreHashMap: MemoryStoreHashMap, key: string)
    local success, pcallResult
    while true do
        success, pcallResult = pcall(function()
            return memoryStoreHashMap:GetAsync(key)
        end)
        local isWaiting = false
        if success and pcallResult then
            isWaiting = (pcallResult == Constants.memoryStoreStates.waitForData)
        end
        if not (success and (not isWaiting)) then
            task.wait(Constants.memoryStoreRetryTime)
        else
            break
        end
    end
    return success, pcallResult
end

setMemoryStoreValue = function(memoryStoreHashMap: MemoryStoreHashMap, key: string, value: any, expirationTimeFn: () -> number)
    local success
    repeat
        success = pcall(function()
            memoryStoreHashMap:SetAsync(key, value, expirationTimeFn())
        end)
        if not success then
            task.wait(Constants.memoryStoreRetryTime)
        end
    until success
end


----- Cached data store -----

cached_dataStore_getKeys = function(dataStore: DataStore, expirationTimeFn: () -> number)
    local memoryStoreHashMap = getMemoryStoreHashMap(dataStore)
    local key = Constants.memoryStoreKeyNames.getKeys
    local result

    -- Get from memory store
    local success, pcallResult = waitAndGetValueFromMemoryStoreHashMap(memoryStoreHashMap, key)

    -- Check memory store or get from data store
    if success and pcallResult then
        result = pcallResult
    end

    -- If invalid, get from data store
    if not (success and result) then
        setMemoryStoreValue(
            memoryStoreHashMap,
            key, Constants.memoryStoreStates.waitForData, function() return Constants.memoryStoreFetchTime end
        )
        success, result = getDataStoreKeys_raw(dataStore)
        if success then
            setMemoryStoreValue(
                memoryStoreHashMap,
                key, result, expirationTimeFn
            )
        end
    end

    -- Return result
    return success, result
end

cached_dataStore_getAsync = function(dataStore: DataStore, key: string, expirationTimeFn: () -> number)
    local memoryStoreHashMap = getMemoryStoreHashMap(dataStore)
    local result

    -- Get from memory store
    local success, pcallResult = waitAndGetValueFromMemoryStoreHashMap(memoryStoreHashMap, key)

    -- Check memory store
    if success and pcallResult then
        result = pcallResult
    end

    -- If invalid, get from data store
    if not (success and result) then
        setMemoryStoreValue(
            memoryStoreHashMap,
            key, Constants.memoryStoreStates.waitForData, function() return Constants.memoryStoreFetchTime end
        )
        success, result = pcall(function()
            return dataStore:GetAsync(key)
        end)
        if success then
            setMemoryStoreValue(
                memoryStoreHashMap,
                key, result, expirationTimeFn
            )
        end
    end

    -- Return result
    return success, result
end


---------- Module ----------

local Module = {}
Module.__index = Module


----- Type -----

type ClassData = {
    _expirationTimeFn: () -> number,
    _completedCount: number,
    _keySize: number,
    _data: {[string]: any},
    _isFinishedReading: boolean,
}

export type ClassType = ClassData & typeof(Module)


----- Constructor -----

function Module.new(): ClassType
    local self = setmetatable({} :: any, Module) :: ClassType
    self._expirationTimeFn = getSecondsUntilNextHour
    self._completedCount = 0
    self._keySize = 0
    self._data = {}
    self._isFinishedReading = false
    return self
end


----- Methods -----

--[[
Sets the function for returning the expiration time (seconds) for the cache.
]]
function Module.setExpirationTimeFunction(self: ClassType, expirationTimeFn: () -> number)
    self._expirationTimeFn = expirationTimeFn
end

function Module.readDataStore_allScopes(self: ClassType, name: string)
    self:readDataStore(name, "", Constants.allScopesDataStoreOptions)
end

function Module.readDataStore(self: ClassType, name: string, scope: string?, options: DataStoreOptions?)
    local success, result = pcall(function()
        -- Get data store
        local dataStore = DataStoreService:GetDataStore(name, scope, options)

        -- Get keys
        local success
        local dataStoreKeys
        repeat
            success, dataStoreKeys = cached_dataStore_getKeys(dataStore, self._expirationTimeFn)
            if not success then
                warn(`[DataStoreReader]: Get keys failed: {dataStoreKeys}`)
                task.wait(Constants.dataStoreFailRetryTime)
            end
        until success

        -- Read data store
        self:_readDataStoreDataFromKeys(dataStore, dataStoreKeys)
    end)

    if not success then
        warn(`[DataStoreReader]: Error while reading data store: {result}`)
    end
end

function Module._readDataStoreDataFromKeys(self: ClassType, dataStore: DataStore, keyNames: {string})
    -- Get overall data
    local keySize = #keyNames
    local batchSize = math.max(math.ceil(keySize / Constants.maxThreadsCount), 1)
    self._keySize = keySize
    self._data = {} :: {[string]: any}
    self._isFinishedReading = false

    -- Get data by batches in threads
    local index = 0
    self._completedCount = 0
    local batch = {} :: {string}
    for _, rawKey in keyNames do
        index += 1
        table.insert(batch, rawKey)
        if #batch >= batchSize or index == keySize then
            local threadBatch = batch
            batch = {}
            task.defer(function()
                local threadSize = #threadBatch
                local threadIndex = 1
                while threadIndex <= threadSize do
                    local key = threadBatch[threadIndex]
                    local success, data = cached_dataStore_getAsync(dataStore, key, self._expirationTimeFn)
                    if not success then
                        warn(`[DataStoreReader]: GetAsync failed: {data}`)
                        task.wait(Constants.dataStoreFailRetryTime)
                    else
                        self._data[key] = data
                        self._completedCount += 1
                        threadIndex += 1
                    end
                    task.wait()
                end
            end)
        end
    end
    while self._completedCount < keySize do
        task.wait()
    end
    self._isFinishedReading = true
end

function Module.getCurrentData(self: ClassType)
    return self._data
end

function Module.getIsFinishedReading(self: ClassType)
    return self._isFinishedReading
end


---------- Return module ----------

table.freeze(Module)
return Module
