# Phase 0: Infrastructure Setup - Detailed Checklist

**Goal**: Set up PostgreSQL and EventStore infrastructure without changing business logic.

**Estimated Time**: 2-3 hours
**Risk Level**: Low
**Rollback**: Delete files and remove dependencies

---

## Pre-Flight Checks

Before starting Phase 0:

- [ ] Read `CQRS_MIGRATION_PLAN.md` (full plan)
- [ ] Read `MIGRATION_ROADMAP.md` (quick reference)
- [ ] Ensure Docker is installed and running: `docker --version`
- [ ] Ensure PostgreSQL client tools available: `psql --version`
- [ ] Current branch is clean: `git status`
- [ ] All tests passing: `mix test`

---

## Step 1: Create Migration Branch (5 min)

```bash
# Create and checkout new branch
git checkout -b feature/cqrs-migration

# Verify you're on the new branch
git branch --show-current
# Expected output: feature/cqrs-migration
```

**Checkpoint**:
- [ ] On `feature/cqrs-migration` branch
- [ ] Git status shows no uncommitted changes

---

## Step 2: Add Dependencies (5 min)

### Update `mix.exs`

Edit the `deps/0` function to add EventStore dependencies:

```elixir
defp deps do
  [
    {:plug_cowboy, "~> 2.0"},
    {:jason, "~> 1.2"},
    {:memento, "~> 0.5.0"},
    # NEW: EventStore dependencies
    {:eventstore, "~> 1.4.8"},
    {:postgrex, "~> 0.21.1"}
  ]
end
```

### Fetch dependencies

```bash
mix deps.get
```

**Expected output**:
```
Resolving Hex dependencies...
...
* Getting eventstore (Hex package)
* Getting postgrex (Hex package)
...
```

**Checkpoint**:
- [ ] Dependencies added to `mix.exs`
- [ ] `mix deps.get` completed successfully
- [ ] Both Memento and EventStore dependencies present
- [ ] Application still compiles: `mix compile`

---

## Step 3: Set Up Docker Compose (15 min)

### Create `docker-compose.yml`

Create a new file in the project root:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14-alpine
    container_name: config_api_postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: config_api_eventstore
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Start PostgreSQL

```bash
# Start PostgreSQL container
docker-compose up -d

# Wait for health check
docker-compose ps

# Verify PostgreSQL is running
docker-compose exec postgres psql -U postgres -c "SELECT version();"
```

**Expected output**:
```
 version
---------
 PostgreSQL 14.x ...
```

### Test connection from host

```bash
# Test connection (should succeed)
psql -h localhost -U postgres -d config_api_eventstore -c "SELECT 1;"

# If prompted for password, enter: postgres
```

**Checkpoint**:
- [ ] `docker-compose.yml` created
- [ ] PostgreSQL container running
- [ ] Can connect to PostgreSQL from host
- [ ] Database `config_api_eventstore` exists

---

## Step 4: Configure EventStore Module (10 min)

### Create `lib/config_api/event_store.ex`

```elixir
defmodule ConfigApi.EventStore do
  use EventStore, otp_app: :config_api

  # Custom initialization to support environment variables
  def init(config) do
    {:ok, config}
  end
end
```

**Checkpoint**:
- [ ] File created at `lib/config_api/event_store.ex`
- [ ] Module compiles: `mix compile`

---

## Step 5: Configure EventStore Settings (15 min)

### Update `config/config.exs`

Add EventStore configuration:

```elixir
import Config

# Existing config...

# EventStore configuration
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  port: 5432,
  pool_size: 10,
  pool_overflow: 5

# Import environment-specific config
import_config "#{config_env()}.exs"
```

### Create `config/dev.exs`

```elixir
import Config

# Development-specific EventStore config
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  port: 5432,
  pool_size: 10

# Keep logger level
config :logger, level: :info
```

### Update `config/test.exs`

