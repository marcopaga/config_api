# CQRS Migration Plan

**Goal**: Migrate ConfigApi from simple Memento-based in-memory storage to a stable, scalable CQRS/Event Sourcing implementation with PostgreSQL persistence.

**Timeline Estimate**: 4-6 development sessions
**Risk Level**: Medium (architectural change, but API remains unchanged)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Migration Strategy](#migration-strategy)
3. [Phase-by-Phase Implementation](#phase-by-phase-implementation)
4. [Testing Strategy](#testing-strategy)
5. [Rollback Plan](#rollback-plan)
6. [Success Criteria](#success-criteria)
7. [Risks and Mitigations](#risks-and-mitigations)

---

## Architecture Overview

### Current Architecture (Simple)

```
HTTP Request → Router → ConfigStore → Memento (in-memory) → Response
                            ↓
                    ConfigUpdateWorker (async logging)
```

**Characteristics**:
- Simple CRUD operations
- In-memory storage (no persistence)
- Synchronous reads/writes
- ~100 LOC total business logic

### Target Architecture (CQRS + Event Sourcing)

```
WRITE PATH:
HTTP PUT → Router → ConfigStore → Aggregate → Event → EventStore (PostgreSQL)
                                                         ↓
                                                    Subscription
                                                         ↓
                                                    Projection (ETS)

READ PATH:
HTTP GET → Router → ConfigStore → Projection (ETS) → Response

AUDIT:
Event → ConfigUpdateWorker (async logging)
```

**Characteristics**:
- Event-sourced writes (immutable event log)
- CQRS pattern (separate read/write models)
- PostgreSQL persistence
- ETS-based projection for fast reads
- Complete audit trail
- Time-travel capability

---

## Migration Strategy

### Principle: **Incremental, Test-First, Reversible**

We'll migrate in small, testable phases where each phase:
1. Adds new functionality alongside old code
2. Has comprehensive tests passing
3. Can be rolled back if issues arise
4. Maintains API backward compatibility

### Key Decisions

#### 1. Event Store: `eventstore` library (Hex)
- **Why**: Battle-tested Elixir library, PostgreSQL-backed
- **Alternatives considered**:
  - Commanded (more opinionated, heavier)
  - Custom implementation (too much work)

#### 2. Database: PostgreSQL
- **Why**: ACID compliance, mature, well-supported by EventStore
- **Development**: Docker Compose
- **Production**: Managed PostgreSQL (RDS, Cloud SQL, etc.)

#### 3. Read Model: ETS (Erlang Term Storage)
- **Why**: In-memory fast reads, rebuilt on restart from events
- **Alternative**: PostgreSQL read table (considered for future if ETS limitations hit)

#### 4. Migration Approach: Strangler Pattern
- Keep old Memento code working initially
- Build new CQRS alongside
- Switch over when tests pass
- Remove old code in final phase

---

## Phase-by-Phase Implementation

### Phase 0: Preparation & Infrastructure (Session 1)
**Goal**: Set up infrastructure and testing framework without touching business logic

**Tasks**:
1. Create migration branch `feature/cqrs-migration`
2. Add dependencies to `mix.exs`:
   ```elixir
   {:eventstore, "~> 1.4.8"}
   {:postgrex, "~> 0.21.1"}
   ```
3. Set up Docker Compose for PostgreSQL:
   - Development database: `config_api_eventstore`
   - Test database: `config_api_eventstore_test`
4. Create EventStore configuration:
   - `lib/config_api/event_store.ex`
   - `config/dev.exs` and `config/test.exs`
5. Add EventStore Mix tasks:
   - `mix event_store.create`
   - `mix event_store.init`
   - `mix event_store.drop`

**Tests**:
- [ ] `mix event_store.create` succeeds
- [ ] `mix event_store.init` succeeds
- [ ] Can connect to EventStore in tests
- [ ] Can append and read a dummy event
- [ ] All existing tests still pass (Memento still works)

**Success Criteria**:
- ✅ PostgreSQL running in Docker
- ✅ EventStore initialized and accessible
- ✅ Test helper can reset EventStore between tests
- ✅ Zero impact on existing functionality

**Rollback**: Remove new deps, remove Docker Compose, delete config files

---

### Phase 1: Domain Events (Session 2)
**Goal**: Define domain events without changing ConfigStore behavior

**Tasks**:
1. Create event modules:
   ```
   lib/config_api/events/
   ├── config_value_set.ex
   └── config_value_deleted.ex
   ```
2. Define event structs with:
   - `config_name`, `value`, `old_value`, `timestamp`
   - `new/2` constructor functions
   - Event serialization (automatic via Jason)

**Tests**:
- [ ] Events can be created with `ConfigValueSet.new/3`
- [ ] Events serialize/deserialize to JSON correctly
- [ ] Event timestamps are UTC
- [ ] Events are immutable (struct validation)

**Success Criteria**:
- ✅ Event modules compile and pass tests
- ✅ Events can be encoded/decoded via EventStore serializer
- ✅ No changes to ConfigStore yet (no integration)

**Rollback**: Delete `lib/config_api/events/` directory

---

### Phase 2: Aggregate Implementation (Session 2-3)
**Goal**: Implement ConfigValue aggregate with command/event logic

**Tasks**:
1. Create aggregate:
   ```
   lib/config_api/aggregates/config_value.ex
   ```
2. Implement aggregate struct:
   ```elixir
   defstruct [:name, :value, :version, :deleted]
   ```
3. Implement commands:
   - `set_value(aggregate, name, value)` → `{:ok, event, new_aggregate}`
   - `delete_value(aggregate)` → `{:ok, event, new_aggregate}`
4. Implement event application:
   - `apply_event(aggregate, ConfigValueSet)` → new aggregate
   - `apply_event(aggregate, ConfigValueDeleted)` → new aggregate
5. Implement event replay:
   - `replay_events([events])` → aggregate state
6. Business rules:
   - Cannot set value on deleted config
   - Cannot delete non-existent config

**Tests**:
- [ ] New aggregate starts with nil name/value, version 0
- [ ] `set_value` produces ConfigValueSet event
- [ ] `set_value` increments version
- [ ] Cannot set value on deleted aggregate
- [ ] `delete_value` produces ConfigValueDeleted event
- [ ] Cannot delete already-deleted aggregate
- [ ] Event replay rebuilds correct state
- [ ] Event replay maintains version correctly
- [ ] Multiple events replay in correct order

**Success Criteria**:
- ✅ Aggregate business logic fully tested in isolation
- ✅ No EventStore integration yet
- ✅ Pure functions, easy to test

**Rollback**: Delete `lib/config_api/aggregates/` directory

---

### Phase 3: Projection Implementation (Session 3)
**Goal**: Build read model that subscribes to events

**Tasks**:
1. Create projection:
   ```
   lib/config_api/projections/config_state_projection.ex
   ```
2. Implement as GenServer with ETS table
3. Subscribe to EventStore `$all` stream
4. Handle events:
   - `ConfigValueSet` → update ETS table
   - `ConfigValueDeleted` → remove from ETS table
5. Implement query functions:
   - `get_config(name)` → `{:ok, value}` or `{:error, :not_found}`
   - `get_all_configs()` → `[%{name: ..., value: ...}]`
6. Implement state rebuild:
   - On startup, replay all events from EventStore
   - Build ETS table from scratch

**Tests**:
- [ ] Projection starts with empty ETS table
- [ ] Can manually insert events and query results
- [ ] Handles ConfigValueSet events correctly
- [ ] Handles ConfigValueDeleted events correctly
- [ ] Handles update (multiple ConfigValueSet for same key)
- [ ] `get_all_configs` returns all non-deleted configs
- [ ] State rebuild works after restart
- [ ] Projection handles events in correct order

**Integration Tests**:
- [ ] Append events to EventStore → Projection receives them
- [ ] Stop/restart projection → State rebuilds correctly
- [ ] Concurrent event processing works correctly

**Success Criteria**:
- ✅ Projection maintains consistent read model
- ✅ Projection survives restarts
- ✅ Fast reads from ETS (no database queries)

**Rollback**: Delete `lib/config_api/projections/` directory, remove from Application

---

### Phase 4: New ConfigStore with CQRS (Session 4)
**Goal**: Implement new ConfigStore using aggregates, events, and projections

**Tasks**:
1. Create new module:
   ```
   lib/config_api/config_store_cqrs.ex
   ```
2. Implement write path:
   ```elixir
   put(name, value) ->
     1. Load aggregate events from EventStore
     2. Replay events to build aggregate
     3. Execute command on aggregate
     4. Append new event to EventStore
     5. Return result
   ```
3. Implement read path:
   ```elixir
   get(name) ->
     Query projection (fast ETS lookup)

   all() ->
     Query projection (ETS table scan)
   ```
4. Implement additional features:
   ```elixir
   get_history(name) -> all events for config
   get_at_timestamp(name, timestamp) -> time-travel query
   delete(name) -> delete command
   ```
5. Integrate ConfigUpdateWorker (send messages on events)

**Tests**:
- [ ] PUT stores event in EventStore
- [ ] PUT returns success
- [ ] GET retrieves from projection (not EventStore)
- [ ] PUT → GET workflow works
- [ ] UPDATE workflow (PUT same key twice)
- [ ] DELETE workflow
- [ ] GET after DELETE returns :not_found
- [ ] `all()` returns all non-deleted configs
- [ ] `get_history/1` returns all events for a config
- [ ] `get_at_timestamp/2` time-travel works
- [ ] ConfigUpdateWorker receives notifications

**Integration Tests**:
- [ ] Full workflow: PUT → wait for projection → GET
- [ ] Multiple configs workflow
- [ ] Delete workflow with projection update
- [ ] Projection restart → state rebuilds → GET works
- [ ] Concurrent writes to same config (version conflicts)

**Success Criteria**:
- ✅ New ConfigStoreCQRS module fully functional
- ✅ All tests passing
- ✅ Old ConfigStore still exists and works

**Rollback**: Delete `config_store_cqrs.ex`, keep old ConfigStore

---

### Phase 5: Router Integration & Switchover (Session 5)
**Goal**: Switch router to use new CQRS ConfigStore

**Tasks**:
1. Update Application supervision tree:
   ```elixir
   children = [
     ConfigApi.EventStore,
     ConfigApi.Projections.ConfigStateProjection,
     ConfigApi.ConfigUpdateWorker,
     {Plug.Cowboy, ...}
   ]
   ```
2. Create configuration flag for switching:
   ```elixir
   # config/config.exs
   config :config_api, :storage_backend, :cqrs  # or :memento
   ```
3. Update ConfigStore to delegate based on flag:
   ```elixir
   defdelegate put(name, value), to: backend()
   defdelegate get(name), to: backend()
   defdelegate all(), to: backend()

   defp backend do
     case Application.get_env(:config_api, :storage_backend) do
       :cqrs -> ConfigApi.ConfigStoreCQRS
       :memento -> ConfigApi.ConfigStoreMemento
     end
   end
   ```
4. Rename old ConfigStore → ConfigStoreMemento
5. Rename ConfigStoreCQRS → ConfigStore
6. Test with both backends

**Tests**:
- [ ] All existing tests pass with :memento backend
- [ ] All existing tests pass with :cqrs backend
- [ ] Can switch backends via config
- [ ] Router integration tests pass
- [ ] HTTP-level tests pass (curl-style tests)

**API Tests** (HTTP level):
- [ ] `GET /config` returns empty array initially
- [ ] `GET /config/foo` returns 404 when not found
- [ ] `PUT /config/foo` with value "bar" returns 200
- [ ] `GET /config/foo` returns "bar"
- [ ] `PUT /config/foo` with value "baz" updates to "baz"
- [ ] `GET /config` returns all configs as JSON
- [ ] `DELETE /config/foo` returns 200
- [ ] `GET /config/foo` returns 404 after delete

**Success Criteria**:
- ✅ All tests pass with CQRS backend
- ✅ API behavior unchanged from user perspective
- ✅ Can switch back to Memento if needed (feature flag)

**Rollback**: Set config to `:memento`, all tests still pass

---

### Phase 6: Cleanup & Documentation (Session 6)
**Goal**: Remove old code, finalize migration, update docs

**Tasks**:
1. Remove Memento backend code:
   - Delete `lib/config_api/config_store_memento.ex`
   - Delete `lib/config_api/config_value.ex` (Memento table)
   - Delete `lib/config_api/db.ex`
   - Remove Memento dependency from `mix.exs`
2. Remove backend switching logic (hardcode CQRS)
3. Update README.md with:
   - CQRS architecture explanation
   - Database setup instructions
   - New API features (history, time-travel)
4. Update CLAUDE.md with CQRS architecture
5. Add operational runbook:
   - Database backup/restore
   - Event replay procedures
   - Projection rebuild procedures
6. Add migration guide for any existing users

**Tests**:
- [ ] All tests pass without Memento
- [ ] Application starts clean (no Memento warnings)
- [ ] Mix deps shows no Memento

**Documentation**:
- [ ] README.md updated
- [ ] CLAUDE.md updated
- [ ] API documentation includes new endpoints
- [ ] Database setup documented
- [ ] Troubleshooting guide added

**Success Criteria**:
- ✅ Clean codebase with only CQRS code
- ✅ Comprehensive documentation
- ✅ Ready for production use

**Rollback**: Git revert to Phase 5 (can still use Memento backend)

---

## Testing Strategy

### Test Pyramid

```
                    /\
                   /  \
                  / E2E\          (API-level HTTP tests)
                 /______\
                /        \
               / Integration\     (EventStore + Projection + ConfigStore)
              /____________\
             /              \
            /   Unit Tests   \   (Aggregate, Events, Projection in isolation)
           /________________\
```

### Test Categories

#### 1. Unit Tests (Fast, Isolated)
**Run time: < 100ms total**

- **Aggregate Tests**: Pure functions, no I/O
  - Command validation
  - Event generation
  - State transitions
  - Business rule enforcement

- **Event Tests**: Struct validation
  - Event creation
  - Serialization

- **Projection Tests** (with mock events):
  - ETS updates
  - Query functions

**Tools**: ExUnit with `async: true`

#### 2. Integration Tests (Medium, Real Components)
**Run time: < 2 seconds total**

- **EventStore Integration**:
  - Append events
  - Read streams
  - Stream subscriptions

- **Projection Integration**:
  - Event subscription works
  - Projection rebuilds state
  - Concurrent event handling

- **ConfigStore Integration**:
  - Full write path (aggregate → event → store)
  - Full read path (projection → ETS)
  - Time-travel queries

**Setup**:
- Real PostgreSQL (test database)
- EventStore reset between tests
- `async: false` for EventStore tests

#### 3. End-to-End Tests (Slow, Full Stack)
**Run time: < 5 seconds total**

- **HTTP API Tests**:
  - Start application
  - Make HTTP requests
  - Verify responses
  - Test full CRUD workflow

**Tools**:
- `Plug.Test` for HTTP testing
- Real application stack

### Test Data Strategy

**Use factories for consistency**:
```elixir
# test/support/factories.ex
defmodule ConfigApi.Factory do
  def config_name(n \\ 1), do: "test_config_#{n}"
  def config_value(n \\ 1), do: "test_value_#{n}"

  def config_value_set_event(name, value) do
    ConfigApi.Events.ConfigValueSet.new(name, value, nil)
  end
end
```

### Test Coverage Goals

- **Aggregate**: 100% coverage (pure logic, critical)
- **Events**: 100% coverage (simple, easy to test)
- **Projection**: 95%+ coverage (complex state management)
- **ConfigStore**: 90%+ coverage (integration points)
- **Router**: 80%+ coverage (HTTP handling)

**Overall target**: 90%+ test coverage

### Confidence Builders

1. **Property-based testing** (future enhancement):
   - Use StreamData for aggregate property tests
   - Generate random event sequences, verify invariants

2. **Mutation testing** (future enhancement):
   - Use Muzak to verify tests catch bugs

3. **Load testing** (future):
   - Test concurrent writes
   - Test projection performance under load

---

## Rollback Plan

### Per-Phase Rollback

Each phase can be rolled back independently:
- **Phase 0-3**: Delete new files, remove new deps
- **Phase 4**: Keep old ConfigStore, delete new one
- **Phase 5**: Change config flag to `:memento`
- **Phase 6**: Git revert, restore Memento

### Emergency Rollback (Production)

If deployed to production and issues arise:

1. **Immediate** (< 1 minute):
   ```bash
   # Revert to previous git commit
   git revert HEAD
   git push
   # Deploy previous version
   ```

2. **Data preservation**:
   - EventStore data persists in PostgreSQL
   - Can rebuild projection at any time
   - No data loss (only availability issue)

3. **Staged rollback**:
   ```bash
   # Switch to Memento backend via config
   export STORAGE_BACKEND=memento
   # Restart application
   ```

### Point of No Return

**Phase 6 completion** = committed to CQRS:
- After removing Memento code, must stay on CQRS
- Can still rollback via git, but requires code changes
- Database migration would be needed to go back

---

## Success Criteria

### Phase Completion Criteria

Each phase must meet:
- ✅ All tests passing (no flaky tests)
- ✅ Code reviewed (if team environment)
- ✅ Documentation updated
- ✅ Rollback tested
- ✅ No regressions in existing functionality

### Final Success Criteria

Before considering migration complete:

#### Functional Requirements
- ✅ All original API endpoints work identically
- ✅ New features work (history, time-travel, delete)
- ✅ Data persists across restarts
- ✅ Projection rebuilds correctly on startup
- ✅ Audit logging works (ConfigUpdateWorker)

#### Non-Functional Requirements
- ✅ Response time: GET < 10ms (p95)
- ✅ Response time: PUT < 50ms (p95)
- ✅ Test suite runs in < 10 seconds
- ✅ Test coverage > 90%
- ✅ Zero flaky tests
- ✅ Application starts in < 5 seconds

#### Operational Requirements
- ✅ Database setup documented
- ✅ Backup/restore procedures documented
- ✅ Monitoring/logging in place
- ✅ Error handling tested (DB down, etc.)

#### Code Quality
- ✅ No compiler warnings
- ✅ Consistent code style (`mix format`)
- ✅ Credo passes (if using)
- ✅ Dialyzer passes (if using)

---

## Risks and Mitigations

### Risk 1: EventStore `reset!` function missing
**Likelihood**: High (encountered in previous attempt)
**Impact**: Medium (test infrastructure breaks)

**Mitigation**:
- Check EventStore API documentation first
- Implement custom reset function if needed:
  ```elixir
  def reset_event_store! do
    ConfigApi.EventStore.delete_all_streams!()
    # Or: drop and recreate database in tests
  end
  ```
- Alternative: Use test database that gets dropped/recreated each run

### Risk 2: Eventual consistency issues
**Likelihood**: Medium (CQRS introduces async processing)
**Impact**: High (test failures, race conditions)

**Mitigation**:
- Add explicit wait mechanisms in tests:
  ```elixir
  def wait_for_projection(name, max_wait \\ 1000) do
    # Poll until projection has value or timeout
  end
  ```
- Use Phoenix.PubSub to notify when projection updates
- Consider making projection updates synchronous in tests

### Risk 3: Event schema changes
**Likelihood**: Low (events should be immutable)
**Impact**: High (can't deserialize old events)

**Mitigation**:
- Version events from day 1:
  ```elixir
  %ConfigValueSet{
    version: 1,
    config_name: "foo",
    value: "bar"
  }
  ```
- Create event upcaster pattern for schema migrations
- Document event schema evolution policy

### Risk 4: PostgreSQL dependency in tests
**Likelihood**: Low (Docker makes this easy)
**Impact**: Medium (slower tests, CI setup complexity)

**Mitigation**:
- Use Docker Compose for local development
- Use GitHub Actions services for CI
- Document PostgreSQL setup clearly
- Consider in-memory PostgreSQL for faster tests (pg_tmp)

### Risk 5: Performance degradation
**Likelihood**: Low (ETS projections are fast)
**Impact**: Medium (slower API responses)

**Mitigation**:
- Benchmark before and after migration
- Monitor p95 response times
- Optimize projection if needed
- Consider caching strategies
- Profile with `:observer` and `:fprof`

### Risk 6: Projection rebuild time
**Likelihood**: Medium (as events accumulate)
**Impact**: Low (only affects startup)

**Mitigation**:
- Implement projection snapshots (future)
- Optimize event replay with batching
- Monitor rebuild time as events grow
- Consider projection caching strategies

### Risk 7: Testing fatigue
**Likelihood**: Medium (comprehensive test suite takes time)
**Impact**: Medium (might skip tests, reduce quality)

**Mitigation**:
- Write tests incrementally (TDD approach)
- Keep tests fast (unit > integration > e2e ratio)
- Use test factories to reduce boilerplate
- Run tests frequently during development
- Celebrate test milestones

---

## Open Questions

These should be answered before starting:

1. **Deployment Environment**:
   - Where will this run? (local, cloud, on-prem)
   - What PostgreSQL version?
   - Managed DB or self-hosted?

2. **Scale Requirements**:
   - Expected request rate?
   - Expected number of config keys?
   - Expected event volume growth?

3. **Backup Strategy**:
   - How often to backup EventStore?
   - Point-in-time recovery needed?
   - Backup retention policy?

4. **Monitoring**:
   - What metrics to track?
   - Alerting requirements?
   - Log aggregation setup?

5. **Team**:
   - Working solo or with team?
   - Code review process?
   - Pair programming sessions?

---

## Estimated Effort

### Time Breakdown

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| Phase 0: Infrastructure | Setup, config, basic tests | 2-3 hours |
| Phase 1: Events | Event definitions, serialization tests | 1-2 hours |
| Phase 2: Aggregates | Business logic, comprehensive tests | 3-4 hours |
| Phase 3: Projections | GenServer, ETS, subscriptions, tests | 4-5 hours |
| Phase 4: ConfigStore CQRS | Integration, full workflow tests | 4-6 hours |
| Phase 5: Switchover | Router update, HTTP tests, verification | 2-3 hours |
| Phase 6: Cleanup | Remove old code, documentation | 2-3 hours |
| **Total** | | **18-26 hours** |

### Session Breakdown (assuming 3-4 hour sessions)

- **Session 1**: Phase 0 + start Phase 1
- **Session 2**: Complete Phase 1 + Phase 2
- **Session 3**: Phase 3 (projections)
- **Session 4**: Phase 4 (CQRS ConfigStore)
- **Session 5**: Phase 5 (switchover and testing)
- **Session 6**: Phase 6 (cleanup and docs)

**Total: 6 sessions** (can be compressed to 4 if needed)

---

## Next Steps

To proceed with this plan:

1. **Review this plan** - Any questions or concerns?
2. **Answer open questions** - Deployment, scale, monitoring needs
3. **Schedule sessions** - Block time for focused development
4. **Start Phase 0** - Create branch, set up infrastructure

Once approved, we can begin with Phase 0 immediately.

---

## References

- **EventStore Docs**: https://hexdocs.pm/eventstore/
- **CQRS Pattern**: https://martinfowler.com/bliki/CQRS.html
- **Event Sourcing**: https://martinfowler.com/eaaDev/EventSourcing.html
- **Strangler Pattern**: https://martinfowler.com/bliki/StranglerFigApplication.html
