# Data Flow Diagrams

Detailed request/response flows for all operations in ConfigApi.

## 📊 Overview

```mermaid
graph TB
    Client[HTTP Client]

    subgraph "ConfigApi System"
        Router[Router<br/>HTTP Layer]
        CQRS[ConfigStoreCQRS<br/>Facade]

        subgraph "Write Path"
            Agg[Aggregate]
            ES[(EventStore)]
        end

        subgraph "Read Path"
            Proj[(Projection)]
        end

        Worker[Worker<br/>Audit Logger]
    end

    Client -->|Request| Router
    Router -->|Route| CQRS

    CQRS -.->|Commands| Agg
    Agg -.->|Events| ES
    ES -.->|Notify| Worker

    CQRS -.->|Queries| Proj
    ES -->|Rebuild| Proj

    Router -->|Response| Client

    style ES fill:#e1f5ff
    style Proj fill:#fff4e1
    style Agg fill:#c8e6c9
```

---

## 🔨 Write Operations

### PUT /config/:name - Set Configuration

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant Agg as ConfigAggregate
    participant ES as EventStore<br/>(PostgreSQL)
    participant Worker as ConfigUpdateWorker
    participant Proj as Projection

    Client->>+Router: PUT /config/database_url<br/>{"value":"postgres://..."}

    Router->>+CQRS: put("database_url", "postgres://...")

    Note over CQRS: Create ephemeral aggregate
    CQRS->>+Agg: new("database_url")
    Agg-->>-CQRS: %ConfigAggregate{}

    Note over CQRS: Execute SetValue command
    CQRS->>+Agg: execute(SetValue)

    Note over Agg: Validate command<br/>Check business rules
    Agg->>Agg: validate(command)

    Note over Agg: Create event
    Agg->>Agg: ConfigValueSet{<br/>  name: "database_url",<br/>  value: "postgres://...",<br/>  old_value: nil,<br/>  timestamp: now<br/>}

    Agg-->>-CQRS: {:ok, [event]}

    Note over CQRS: Persist event
    CQRS->>+ES: append_to_stream("config-database_url", [event])

    ES->>ES: BEGIN TRANSACTION
    ES->>ES: INSERT INTO streams
    ES->>ES: INSERT INTO events
    ES->>ES: COMMIT

    ES-->>-CQRS: {:ok, event}

    Note over ES: Async notification
    ES-->>Worker: config_updated

    Worker->>Worker: Log: "Config updated:<br/>database_url = postgres://..."

    CQRS-->>-Router: {:ok, "postgres://..."}

    Router-->>-Client: 200 OK

    Note over Proj: NOT updated yet<br/>Waits for restart
```

**Key Points:**
1. Aggregate validates business rules
2. Event created with timestamp and old value
3. Event persisted in PostgreSQL transaction
4. Worker receives async notification
5. **Projection NOT updated** (restart-based consistency)
6. Response to client before projection update

**Timing:**
- Steps 1-14: ~20-30ms
- PostgreSQL transaction: ~15ms
- Worker notification: async (doesn't block response)

---

### DELETE /config/:name - Delete Configuration

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant Agg as ConfigAggregate
    participant ES as EventStore
    participant Proj as Projection

    Client->>+Router: DELETE /config/old_key

    Router->>+CQRS: delete("old_key")

    Note over CQRS: Get current aggregate state
    CQRS->>+ES: read_stream_forward("config-old_key")

    ES-->>-CQRS: [ConfigValueSet event]

    Note over CQRS: Reconstruct aggregate
    CQRS->>+Agg: rebuild_from_events([events])
    Agg-->>-CQRS: %ConfigAggregate{<br/>  name: "old_key",<br/>  value: "old_value",<br/>  deleted: false<br/>}

    Note over CQRS: Execute DeleteValue command
    CQRS->>+Agg: execute(DeleteValue)

    alt Already deleted
        Agg-->>CQRS: {:error, :config_already_deleted}
        CQRS-->>Router: {:error, :config_already_deleted}
        Router-->>Client: 410 Gone
    else Not deleted yet
        Agg->>Agg: ConfigValueDeleted{<br/>  name: "old_key",<br/>  old_value: "old_value",<br/>  timestamp: now<br/>}

        Agg-->>-CQRS: {:ok, [event]}

        CQRS->>+ES: append_to_stream("config-old_key", [event])
        ES-->>-CQRS: {:ok, event}

        CQRS-->>-Router: :ok
        Router-->>-Client: 200 OK
    end

    Note over Proj: NOT updated<br/>Until restart
```