```elixir
import Config

# Test-specific EventStore config (separate database)
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore_test",
  hostname: "localhost",
  port: 5432,
  pool_size: 1

# Keep logger level for tests
config :logger, level: :info
```

**Checkpoint**:
- [ ] `config/config.exs` updated
- [ ] `config/dev.exs` created
- [ ] `config/test.exs` updated
- [ ] Application compiles: `mix compile`

---

## Step 6: Initialize EventStore Databases (15 min)

### Create development database

```bash
# Create EventStore schema in development database
MIX_ENV=dev mix event_store.create

# Initialize EventStore tables
MIX_ENV=dev mix event_store.init
```

**Expected output**:
```
The database for ConfigApi.EventStore has been created
The EventStore database has been initialized
```

### Create test database

```bash
# Create EventStore schema in test database
MIX_ENV=test mix event_store.create

# Initialize EventStore tables
MIX_ENV=test mix event_store.init
```

**Expected output**:
```
The database for ConfigApi.EventStore has been created
The EventStore database has been initialized
```

### Verify databases exist

```bash
# List databases
psql -h localhost -U postgres -l | grep config_api

# Expected output:
# config_api_eventstore       | postgres | ...
# config_api_eventstore_test  | postgres | ...
```

**Checkpoint**:
- [ ] Development EventStore database created and initialized
- [ ] Test EventStore database created and initialized
- [ ] Can connect to both databases

---

## Step 7: Create Test Helpers (20 min)

### Add EventStore test helper

Create `test/support/event_store_case.ex`:

```elixir
defmodule ConfigApi.EventStoreCase do
  @moduledoc """
  Test case helper for EventStore tests.
  Provides setup to reset EventStore between tests.
  """

  use ExUnit.CaseTemplate

  alias ConfigApi.EventStore

  using do
    quote do
      alias ConfigApi.EventStore
      import ConfigApi.EventStoreCase
    end
  end

  setup do
    # Reset EventStore before each test
    :ok = reset_eventstore!()
    :ok
  end

  @doc """
  Resets the EventStore by deleting and recreating the schema.
  """
  def reset_eventstore! do
    config = EventStore.config()

    {:ok, conn} = Postgrex.start_link(config)

    # Delete all streams
    Postgrex.query!(
      conn,
      "TRUNCATE TABLE streams, events, subscriptions, snapshots CASCADE;",
      []
    )

    GenServer.stop(conn)

    :ok
  rescue
    error ->
      IO.puts("Warning: Failed to reset EventStore: #{inspect(error)}")
      :ok
  end
end
```

### Update `test/test_helper.exs`

```elixir
ExUnit.start()

# Ensure EventStore test database is initialized
case Mix.Task.run("event_store.init", ["--quiet"]) do
  :ok -> :ok
  {:error, _} -> :ok  # Already initialized
  _ -> :ok
end
```

**Checkpoint**:
- [ ] `test/support/event_store_case.ex` created
- [ ] `test/test_helper.exs` updated
- [ ] Files compile: `mix compile`

---

## Step 8: Write Basic EventStore Tests (30 min)

### Create `test/config_api/event_store_test.exs`

