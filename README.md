# ConfigApi

This project exposes a simple config API with **Event Sourcing** architecture. All configuration changes are persisted as immutable events in PostgreSQL, providing complete audit trails and historical data access.

## Architecture

- **Event Sourcing**: All state changes are stored as events
- **CQRS**: Separate read/write models with projections
- **PostgreSQL**: Persistent event store backend
- **Complete Audit Trail**: Every configuration change is permanently recorded
- **Time Travel**: Query configuration state at any point in time

## Prerequisites

- Docker and Docker Compose
- Erlang and Elixir (via ASDF or your preferred method)

## Setup

### 1. Start PostgreSQL Database

```shell
# Start PostgreSQL with docker-compose
docker-compose up -d

# Verify database is running
docker-compose ps
```

### 2. Install Dependencies

```shell
mix deps.get
```

### 3. Initialize EventStore

```shell
# Create and migrate the EventStore database
mix event_store.create
mix event_store.init
```

### 4. Run the Application

```shell
iex -S mix
```

The server will start on `http://localhost:4000`

## API Usage

The API maintains the same interface as before, but now with full event sourcing capabilities:

### Basic Operations

```shell
# 1. List all values (should be empty initially)
curl -i http://localhost:4000/config

# 2. Query a non-existent value (404)
curl -i http://localhost:4000/config/foo

# 3. Set a value (PUT)
curl -i -X PUT http://localhost:4000/config/foo \
     -H "Content-Type: application/json" \
     -d '{"value":"bar"}'

# 4. Get the value that was just set (200, "bar")
curl -i http://localhost:4000/config/foo

# 5. Set another value
curl -i -X PUT http://localhost:4000/config/database_url \
     -H "Content-Type: application/json" \
     -d '{"value":"postgres://localhost/mydb"}'

# 6. List all values (should contain both, JSON)
curl -i http://localhost:4000/config
```

### Event Sourcing Features

```shell
# Get complete history of a configuration value
curl -i http://localhost:4000/config/foo/history

# Get configuration state at a specific timestamp
curl -i "http://localhost:4000/config/foo/at?timestamp=2024-01-01T12:00:00Z"

# Delete a configuration value
curl -i -X DELETE http://localhost:4000/config/foo
```

## Event Sourcing Benefits

1. **Complete Audit Trail**: Every change is permanently recorded
2. **Time Travel**: Query any configuration at any point in history
3. **Debugging**: Full visibility into what changed, when, and why
4. **Data Recovery**: Rebuild state from events if needed
5. **Analytics**: Analyze configuration change patterns over time

## Logging

The system provides detailed logging for all configuration changes:

```
[info] Config updated at 2025-09-08T08:20:12.405220Z: name=database_url, old_value=nil, new_value=postgres://localhost/mydb
[info] Config updated at 2025-09-08T08:20:38.495306Z: name=database_url, old_value=postgres://localhost/mydb, new_value=postgres://production/mydb
[info] Config deleted at 2025-09-08T08:21:03.035595Z: name=api_timeout, deleted_value=5000
```

## Development

### Database Management

```shell
# Stop and remove database
docker-compose down

# Reset database (WARNING: destroys all data)
docker-compose down -v
docker-compose up -d
mix event_store.drop
mix event_store.create
mix event_store.init
```

### Running Tests

```shell
# Start test database
docker-compose up -d

# Run tests
mix test
```

## Installation of Erlang and Elixir via ASDF

Erlang and Elixir are installed with ASDF as specified in `.tool-versions`.

```shell
asdf install
```

## Project Structure

```
lib/
├── config_api/
│   ├── aggregates/          # Domain aggregates
│   │   └── config_value.ex  # ConfigValue aggregate
│   ├── events/              # Domain events
│   │   ├── config_value_set.ex
│   │   └── config_value_deleted.ex
│   ├── projections/         # Read model projections
│   │   └── config_state_projection.ex
│   ├── event_store.ex       # EventStore configuration
│   ├── ConfigStore.ex       # Main API interface
│   └── config_update_worker.ex  # Logging worker
└── config_api_web/
    └── router.ex            # HTTP routes