**Key Points:**
1. Must read current state to validate
2. Can't delete already-deleted config (returns 410)
3. Deletion event preserved in history
4. Soft delete (event-based), not hard delete

**Edge Cases:**
- Config never existed → 404 Not Found
- Config already deleted → 410 Gone
- Valid deletion → 200 OK

---

## 🔍 Read Operations

### GET /config/:name - Get Configuration

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant Proj as Projection<br/>(ETS)

    Client->>+Router: GET /config/database_url

    Router->>+CQRS: get("database_url")

    Note over CQRS: Query read model
    CQRS->>+Proj: get_config("database_url")

    Proj->>Proj: :ets.lookup(:config_state_projection,<br/>              "database_url")

    alt Config exists
        Proj-->>-CQRS: {:ok, "postgres://..."}
        CQRS-->>-Router: {:ok, "postgres://..."}
        Router-->>-Client: 200 "postgres://..."
    else Config not found
        Proj-->>CQRS: {:error, :not_found}
        CQRS-->>Router: {:error, :not_found}
        Router-->>Client: 404 Not Found
    end

    Note over Proj: Sub-millisecond<br/>response time
```

**Key Points:**
1. Direct ETS lookup (no database query)
2. Sub-millisecond response time
3. Returns 404 if not in projection
4. **Reflects state at last restart**

**Timing:**
- Steps 1-6: <1ms
- ETS lookup: microseconds

---

### GET /config - List All Configurations

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant Proj as Projection

    Client->>+Router: GET /config

    Router->>+CQRS: all()

    CQRS->>+Proj: get_all_configs()

    Proj->>Proj: :ets.tab2list(:config_state_projection)

    Proj->>Proj: Enum.map to %{name, value}

    Proj-->>-CQRS: [<br/>  %{name: "database_url", value: "..."},<br/>  %{name: "api_key", value: "..."},<br/>  ...<br/>]

    CQRS-->>-Router: config_list

    Router->>Router: Jason.encode!(config_list)

    Router-->>-Client: 200 [{"name":"...","value":"..."},...]

    Note over Proj: Fast even with<br/>hundreds of configs
```

**Performance:**
- 10 configs: ~1ms
- 100 configs: ~3ms
- 1000 configs: ~10ms

---

## 📜 Event History Operations

### GET /config/:name/history - Get Event History

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant ES as EventStore

    Client->>+Router: GET /config/database_url/history

    Router->>+CQRS: get_history("database_url")

    Note over CQRS: Read directly from EventStore
    CQRS->>+ES: read_stream_forward("config-database_url")

    ES->>ES: SELECT * FROM events<br/>WHERE stream_uuid = 'config-database_url'<br/>ORDER BY stream_version

    ES-->>-CQRS: [<br/>  %RecordedEvent{<br/>    event_type: "ConfigValueSet",<br/>    data: %ConfigValueSet{},<br/>    stream_version: 1,<br/>    created_at: ~U[2026-02-12 10:00:00Z]<br/>  },<br/>  %RecordedEvent{...},<br/>  ...<br/>]

    CQRS->>CQRS: Format events for HTTP response

    CQRS-->>-Router: {:ok, events}

    Router->>Router: Jason.encode!(events)

    Router-->>-Client: 200 [event1, event2, ...]

    Note over ES: Complete audit trail<br/>with all changes