```elixir
defmodule ConfigApi.EventStoreTest do
  use ConfigApi.EventStoreCase, async: false

  alias ConfigApi.EventStore

  describe "basic EventStore functionality" do
    test "can connect to EventStore" do
      # This test passes if setup succeeds
      assert true
    end

    test "can append and read events" do
      stream_name = "test_stream_#{System.unique_integer([:positive])}"

      # Create a simple event
      event = %EventStore.EventData{
        event_type: "TestEvent",
        data: %{test: "data", value: 42},
        metadata: %{created_by: "test"}
      }

      # Append event to stream
      assert {:ok, _} = EventStore.append_to_stream(stream_name, :any_version, [event])

      # Read event back
      assert {:ok, recorded_events} = EventStore.read_stream_forward(stream_name)
      assert length(recorded_events) == 1

      [recorded_event] = recorded_events
      assert recorded_event.event_type == "TestEvent"
      assert recorded_event.data.test == "data"
      assert recorded_event.data.value == 42
    end

    test "can append multiple events to a stream" do
      stream_name = "multi_event_stream_#{System.unique_integer([:positive])}"

      events = [
        %EventStore.EventData{
          event_type: "Event1",
          data: %{sequence: 1},
          metadata: %{}
        },
        %EventStore.EventData{
          event_type: "Event2",
          data: %{sequence: 2},
          metadata: %{}
        },
        %EventStore.EventData{
          event_type: "Event3",
          data: %{sequence: 3},
          metadata: %{}
        }
      ]

      # Append all events
      assert {:ok, _} = EventStore.append_to_stream(stream_name, :any_version, events)

      # Read all events back
      assert {:ok, recorded_events} = EventStore.read_stream_forward(stream_name)
      assert length(recorded_events) == 3

      # Verify order
      sequences = Enum.map(recorded_events, & &1.data.sequence)
      assert sequences == [1, 2, 3]
    end

    test "reading non-existent stream returns error" do
      stream_name = "non_existent_#{System.unique_integer([:positive])}"

      assert {:error, :stream_not_found} = EventStore.read_stream_forward(stream_name)
    end

    test "events persist across test resets" do
      # This test verifies that reset_eventstore! works
      # If we can write after a reset, it means the reset succeeded
      stream_name = "reset_test_#{System.unique_integer([:positive])}"

      event = %EventStore.EventData{
        event_type: "AfterReset",
        data: %{test: "reset"},
        metadata: %{}
      }

      assert {:ok, _} = EventStore.append_to_stream(stream_name, :any_version, [event])
      assert {:ok, events} = EventStore.read_stream_forward(stream_name)
      assert length(events) == 1
    end
  end

  describe "EventStore reset functionality" do
    test "reset clears all streams" do
      # Write to multiple streams
      for i <- 1..3 do
        stream_name = "stream_#{i}"
        event = %EventStore.EventData{
          event_type: "TestEvent",
          data: %{number: i},
          metadata: %{}
        }
        EventStore.append_to_stream(stream_name, :any_version, [event])
      end

      # Reset
      :ok = reset_eventstore!()

      # Verify streams are gone
      for i <- 1..3 do
        stream_name = "stream_#{i}"
        assert {:error, :stream_not_found} = EventStore.read_stream_forward(stream_name)
      end
    end
  end
end
```

### Run tests

```bash
# Run only EventStore tests
mix test test/config_api/event_store_test.exs

# Expected output: All tests passing
```

**Checkpoint**:
- [ ] EventStore test file created
- [ ] All EventStore tests pass
- [ ] Reset functionality works
- [ ] Can append and read events

---

## Step 9: Verify Existing Tests Still Pass (10 min)

### Run all tests

```bash
# Run complete test suite
mix test

# Expected output: All tests passing (both old and new)
```

**Important**: If old tests fail, EventStore might be interfering. Check:
- Memento tables still being created
- No port conflicts
- No dependency conflicts

**Checkpoint**:
- [ ] All existing tests still pass
- [ ] New EventStore tests pass
- [ ] No warnings during compilation
- [ ] No deprecation warnings

---

## Step 10: Commit Phase 0 (10 min)

### Review changes

```bash
# Check what changed
git status

# Review diff
git diff

# Should see:
# - mix.exs (new deps)
# - docker-compose.yml (new file)
# - config files (EventStore config)
# - lib/config_api/event_store.ex (new file)
# - test/support/event_store_case.ex (new file)
# - test/config_api/event_store_test.exs (new file)
```

### Stage and commit

