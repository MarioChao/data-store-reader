# Changelogs

## [v0.0.0] First version | 2026/03/12

Rudimentary version of Data Store Reader:
- Reads all keys then retrieves all associated data from a data store.
- Runs `GetAsync()` in a maximum of 10 threads.
- Retries `GetAsync()` every 10 seconds when it fails.
- Methods like `:readDataStore()`, `:getCurrentData()`, and `:getIsFinishedReading()`.