```

**Use Cases:**
- Audit trail
- Debugging state changes
- Understanding configuration evolution
- Compliance reporting

**Data Returned:**
```json
{
  "event_type": "Elixir.ConfigApi.Events.ConfigValueSet",
  "data": {
    "config_name": "database_url",
    "value": "new_value",
    "old_value": "old_value",
    "timestamp": "2026-02-12T10:00:00Z"
  },
  "metadata": {
    "aggregate_id": "database_url",
    "aggregate_type": "ConfigValue"
  },
  "created_at": "2026-02-12T10:00:00.123456Z",
  "stream_version": 1
}
```

---

### GET /config/:name/at/:timestamp - Time-Travel Query

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant CQRS as ConfigStoreCQRS
    participant ES as EventStore

    Client->>+Router: GET /config/database_url/at/2026-02-12T10:30:00Z

    Router->>Router: parse_timestamp("2026-02-12T10:30:00Z")

    alt Invalid timestamp
        Router-->>Client: 400 Invalid timestamp format
    else Valid timestamp
        Router->>+CQRS: get_at_timestamp("database_url",<br/>                      ~U[2026-02-12 10:30:00Z])

        Note over CQRS: Read all events for config
        CQRS->>+ES: read_stream_forward("config-database_url")

        ES-->>-CQRS: [event1, event2, event3, ...]

        Note over CQRS: Filter events ≤ timestamp
        CQRS->>CQRS: events<br/>|> Enum.filter(&(&1.created_at <= timestamp))

        Note over CQRS: Replay filtered events
        CQRS->>CQRS: Enum.reduce(events, nil, fn event, state -><br/>  apply_event(event.data, state)<br/>end)

        alt State found
            CQRS-->>-Router: {:ok, "postgres://old-value"}
            Router-->>-Client: 200 "postgres://old-value"
        else Not found at that time
            CQRS-->>Router: {:error, :not_found}
            Router-->>Client: 404 Not Found
        end
    end

    Note over CQRS: Point-in-time<br/>reconstruction
```

**Example Timeline:**

```
Time: 09:00 ---|--- 10:00 ---|--- 11:00 ---|--- 12:00 ---
              Set: "val1"   Set: "val2"   Del: null

Query at 09:30: Not Found (before first event)
Query at 10:30: "val1" (after first, before second)
Query at 11:30: "val2" (after second, before delete)
Query at 12:30: Not Found (after delete)
```

**Performance:**
- Few events (<10): ~5ms
- Medium events (10-100): ~10-20ms
- Many events (>100): ~50ms+

---

## 🔄 Projection Rebuild Flow

### Application Startup - Rebuild Process

```mermaid
sequenceDiagram
    autonumber
    participant App as Application.start
    participant Sup as Supervisor
    participant ES as EventStore
    participant Proj as ConfigStateProjection
    participant PG as PostgreSQL

    App->>+Sup: start_children

    Note over Sup: Start EventStore first
    Sup->>+ES: start_link()
    ES->>+PG: Connect
    PG-->>-ES: Connected
    ES-->>-Sup: {:ok, pid}

    Note over Sup: Start Projection second
    Sup->>+Proj: start_link()

    Proj->>Proj: Create ETS table<br/>:config_state_projection

    Note over Proj: Rebuild from all events
    Proj->>+ES: Query all config streams

    ES->>PG: SELECT DISTINCT stream_uuid<br/>FROM streams<br/>WHERE stream_uuid LIKE 'config-%'

    PG-->>ES: ["config-db_url", "config-api_key", ...]

    ES-->>-Proj: Stream list

    loop For each stream
        Proj->>+ES: read_stream_forward("config-db_url")

        ES->>PG: SELECT * FROM events<br/>WHERE stream_uuid = 'config-db_url'<br/>ORDER BY stream_version

        PG-->>ES: [event1, event2, ...]
        ES-->>-Proj: Events

        Note over Proj: Apply each event
        Proj->>Proj: apply_event(ConfigValueSet)<br/>:ets.insert(table, {name, value})
        Proj->>Proj: apply_event(ConfigValueDeleted)<br/>:ets.delete(table, name)
    end

    Note over Proj: Projection ready
    Proj-->>-Sup: {:ok, pid}

    Sup-->>-App: Application started

    Note over Proj: Now serving queries<br/>with complete state
```

**Rebuild Statistics:**
- 10 events: ~50ms
- 100 events: ~200ms
- 1000 events: ~1-2 seconds
- Memory: O(N) where N = number of configs