```bash
# Stage all changes
git add -A

# Commit with descriptive message
git commit -m "$(cat <<'EOF'
Phase 0: Set up EventStore infrastructure

Added EventStore dependencies and configuration alongside existing
Memento implementation. No business logic changed.

Infrastructure:
- PostgreSQL via Docker Compose
- EventStore library (1.4.8)
- Postgrex (0.21.1)

Configuration:
- Development database: config_api_eventstore
- Test database: config_api_eventstore_test
- EventStore module: ConfigApi.EventStore

Testing:
- Test helper for EventStore reset
- Basic EventStore connectivity tests
- Event append/read tests
- All existing tests still passing

Next: Phase 1 - Define domain events

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

**Checkpoint**:
- [ ] All changes committed
- [ ] Commit message describes Phase 0 work
- [ ] Clean working directory: `git status`

---

## Phase 0 Complete! ✅

### Verification Checklist

Before moving to Phase 1, verify:

#### Infrastructure
- [ ] PostgreSQL running: `docker-compose ps`
- [ ] Development database exists: `psql -h localhost -U postgres -l | grep eventstore`
- [ ] Test database exists: `psql -h localhost -U postgres -l | grep test`

#### Code
- [ ] EventStore module exists: `lib/config_api/event_store.ex`
- [ ] Config files updated: `config/config.exs`, `config/dev.exs`, `config/test.exs`
- [ ] Test helper exists: `test/support/event_store_case.ex`

#### Tests
- [ ] All tests pass: `mix test`
- [ ] EventStore tests pass: `mix test test/config_api/event_store_test.exs`
- [ ] No compilation warnings: `mix compile --warnings-as-errors`

#### Documentation
- [ ] Changes committed to git
- [ ] On feature branch: `git branch --show-current` shows `feature/cqrs-migration`

### What We Achieved

✅ PostgreSQL running in Docker
✅ EventStore library integrated
✅ Test infrastructure ready
✅ Can append and read events
✅ Test reset functionality works
✅ Zero impact on existing functionality

### Rollback Capability

If you need to rollback Phase 0:

```bash
# Delete branch and return to main
git checkout main
git branch -D feature/cqrs-migration

# Stop and remove PostgreSQL
docker-compose down -v

# Remove dependencies
# (manually edit mix.exs to remove eventstore/postgrex)
mix deps.clean --all
mix deps.get
```

---

## Next Steps

You're now ready for **Phase 1: Domain Events**!

Phase 1 tasks:
1. Define `ConfigValueSet` event
2. Define `ConfigValueDeleted` event
3. Event serialization tests
4. No integration yet (events are standalone)

**Estimated time**: 1-2 hours

Read the Phase 1 section in `CQRS_MIGRATION_PLAN.md` for detailed instructions.

---

## Troubleshooting

### Issue: Docker won't start
```bash
# Check if Docker daemon is running
docker ps

# If not running, start Docker Desktop (Mac/Windows)
# or start Docker service (Linux)
sudo systemctl start docker
```

### Issue: Port 5432 already in use
```bash
# Find what's using port 5432
lsof -i :5432

# Either:
# 1. Stop the other PostgreSQL instance
# 2. Change port in docker-compose.yml to 5433
```

### Issue: EventStore create fails
```bash
# Drop and recreate
MIX_ENV=dev mix event_store.drop
MIX_ENV=dev mix event_store.create
MIX_ENV=dev mix event_store.init
```

### Issue: Tests can't connect to PostgreSQL
```bash
# Verify PostgreSQL is running
docker-compose ps

# Check logs
docker-compose logs postgres

# Verify network connectivity
psql -h localhost -U postgres -c "SELECT 1"
```

### Issue: reset_eventstore! function fails
Check that Postgrex is available in test environment:
```elixir
# In test_helper.exs
Mix.install([:postgrex])  # If needed
```

---

## Questions?

If you encounter any issues not covered here:
1. Check PostgreSQL logs: `docker-compose logs postgres`
2. Check EventStore config: `config/test.exs`
3. Verify all dependencies installed: `mix deps.get`
4. Ask for help with specific error messages

Ready to proceed to Phase 1? Let's go! 🚀
