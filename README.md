# ConfigApi

A production-grade configuration management API built with **CQRS (Command Query Responsibility Segregation)** and **Event Sourcing** using PostgreSQL and EventStore.

## Architecture

This application uses a complete CQRS/Event Sourcing architecture:

- **Command Side:** Aggregates validate business logic and emit domain events to EventStore
- **Query Side:** In-memory ETS projection rebuilt from events for fast reads
- **Event Store:** PostgreSQL-based persistent event log (source of truth)
- **Audit Trail:** Complete history of all configuration changes with timestamps
- **Time-Travel:** Query configuration state at any point in time

### Key Components

- **EventStore** - PostgreSQL-backed event persistence
- **ConfigAggregate** - Domain logic and event emission
- **ConfigStateProjection** - ETS-based read model (rebuilds on startup)
- **ConfigStoreCQRS** - Public API facade
- **Health Check** - Component monitoring endpoint

### Consistency Model

**Restart-Based Eventual Consistency:**
- Writes immediately persist events to EventStore
- Projection rebuilds from events on application startup
- Reads reflect all historical events after restart

## Prerequisites

- **Erlang 28.0.2** and **Elixir 1.18.4** (via ASDF)
- **PostgreSQL 12+** (for EventStore)
- **Docker** (optional, for PostgreSQL)

## Quick Start

### 1. Install Dependencies

```bash
# Install Erlang/Elixir via ASDF
asdf install

# Install Elixir dependencies
mix deps.get
```

### 2. Setup PostgreSQL

**Option A: Using Docker**
```bash
docker run -d \
  --name config_api_postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=config_api_eventstore \
  -p 5432:5432 \
  postgres:15
```

**Option B: Local PostgreSQL**
```bash
createdb config_api_eventstore
```

### 3. Initialize EventStore

```bash
# Create EventStore schema
mix event_store.create

# Initialize EventStore tables
mix event_store.init
```

### 4. Run the Application

```bash
# Development mode with interactive shell
iex -S mix

# Production mode
MIX_ENV=prod mix run --no-halt

# Run tests
mix test
```

Server starts on **http://localhost:4000**

## API Reference

### Standard CRUD Operations

#### List All Configurations
```bash
GET /config
```
Returns JSON array of all configurations from the projection.

**Example:**
```bash
curl http://localhost:4000/config
# [{"name":"database_url","value":"postgres://..."},{"name":"api_key","value":"secret"}]
```

#### Get Configuration Value
```bash
GET /config/:name
```
Returns the current value as plain text.

**Example:**
```bash
curl http://localhost:4000/config/database_url
# postgres://localhost/mydb
```

#### Set Configuration Value
```bash
PUT /config/:name
Content-Type: application/json
{"value": "..."}
```

**Example:**
```bash
curl -X PUT http://localhost:4000/config/database_url \
  -H "Content-Type: application/json" \
  -d '{"value":"postgres://localhost/mydb"}'
# OK
```

**Note:** After writing, restart the application to see the value in reads, or use the event history endpoint for immediate verification.

#### Delete Configuration
```bash
DELETE /config/:name
```

**Example:**
```bash
curl -X DELETE http://localhost:4000/config/api_key
# OK
```

### CQRS-Specific Endpoints

#### Get Event History
```bash
GET /config/:name/history
```
Returns complete event stream with timestamps and metadata.

**Example:**
```bash
curl http://localhost:4000/config/database_url/history
```
```json
[
  {
    "event_type": "Elixir.ConfigApi.Events.ConfigValueSet",
    "data": {
      "config_name": "database_url",
      "value": "postgres://localhost/mydb",
      "old_value": null,
      "timestamp": "2026-02-12T10:00:00Z"
    },
    "created_at": "2026-02-12T10:00:00.123456Z",
    "stream_version": 1
  }
]
```

#### Time-Travel Query
```bash
GET /config/:name/at/:timestamp
```
Returns configuration value as it existed at the specified timestamp (ISO8601 format).

**Example:**
```bash
# What was the value at 10:00 AM?
curl http://localhost:4000/config/database_url/at/2026-02-12T10:00:00Z
# postgres://old-server/mydb

# What is the value now?
curl http://localhost:4000/config/database_url/at/2026-02-12T11:00:00Z
# postgres://new-server/mydb
```

### Health Check

```bash
GET /health
```
Returns component status for monitoring.

