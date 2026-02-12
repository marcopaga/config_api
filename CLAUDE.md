# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ConfigApi is a configuration management API using **CQRS (Command Query Responsibility Segregation)** with **Event Sourcing**. Configuration data is persisted in PostgreSQL via EventStore, with in-memory projections for fast reads.

## Architecture

CQRS/Event Sourcing implementation with complete separation of read and write paths:

### Write Path (Commands)
- **ConfigStoreCQRS** (`lib/config_api/config_store_cqrs.ex`): Main CQRS API
  - `put/2`: Set configuration value → generates `ConfigValueSet` event
  - `delete/1`: Delete configuration → generates `ConfigValueDeleted` event
  - Commands validated by aggregates before events are persisted

- **Aggregates** (`lib/config_api/aggregates/`)
  - `ConfigValue`: Business logic and validation
  - Enforces business rules (e.g., allows resurrection)
  - Generates events in response to commands
  - State rebuilt by replaying events

- **Events** (`lib/config_api/events/`)
  - `ConfigValueSet`: Represents a configuration change
  - `ConfigValueDeleted`: Represents a configuration deletion
  - Immutable, append-only event log

- **EventStore** (`lib/config_api/event_store.ex`)
  - PostgreSQL-backed event persistence
  - Uses `eventstore` library (v1.4.8)
  - Stores events with full audit trail

### Read Path (Queries)
- **ConfigStateProjection** (`lib/config_api/projections/config_state_projection.ex`)
  - GenServer maintaining ETS table with current state
  - Rebuilds from EventStore on startup
  - Fast in-memory reads (CQRS query side)

- **ConfigStoreCQRS** query methods:
  - `get/1`: Read from projection (fast)
  - `all/0`: List all configurations
  - `get_history/1`: Full event history for audit
  - `get_at_timestamp/2`: Time-travel queries

### HTTP API
- **Router** (`lib/config_api_web/router.ex`): RESTful API using Plug
  - `GET /config` - List all configurations
  - `GET /config/:name` - Get specific value
  - `PUT /config/:name` - Set value (CQRS command)
  - `DELETE /config/:name` - Delete configuration
  - `GET /config/:name/history` - Event history (audit trail)
  - `GET /config/:name/at/:timestamp` - Time-travel queries

### Supporting Components
- **ConfigUpdateWorker** (`lib/config_api/config_update_worker.ex`)
  - Async audit logging GenServer
  - Receives notifications about config changes
  - Logs with timestamps for monitoring

## Development Commands

```bash
# Install dependencies
mix deps.get

# Start PostgreSQL (required for EventStore)
docker-compose up -d

# Initialize EventStore schema
mix event_store.init

# Start interactive shell with application running
iex -S mix
# Server starts on http://localhost:4000

# Format code
mix format

# Run all tests
mix test

# Run specific test suite
mix test test/config_api/config_store_cqrs_test.exs

# Run static analysis
mix compile --warnings-as-errors

# Stop PostgreSQL
docker-compose down
```

## Storage Model

**Persistent Event Store**: Events are stored in PostgreSQL and survive application restarts. The projection rebuilds from events on startup.

- **Event Storage**: PostgreSQL via EventStore library
- **Read Model**: In-memory ETS table (rebuilt from events)
- **Audit Trail**: Complete event history preserved
- **Time Travel**: Query state at any historical point

**Suitable for**:
- Production deployments
- Systems requiring audit trails
- Time-travel queries
- Historical analysis

## Key Patterns

1. **CQRS**: Separate write path (commands → events) from read path (projections)
2. **Event Sourcing**: State derived from replaying immutable events
3. **Aggregates**: Domain-driven design pattern for business logic
4. **Projections**: Fast read models rebuilt from events
5. **GenServer**: OTP pattern for projection process
6. **EventStore**: PostgreSQL-backed event persistence

## API Specifications

ConfigApi provides comprehensive machine-readable API specifications in the `spec/` directory:

- **OpenAPI 3.1**: `spec/openapi/configapi-v1.yaml` - Complete REST API specification
- **JSON Schema**: `spec/json-schema/` - Domain event and aggregate schemas (draft-07)
- **AsyncAPI 3.0**: `spec/asyncapi/config-events-v1.yaml` - Event streaming specification
- **Documentation**: `spec/README.md` - Usage guide and examples

