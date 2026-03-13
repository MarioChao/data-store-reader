--!strict

-- DSR Test Script


---------- Imports ----------

local DataStoreReader = require(script.Parent.DataStoreReader)


---------- Local functions ----------


----- Main -----

local function main()
    local dataStoreReader = DataStoreReader.new()
    task.defer(function()
        dataStoreReader:readDataStore("TestedRank")
    end)
    while not dataStoreReader:getIsFinishedReading() do
        print(dataStoreReader._completedCount)
        task.wait()
    end
    print(dataStoreReader:getCurrentData())
end


---------- Calling function ----------

main()