**State After Rebuild:**
```elixir
# ETS Table Contents
:ets.tab2list(:config_state_projection)
# [
#   {"database_url", "postgres://..."},
#   {"api_key", "secret-123"},
#   {"feature_flag", "enabled"}
# ]
```

---

## 🏥 Health Check Flow

### GET /health - Component Verification

```mermaid
sequenceDiagram
    autonumber
    participant Client
    participant Router
    participant ES as EventStore
    participant Proj as Projection
    participant CQRS as ConfigStoreCQRS

    Client->>+Router: GET /health

    Note over Router: Check EventStore
    Router->>ES: Process.whereis(EventStore)
    alt Process alive
        ES-->>Router: pid
        Router->>Router: eventstore: :ok
    else Process dead
        ES-->>Router: nil
        Router->>Router: eventstore: :down
    end

    Note over Router: Check Projection
    Router->>Proj: Process.whereis(Projection)
    alt Process alive
        Proj-->>Router: pid
        Router->>Router: projection: :ok
    else Process dead
        Proj-->>Router: nil
        Router->>Router: projection: :down
    end

    Note over Router: Check Database
    Router->>CQRS: all()
    alt Query succeeds
        CQRS-->>Router: [configs]
        Router->>Router: database: :ok
    else Query fails
        CQRS-->>Router: error
        Router->>Router: database: :error
    end

    Note over Router: Aggregate results
    Router->>Router: all_healthy = all checks :ok

    alt All healthy
        Router-->>-Client: 200 {"status":"healthy",...}
    else Any unhealthy
        Router-->>Client: 503 {"status":"unhealthy",...}
    end
```

**Health States:**

| Component | OK | Degraded | Down |
|-----------|-----|----------|------|
| EventStore | Process alive | - | Process dead |
| Projection | Process alive | - | Process dead |
| Database | Query works | - | Query fails |

---

## 📊 Performance Summary

### Operation Performance

| Operation | Data Source | Time | Scalability |
|-----------|-------------|------|-------------|
| PUT /config/:name | EventStore | 20-30ms | O(1) |
| GET /config/:name | ETS | <1ms | O(1) |
| GET /config | ETS | 1-10ms | O(N configs) |
| DELETE /config/:name | EventStore | 25-35ms | O(1) |
| GET /history | EventStore | 5-50ms | O(N events) |
| GET /at/:time | EventStore | 10-100ms | O(N events) |
| Rebuild | EventStore | 50ms-2s | O(N events) |
| Health Check | Processes | <5ms | O(1) |

### Throughput Estimates

**Reads (from ETS):**
- Single queries: 10,000+ req/s
- List operations: 1,000+ req/s

**Writes (to PostgreSQL):**
- Single writes: 500-1000 req/s
- Batch operations: Higher with transactions

**Mixed Workload:**
- 90% reads, 10% writes: ~8,000 req/s
- 50% reads, 50% writes: ~2,000 req/s

---

## 🎯 Design Decisions

### Why Restart-Based Consistency?

```mermaid
graph LR
    subgraph "Alternative: Real-Time Subscriptions"
        W1[Write] --> ES1[(EventStore)]
        ES1 --> Sub[Subscription]
        Sub --> Proj1[Projection]
        R1[Read] --> Proj1
    end

    subgraph "Current: Restart-Based"
        W2[Write] --> ES2[(EventStore)]
        Restart[Restart] --> ES2
        ES2 --> Proj2[Projection]
        R2[Read] --> Proj2
    end

    style Sub fill:#ffccbc
    style Restart fill:#c8e6c9
```

**Trade-offs:**

| Aspect | Real-Time | Restart-Based |
|--------|-----------|---------------|
| Complexity | Higher | Lower |
| Consistency | Immediate | Eventual |
| Reliability | Subscription can fail | Always rebuilds |
| Use Case | High-frequency updates | Infrequent updates |
| Debugging | Check subscription state | Just restart |

**Chosen:** Restart-based for simplicity and reliability in configuration management.

---

## 📚 Related Documentation

- **[Architecture Overview](overview.md)** - High-level system design
- **[CQRS Explained](cqrs.md)** - Command/query separation
- **[Event Sourcing](event-sourcing.md)** - Event-based persistence
- **[Components](components.md)** - Detailed component docs
