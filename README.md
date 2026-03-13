# data-store-reader

Module class for reading all of datastore.

DataStoreReader api:
- `new()`: constructs a new DataStoreReader object.
- `:readDataStore_allScopes(name)`: reads a data store (all scopes).
- `:readDataStore(name, scope, options)`: reads a data store with the specified parameters.
- `:getCurrentData()`: gets the data currently read & stored in the object.
- `:getIsFinishedReading()`: gets whether the DataStoreReader has finished reading a data store.

