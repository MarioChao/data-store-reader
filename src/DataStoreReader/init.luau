--!strict

-- Data Store Reader


---------- Services ----------

local DataStoreService = game:GetService("DataStoreService")


---------- Constants ----------

local Constants = {}

Constants.allScopesDataStoreOptions = Instance.new("DataStoreOptions")
Constants.allScopesDataStoreOptions.AllScopes = true

Constants.maxThreadsCount = 10

table.freeze(Constants)


---------- Local functions ----------

local getDataStoreKeys


----- Data Store -----

getDataStoreKeys = function(dataStore: DataStore)
    local success, dataStoreKeyPages = pcall(function()
        return dataStore:ListKeysAsync()
    end)
    local result = {}
    if success then
        repeat
            local currentPage = dataStoreKeyPages:GetCurrentPage()
            for _, dataStoreKey: DataStoreKey in currentPage do
                table.insert(result, dataStoreKey.KeyName)
            end
            dataStoreKeyPages:AdvanceToNextPageAsync()
            task.wait()
        until dataStoreKeyPages.IsFinished
    end
    return result
end


---------- Module ----------

local Module = {}
Module.__index = Module


----- Type -----

type ClassData = {
    _completedCount: number,
    _keySize: number,
    _data: {[string]: any},
    _isFinishedReading: boolean,
}

export type ClassType = ClassData & typeof(Module)


----- Constructor -----

function Module.new(): ClassType
    local self = setmetatable({} :: any, Module) :: ClassType
    self._completedCount = 0
    self._keySize = 0
    self._data = {}
    self._isFinishedReading = false
    return self
end


----- Methods -----

function Module.readDataStore_allScopes(self: ClassType, name: string)
    self:readDataStore(name, "", Constants.allScopesDataStoreOptions)
end

function Module.readDataStore(self: ClassType, name: string, scope: string?, options: DataStoreOptions?)
    local success, result = pcall(function()
        local dataStore = DataStoreService:GetDataStore(name, scope, options)
        local dataStoreKeys = getDataStoreKeys(dataStore)
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
                    local success, data, _ = pcall(function()
                        return dataStore:GetAsync(key)
                    end)
                    if not success then
                        warn(`[DataStoreReader]: GetAsync failed: {data}`)
                        task.wait(10)
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
