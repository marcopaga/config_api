# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ConfigApi is a simple configuration management API using **Memento** (Mnesia wrapper) for in-memory storage within the Erlang VM. Configuration data is stored in-memory and does not persist between restarts.

## Architecture

Simple in-memory key-value store with async audit logging:

- **ConfigStore** (`lib/config_api/ConfigStore.ex`): Main API facade
  - `get/1`: Read a config value
  - `put/2`: Write a config value
  - `all/0`: List all config values
  - Uses Memento transactions for atomic operations
  - Sends async notifications to ConfigUpdateWorker

- **ConfigValue** (`lib/config_api/ConfigValue.ex`): Memento table definition
  - Attributes: `:name` (key), `:value` (value)
  - Backed by Mnesia (in-memory Erlang database)

- **DB** (`lib/config_api/DB.ex`): Database initialization
  - `setup/0`: Creates Memento table on application start
  - Called from `Application.start/2`

- **ConfigUpdateWorker** (`lib/config_api/config_update_worker.ex`): Async audit logging GenServer
  - Receives notifications about config changes via message passing
  - Logs all updates with timestamps and old/new values
  - Runs asynchronously (non-blocking to main operations)

- **Router** (`lib/config_api_web/router.ex`): HTTP API using Plug
  - `GET /config` - List all configurations (JSON)
  - `GET /config/:name` - Get a specific config value (text/plain or 404)
  - `PUT /config/:name` - Set a config value (requires JSON body with "value" field)

## Development Commands

```bash
# Install dependencies
mix deps.get

# Start interactive shell with application running
iex -S mix
# Server starts on http://localhost:4000

# Format code
mix format

# Run tests
mix test

# Run specific test file
mix test test/config_api_test.exs

# Run static analysis
mix compile --warnings-as-errors
```

## Storage Model

**In-Memory Only**: Data is stored in Erlang VM memory (Mnesia) and does NOT persist between application restarts. This is suitable for:
- Development/testing
- Temporary configuration
- Cache-like use cases

**NOT suitable for**:
- Production data that must survive restarts
- Long-term configuration storage

## Key Patterns

1. **Memento Transactions**: All database operations wrapped in `Memento.transaction!` for atomicity
2. **Async Logging**: ConfigStore sends messages to ConfigUpdateWorker (fire-and-forget pattern)
3. **GenServer Worker**: ConfigUpdateWorker handles messages asynchronously via `handle_info/2`
4. **Simple Router**: Plug-based HTTP routing without Phoenix framework

## API Examples

```bash
# List all values (empty initially)
curl -i http://localhost:4000/config

# Get non-existent value (returns 404)
curl -i http://localhost:4000/config/foo

# Set a value
curl -i -X PUT http://localhost:4000/config/foo \
     -H "Content-Type: application/json" \
     -d '{"value":"bar"}'

# Get the value (returns 200 with "bar")
curl -i http://localhost:4000/config/foo

# List all values (returns JSON array)
curl -i http://localhost:4000/config
```

## Testing

Tests use ExUnit. The application starts fresh for each test run with an empty Memento table:

```bash
mix test
```

## Tooling

- **Erlang/Elixir**: Managed via ASDF (see `.tool-versions`)
  - Run `asdf install` to install correct versions
  - Current versions: Erlang 28.0.2, Elixir 1.18.4

## Important Notes

- This is a **simple in-memory implementation** - there is NO PostgreSQL, NO EventStore, NO Event Sourcing
- Previous attempts to migrate to Event Sourcing/CQRS with EventStore were rolled back
- The codebase intentionally stays simple with Memento for in-memory storage
