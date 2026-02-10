# Project Context & Decisions

**Last Updated**: 2026-02-10

This document captures key decisions and context for the CQRS migration project.

---

## Project Overview

**Purpose**: Learning project to implement CQRS/Event Sourcing patterns in Elixir
**Status**: Planning phase complete, ready for Phase 0 implementation
**Team**: Solo developer (Marco)
**Timeline**: Flexible, work at own pace

---

## Deployment & Infrastructure

### Deployment Environment
- **Target**: Local development only
- **Rationale**: Learning/experimentation project, no production deployment planned
- **Implications**:
  - Can use simpler setup (Docker Compose)
  - No need for high availability or load balancing
  - Can prioritize learning over production-readiness
  - Easier to experiment and rebuild

### Database Setup
- **PostgreSQL**: Docker Compose (development only)
- **Rationale**: Simple, self-contained, easy to reset
- **Configuration**:
  - Development DB: `config_api_eventstore`
  - Test DB: `config_api_eventstore_test`
  - Containerized via docker-compose.yml
- **Implications**:
  - Data lost on container removal (acceptable for learning)
  - Easy to reset/rebuild: `docker-compose down -v && docker-compose up -d`
  - No need for connection pooling optimization
  - No need for SSL/TLS configuration

---

## Scale Requirements

### Request Volume
- **Expected**: < 100 requests/minute (Small scale)
- **Rationale**: Learning project, personal use, light usage
- **Implications**:
  - ETS projection will be more than sufficient
  - No need for caching strategies
  - Single instance deployment adequate
  - Connection pool size: 10 is plenty

### Data Volume
- **Expected**: < 100 configuration keys
- **Rationale**: Simple config like app settings, feature flags
- **Event Growth Estimate**:
  - Assume 10 updates per key over lifetime = ~1,000 events total
  - Very manageable for PostgreSQL and event replay
- **Implications**:
  - Projection rebuild on startup will be instant (< 100ms)
  - No need for snapshot optimization
  - No need for event archival strategy
  - Full event history query is feasible

---

## Backup & Recovery

### Backup Strategy
- **Strategy**: No backups needed (learning project)
- **Rationale**: Can afford to lose data, just experimenting
- **Implications**:
  - No automated backup setup required
  - Can manually export via `pg_dump` if needed for reference
  - Focus development time on features, not backup infrastructure
  - Acceptable to rebuild from scratch if needed

### Disaster Recovery
- **RTO (Recovery Time Objective)**: N/A
- **RPO (Recovery Point Objective)**: N/A
- **Recovery Plan**: Rebuild from docker-compose and re-initialize EventStore

---

## Monitoring & Observability

### Logging
- ✅ **Basic logging**: Already have (Logger.info/error)
- ✅ **Structured logging**: JSON logs, log aggregation
- ✅ **Metrics**: Response times, event counts

### Implementation Plan
1. **Basic Logging** (Already implemented):
   - ConfigUpdateWorker logs all config changes
   - Router logs requests
   - Keep existing Logger setup

2. **Metrics** (Add during migration):
   - Use `:telemetry` library (already dependency via Plug)
   - Track metrics:
     - Request counts by endpoint
     - Response times (p50, p95, p99)
     - Event append rate
     - Projection rebuild time
     - EventStore query times
   - Simple in-memory metrics (no external system needed)

3. **Structured Logging** (Add during Phase 6):
   - Configure Logger for JSON output
   - Add structured metadata to log entries:
     ```elixir
     Logger.info("Config updated",
       config_name: name,
       old_value: old_value,
       new_value: new_value,
       timestamp: timestamp
     )
     ```
   - Can pipe to console or file for analysis

### Not Needed
- ❌ APM / distributed tracing (single-service application)
- ❌ External monitoring services (local project)
- ❌ Alerting infrastructure

---

## Team & Workflow

### Team Structure
- **Solo developer**: Marco
- **No formal code reviews needed**
- **Can self-review before committing**

### Development Workflow
1. Work through phases at own pace
2. Commit frequently with descriptive messages
3. Run tests before each commit
4. Document learnings and decisions

### Git Strategy
- **Branch**: `feature/cqrs-migration` for entire migration
- **Commits**: One commit per logical step (not per file)
- **Merging**: Merge to main when phase complete and stable
- **Tagging**: Tag milestones (e.g., `v0.2.0-phase3-complete`)

---

## Timeline & Pacing

### Approach
- **Flexible**: Work at own pace
- **Session-based**: 3-4 hour focused sessions when available
- **Breaks allowed**: Can pause between phases
- **No deadline pressure**

### Recommended Pace
- **Week 1-2**: Phase 0-1 (Infrastructure + Events)
- **Week 3-4**: Phase 2-3 (Aggregates + Projections)
- **Week 5-6**: Phase 4-5 (CQRS ConfigStore + Switchover)
- **Week 7**: Phase 6 (Cleanup + Documentation)

**Total estimated calendar time**: 6-8 weeks (working on weekends or evenings)

### Session Planning
- Each session = 1 phase (approximately)
- Take breaks between sessions to absorb learnings
- Write notes/reflections after each phase
- No pressure to complete continuously

---

## Technology Decisions

### Core Stack
- **Language**: Elixir 1.18.4
- **Runtime**: Erlang/OTP 28.0.2
- **Database**: PostgreSQL 14 (via Docker)
- **Event Store**: `eventstore` library v1.4.8
- **Web Server**: Plug + Cowboy
- **Testing**: ExUnit

### Key Libraries
- `eventstore` - Event sourcing infrastructure
- `postgrex` - PostgreSQL driver
- `jason` - JSON encoding/decoding
- `plug_cowboy` - HTTP server
- `telemetry` - Metrics (add during migration)

