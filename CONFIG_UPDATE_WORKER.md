# ConfigUpdateWorker Documentation

## Overview

The `ConfigApi.ConfigUpdateWorker` is a GenServer that receives and logs configuration update messages every time a config value is changed via the REST API. It provides detailed audit logging with timestamps, old values, and new values.

## Features

- **Asynchronous Logging**: Non-blocking message processing that doesn't impact HTTP request performance
- **Detailed Information**: Logs config name, old value, new value, and ISO 8601 timestamps
- **Named Process**: Registered as `:config_update_worker` for easy message sending
- **Error Resilience**: Worker failures don't affect config update operations

## Architecture Integration

```
HTTP PUT /config/:name → Router → ConfigStore.put/2 → Worker Message → Logger
```

### Files Modified/Created

1. **New File**: [`lib/config_api/config_update_worker.ex`](lib/config_api/config_update_worker.ex) - GenServer implementation
2. **Modified**: [`lib/config_api/ConfigStore.ex`](lib/config_api/ConfigStore.ex) - Added notification messaging
3. **Modified**: [`lib/config_api/application.ex`](lib/config_api/application.ex) - Added worker to supervision tree

## Message Protocol

### Message Format
```elixir
{:config_updated, name, old_value, new_value, timestamp}
```

### Parameters
- `name`: String - Configuration key name
- `old_value`: String | nil - Previous value (nil for new configs)
- `new_value`: String - New configuration value  
- `timestamp`: DateTime.t() - UTC timestamp when update occurred

### Example Messages
```elixir
# New configuration
{:config_updated, "database_url", nil, "postgres://localhost/mydb", ~U[2025-09-08 08:20:12.405220Z]}

# Updated configuration  
{:config_updated, "database_url", "postgres://localhost/mydb", "postgres://production/mydb", ~U[2025-09-08 08:20:38.495306Z]}
```

## Log Output Format

```
Config updated at <ISO8601_TIMESTAMP>: name=<CONFIG_NAME>, old_value=<OLD_VALUE>, new_value=<NEW_VALUE>
```

### Example Log Entries
```
[info] Config updated at 2025-09-08T08:20:12.405220Z: name=database_url, old_value=nil, new_value=postgres://localhost/mydb

[info] Config updated at 2025-09-08T08:20:38.495306Z: name=database_url, old_value=postgres://localhost/mydb, new_value=postgres://production/mydb

[info] Config updated at 2025-09-08T08:21:03.035595Z: name=api_timeout, old_value=nil, new_value=5000
```

## API Integration

### REST Endpoint
- **Method**: PUT
- **Path**: `/config/:name`
- **Body**: `{"value": "your_config_value"}`

### Example Usage
```bash
# Create new config (old_value=nil)
curl -X PUT http://localhost:4000/config/database_url \
     -H "Content-Type: application/json" \
     -d '{"value":"postgres://localhost/mydb"}'

# Update existing config (old_value captured)
curl -X PUT http://localhost:4000/config/database_url \
     -H "Content-Type: application/json" \
     -d '{"value":"postgres://production/mydb"}'
```

## Implementation Details

### ConfigUpdateWorker GenServer

#### Client API
```elixir
# Start the worker (called by supervisor)
ConfigApi.ConfigUpdateWorker.start_link([])

# Send notification (called by ConfigStore)
ConfigApi.ConfigUpdateWorker.notify_config_update(name, old_value, new_value)
```

#### Server Callbacks
- `init/1`: Initializes empty state and logs startup
- `handle_info/2`: Processes config update messages and logs them
- `handle_info/2`: Handles unexpected messages with warnings

### ConfigStore Integration

The [`ConfigStore.put/2`](lib/config_api/ConfigStore.ex:13) function was enhanced to:

1. **Retrieve Old Value**: Query existing value before update
2. **Perform Update**: Execute Memento transaction
3. **Send Notification**: Async message to worker with timestamp

```elixir
def put(name, value) do
  # Get old value before update
  old_value = case get(name) do
    {:ok, val} -> val
    {:error, :not_found} -> nil
  end

  # Perform update in transaction
  Memento.transaction! fn ->
    %ConfigValue{name: name, value: value}
    |> Memento.Query.write()
  end

  # Notify worker (async, non-blocking)
  timestamp = DateTime.utc_now()
  send(:config_update_worker, {:config_updated, name, old_value, value, timestamp})

  {:ok, value}
end
```

### Application Supervision

The worker is added to the supervision tree in [`Application.start/2`](lib/config_api/application.ex:14):

```elixir
children = [
  ConfigApi.ConfigUpdateWorker,  # Started before HTTP server
  {Plug.Cowboy, scheme: :http, plug: ConfigApiWeb.Router, options: [port: 4000]}
]
```

## Performance Characteristics

- **Memory Usage**: Minimal (stateless GenServer)
- **CPU Impact**: Low (simple message processing)
- **HTTP Latency**: Zero impact (asynchronous messaging)
- **Reliability**: Isolated failures don't affect config operations

## Testing

### Manual Testing
1. Start the application: `mix run --no-halt`
2. Watch logs for worker startup: `[info] ConfigUpdateWorker started`
3. Make config updates via REST API
4. Observe detailed log entries with timestamps and values

### Example Test Sequence
```bash
# Test 1: Create new config
curl -X PUT localhost:4000/config/test_key -H "Content-Type: application/json" -d '{"value":"initial"}'
# Expected log: old_value=nil, new_value=initial

# Test 2: Update existing config  
curl -X PUT localhost:4000/config/test_key -H "Content-Type: application/json" -d '{"value":"updated"}'
# Expected log: old_value=initial, new_value=updated
```

## Future Enhancements

Potential improvements for the worker:

1. **Metrics Collection**: Track update frequency and value sizes
2. **Audit Trail**: Store update history in persistent storage
3. **Filtering**: Skip logging for specific config keys
4. **Batching**: Group multiple updates in time windows
5. **External Notifications**: Send updates to external monitoring systems
6. **Value Sanitization**: Mask sensitive values in logs