### Specification Testing

Run contract tests to validate API against specifications:
```bash
mix test test/spec/                     # All specification tests (61 tests)
mix test test/spec/openapi_contract_test.exs   # OpenAPI contract tests
mix test test/spec/event_schema_test.exs       # Event schema validation
mix test test/spec/spec_validation_test.exs    # Spec file validation
```

### API Versioning

All endpoints use `/v1` prefix for proper versioning:
- **Versioned**: `/v1/config`, `/v1/health` (recommended)
- **Legacy**: `/config`, `/health` (deprecated, backward compatibility only)

## API Examples

```bash
# List all configurations (versioned)
curl http://localhost:4000/v1/config

# Get a specific value
curl http://localhost:4000/v1/config/api_key

# Set a value (CQRS command)
curl -X PUT http://localhost:4000/v1/config/api_key \
     -H "Content-Type: application/json" \
     -d '{"value":"secret123"}'

# Delete a configuration
curl -X DELETE http://localhost:4000/v1/config/api_key

# Get event history (audit trail)
curl http://localhost:4000/v1/config/api_key/history

# Time-travel query (ISO8601 timestamp)
curl http://localhost:4000/v1/config/api_key/at/2024-01-15T10:30:00Z

# Health check
curl http://localhost:4000/v1/health
```

## Testing

Tests use ExUnit with EventStore reset between tests:

```bash
# Run all tests (102 tests)
mix test

# Run specific test suite
mix test test/config_api_web/router_test.exs

# Run with coverage
mix test --cover
```

Test organization:
- `test/config_api/events/` - Event struct tests
- `test/config_api/aggregates/` - Business logic tests
- `test/config_api/projections/` - Projection tests
- `test/config_api/config_store_cqrs_test.exs` - Integration tests
- `test/config_api_web/router_test.exs` - HTTP API tests

## Tooling

- **Erlang/Elixir**: Managed via ASDF (see `.tool-versions`)
  - Run `asdf install` to install correct versions
  - Current versions: Erlang 28.0.2, Elixir 1.18.4

- **Docker**: PostgreSQL 14 for EventStore
  - Configured in `docker-compose.yml`
  - Database: `config_api_eventstore`

- **Dependencies**:
  - `eventstore` (1.4.8) - Event persistence
  - `postgrex` - PostgreSQL driver
  - `jason` - JSON encoding/decoding
  - `plug_cowboy` - HTTP server

## Important Notes

- **CQRS Migration Complete**: The codebase now uses CQRS/Event Sourcing
- **Old Code**: Legacy Memento-based `ConfigStore` still exists but is unused
- **Event Subscriptions**: Currently disabled in projection (rebuild from events works)
- **Production**: EventStore and Projection started manually in tests (not yet in supervision tree for production)
- **Audit Trail**: Every configuration change is permanently recorded as an event
- **Time Travel**: Can query configuration state at any point in history

## Architecture Diagram

```
┌──────────────┐
│  HTTP API    │ ← Router (Plug)
│   (REST)     │
└──────┬───────┘
       │
       ├────────────────┐
       │                │
       ▼                ▼
┌─────────────┐  ┌──────────────┐
│  Commands   │  │   Queries    │
│   (Write)   │  │    (Read)    │
└──────┬──────┘  └──────┬───────┘
       │                │
       ▼                ▼
┌─────────────┐  ┌──────────────┐
│ Aggregates  │  │  Projection  │
│  (Business  │  │     (ETS)    │
│   Logic)    │  │              │
└──────┬──────┘  └──────▲───────┘
       │                │
       ▼                │
┌─────────────┐         │
│   Events    │─────────┘
│ (Immutable) │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ EventStore  │
│ (Postgres)  │
└─────────────┘
```

## Migration Status

✅ Phase 0: EventStore Infrastructure
✅ Phase 1: Domain Events
✅ Phase 2: Aggregates
✅ Phase 3: Projections
✅ Phase 4: CQRS ConfigStore
✅ Phase 5: Router Integration
🔄 Phase 6: Production Readiness (in progress)

The CQRS implementation is complete and fully tested. Legacy code will be removed in Phase 6.