### Architectural Patterns
- **Event Sourcing**: All state changes as immutable events
- **CQRS**: Separate read and write models
- **Aggregate Pattern**: Domain logic encapsulated in aggregates
- **Projection Pattern**: Read model built from events
- **GenServer**: For projection and worker processes

---

## Success Criteria (Customized for Learning Project)

### Functional
- ✅ All original API endpoints work
- ✅ Events persist in PostgreSQL
- ✅ Projection rebuilds correctly
- ✅ Time-travel queries work
- ✅ Audit trail is complete

### Educational (Learning Goals)
- ✅ Understand Event Sourcing deeply
- ✅ Understand CQRS pattern
- ✅ Learn EventStore library
- ✅ Practice test-driven development
- ✅ Document learnings

### Technical
- ✅ Test coverage > 90%
- ✅ All tests pass consistently
- ✅ No flaky tests
- ✅ Clean code (mix format, no warnings)
- ✅ Well-documented (inline comments where needed)

### Performance (Relaxed for learning project)
- ⚠️ GET requests < 50ms (p95) - good enough for local dev
- ⚠️ PUT requests < 100ms (p95) - acceptable for learning
- ✅ Test suite < 15 seconds - keep tests fast
- ✅ Application starts < 10 seconds

---

## Simplifications (vs. Production)

Because this is a learning project, we can simplify:

### Skip/Defer
1. **High Availability**: Single instance is fine
2. **Load Balancing**: Not needed
3. **SSL/TLS**: Local development doesn't need encryption
4. **Authentication**: No auth layer needed
5. **Rate Limiting**: No abuse concerns
6. **Error Reporting**: Logger is sufficient (no Sentry/Rollbar)
7. **CI/CD**: Can test locally, no need for pipelines
8. **Staging Environment**: Production = development
9. **Database Replication**: Single database instance
10. **Backup Automation**: Manual if needed

### Keep Simple
1. **Configuration**: Environment variables via `.env` or hardcode
2. **Secrets Management**: No vault needed, can use plain config
3. **Monitoring**: Built-in Logger + simple metrics
4. **Deployment**: `docker-compose up -d` is sufficient
5. **Testing**: Local only, no separate test environment

---

## Open Questions Answered

### ✅ Deployment Environment
**Answer**: Local development only
**Impact**: Simplified infrastructure, Docker Compose is sufficient

### ✅ PostgreSQL Setup
**Answer**: Docker Compose for development
**Impact**: Self-contained, easy reset, no cloud costs

### ✅ Scale Requirements
**Answer**: Small scale (< 100 req/min, < 100 keys)
**Impact**: ETS projection sufficient, no optimization needed

### ✅ Backup Strategy
**Answer**: No backups needed (learning project)
**Impact**: Skip backup infrastructure, focus on features

### ✅ Monitoring
**Answer**: Basic logging + metrics + structured logging
**Impact**: Add telemetry metrics, configure JSON logging

### ✅ Team
**Answer**: Solo developer
**Impact**: Self-paced, no code review coordination needed

### ✅ Timeline
**Answer**: Flexible, work at own pace
**Impact**: Can pause between phases, no sprint pressure

---

## Risk Assessment (Updated)

Given the project context, risk levels are adjusted:

| Risk | Original Level | Adjusted Level | Rationale |
|------|---------------|----------------|-----------|
| EventStore reset! missing | 🔴 High | 🟡 Medium | Can iterate locally until solved |
| Eventual consistency | 🟡 Medium | 🟢 Low | Learning project, can add wait helpers |
| PostgreSQL in tests | 🟡 Medium | 🟢 Low | Docker Compose is easy, have time to debug |
| Testing fatigue | 🟡 Medium | 🟢 Low | Flexible timeline reduces pressure |
| Event schema changes | 🟢 Low | 🟢 Low | Small dataset, easy to rebuild |
| Performance issues | 🟢 Low | 🟢 Low | Low scale, performance not critical |
| Production deployment | 🟡 Medium | 🟢 N/A | Not deploying to production |

**Overall Risk**: Low (learning environment, flexible timeline, small scale)

---

## Next Actions

Based on this context:

1. **Proceed with Phase 0** using PHASE_0_CHECKLIST.md
2. **Add telemetry metrics** during Phase 4 (ConfigStore implementation)
3. **Configure structured logging** during Phase 6 (cleanup)
4. **Document learnings** in a LEARNINGS.md file (create during migration)
5. **Take breaks** between phases to absorb concepts

---

## Learning Goals

### Phase 0-1: Infrastructure & Events
- Learn PostgreSQL setup with Docker
- Understand EventStore library
- Learn event serialization

### Phase 2: Aggregates
- Learn aggregate pattern
- Understand command/event separation
- Practice pure functional design

### Phase 3: Projections
- Learn GenServer for stateful processes
- Understand ETS (Erlang Term Storage)
- Learn event subscriptions

### Phase 4: CQRS Integration
- Understand CQRS pattern deeply
- Learn event replay and sourcing
- Practice integration testing

### Phase 5-6: Production Readiness
- Learn migration strategies
- Understand backward compatibility
- Practice documentation

---

## References for Learning

- **EventStore Docs**: https://hexdocs.pm/eventstore/
- **CQRS**: https://martinfowler.com/bliki/CQRS.html
- **Event Sourcing**: https://martinfowler.com/eaaDev/EventSourcing.html
- **Elixir GenServer**: https://hexdocs.pm/elixir/GenServer.html
- **ETS Guide**: https://elixir-lang.org/getting-started/mix-otp/ets.html
- **Telemetry**: https://hexdocs.pm/telemetry/

---

## Notes

Add notes and learnings here as you progress through the migration:

- [Add notes during Phase 0]
- [Add reflections after each phase]
- [Document unexpected challenges]
- [Record "aha!" moments]