**Example:**
```bash
curl http://localhost:4000/health
```
```json
{
  "status": "healthy",
  "timestamp": "2026-02-12T10:30:00Z",
  "checks": {
    "eventstore": "ok",
    "projection": "ok",
    "database": "ok"
  }
}
```
Returns HTTP 200 if healthy, 503 if any component is down.

## Development

### Run Tests
```bash
# All tests
mix test

# Specific test file
mix test test/config_api/config_store_cqrs_test.exs

# With coverage
mix test --cover
```

**Test Results:**
```
Finished in 17.6 seconds
1 doctest, 102 tests, 0 failures ✅
```

### Code Formatting
```bash
mix format
```

### Static Analysis
```bash
mix compile --warnings-as-errors
```

### Clear Event Data (Development)
```bash
# WARNING: Deletes all events
mix event_store.drop
mix event_store.create
mix event_store.init
```

## Event Sourcing Benefits

### Complete Audit Trail
Every configuration change is recorded with:
- Who/what changed it (via aggregate metadata)
- When it changed (timestamp)
- What the old value was
- What the new value is

### Time-Travel Queries
Answer questions like:
- "What was the database URL last Tuesday?"
- "When did the API key change?"
- "Show me all changes to this configuration"

### Event Replay
Rebuild the entire application state from events:
```elixir
# Projection automatically rebuilds on startup
# Replays all events from EventStore → ETS projection
```

### Debug and Compliance
- Full audit log for compliance requirements
- Debug production issues by replaying events
- Understand system behavior over time

## Architecture Details

### Write Path (Commands)
```
HTTP PUT → ConfigStoreCQRS → ConfigAggregate → Domain Event → EventStore (PostgreSQL)
                                                                    ↓
                                                        ConfigUpdateWorker (audit log)
```

### Read Path (Queries)
```
HTTP GET → ConfigStoreCQRS → ConfigStateProjection (ETS) → Response
```

### Event Flow
```
EventStore (PostgreSQL)
    ↓ (on startup)
Projection reads all events
    ↓
Rebuilds ETS table
    ↓
Ready for fast reads
```

## Configuration

See `config/config.exs` for EventStore settings:

```elixir
config :config_api, ConfigApi.EventStore,
  serializer: ConfigApi.EventSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  port: 5432,
  pool_size: 10
```

## Production Deployment

### Build Release
```bash
MIX_ENV=prod mix release
```

### Run Release
```bash
_build/prod/rel/config_api/bin/config_api start
```

### Environment Variables
Set PostgreSQL connection via environment:
```bash
export DATABASE_URL="postgres://user:pass@host/config_api_eventstore"
```

### Health Monitoring
Configure your load balancer to check:
```
GET /health
```
- 200 = healthy
- 503 = unhealthy (remove from rotation)

## Consistency Model

**Important:** This application uses a restart-based consistency model:

1. **Write Operation:** Event immediately persisted to EventStore (durable)
2. **Read Operation:** Returns data from ETS projection
3. **Projection Update:** Happens on application restart (reads all events)

**Implications:**
- Writes are immediately durable (events in PostgreSQL)
- Reads require server restart to reflect new writes
- Use `/config/:name/history` endpoint for immediate event verification
- Suitable for configuration management with infrequent updates

**Workarounds for immediate reads:**
- Restart application after critical updates
- Use event history endpoint (`/config/:name/history`)
- Schedule periodic projection refreshes

## Troubleshooting

### EventStore Connection Issues
```bash
# Check PostgreSQL is running
psql -U postgres -d config_api_eventstore -c "SELECT 1"

# Reinitialize EventStore
mix event_store.drop
mix event_store.create
mix event_store.init
```

### Projection Out of Sync
```bash
# Restart application - projection rebuilds automatically
# Verify with health check
curl http://localhost:4000/health
```

### Port Already in Use
```bash
# Find process using port 4000
lsof -i :4000

# Kill it
kill -9 <PID>
```

## Technology Stack

- **Language:** Elixir 1.18.4 / Erlang/OTP 28
- **Web Framework:** Plug + Cowboy
- **Event Store:** EventStore library (PostgreSQL-backed)
- **Database:** PostgreSQL 12+
- **Read Model:** ETS (in-memory Erlang tables)
- **Serialization:** JSON (Jason library)
- **Testing:** ExUnit

## Project Status

**Version:** 0.1.0
**Status:** Production-ready with restart-based consistency
**Test Coverage:** 102/102 tests passing
**Architecture:** Complete CQRS/Event Sourcing implementation

## Contributing

See `CLAUDE.md` for development guidelines and architecture details.

## License

MIT License
