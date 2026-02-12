# ConfigApi Documentation

Welcome to the ConfigApi documentation! This is a production-grade configuration management system built with CQRS (Command Query Responsibility Segregation) and Event Sourcing patterns.

## 📚 Documentation Structure

### Architecture
- **[Architecture Overview](architecture/overview.md)** - High-level system design and patterns
- **[CQRS Explained](architecture/cqrs.md)** - Understanding CQRS in this application
- **[Event Sourcing](architecture/event-sourcing.md)** - How we use events as the source of truth
- **[Data Flow](architecture/data-flow.md)** - Request/response flows with diagrams
- **[Components](architecture/components.md)** - Detailed component breakdown

### Guides
- **[Quick Start](guides/quick-start.md)** - Get up and running in 5 minutes
- **[Development Guide](guides/development.md)** - Setting up your dev environment
- **[Production Deployment](guides/deployment.md)** - Deploy to production
- **[Testing Guide](guides/testing.md)** - Writing and running tests
- **[Troubleshooting](guides/troubleshooting.md)** - Common issues and solutions

### API Reference
- **[REST API](api/rest-api.md)** - Complete HTTP API reference
- **[CQRS Operations](api/cqrs-operations.md)** - Command and query examples
- **[Event History](api/event-history.md)** - Working with event streams
- **[Time-Travel Queries](api/time-travel.md)** - Point-in-time data retrieval

## 🎯 Quick Links

### For New Users
1. Start with **[Architecture Overview](architecture/overview.md)** to understand the system
2. Follow the **[Quick Start Guide](guides/quick-start.md)** to run the application
3. Explore the **[REST API](api/rest-api.md)** to learn available endpoints

### For Developers
1. Read **[CQRS Explained](architecture/cqrs.md)** to understand the pattern
2. Review **[Components](architecture/components.md)** to see how everything fits together
3. Check **[Development Guide](guides/development.md)** for workflow best practices

### For DevOps
1. See **[Production Deployment](guides/deployment.md)** for deployment strategies
2. Review **[Troubleshooting](guides/troubleshooting.md)** for operational issues
3. Check **[REST API - Health Check](api/rest-api.md#health-check)** for monitoring

## 🔑 Key Concepts

### CQRS (Command Query Responsibility Segregation)
Separate paths for writes (commands) and reads (queries):
- **Commands** modify state and produce events
- **Queries** read from optimized projections
- See: [CQRS Explained](architecture/cqrs.md)

### Event Sourcing
Store all changes as a sequence of events:
- Events are the source of truth
- Complete audit trail of all changes
- Time-travel capabilities
- See: [Event Sourcing](architecture/event-sourcing.md)

### Restart-Based Consistency
The projection rebuilds from events on startup:
- Writes are immediately durable (EventStore)
- Reads require restart to reflect new writes
- Suitable for configuration management
- See: [Architecture Overview](architecture/overview.md#consistency-model)

## 🚀 What This System Provides

### ✅ Core Features
- **Configuration Management** - Store and retrieve key-value configurations
- **Complete Audit Trail** - Every change is recorded with timestamp
- **Event History** - View all changes to any configuration
- **Time-Travel Queries** - See configuration state at any point in time
- **Health Monitoring** - Endpoint for operational monitoring

### ✅ Technical Benefits
- **CQRS Architecture** - Optimized read and write paths
- **Event Sourcing** - Full audit trail and reproducibility
- **Fast Reads** - ETS-based in-memory projections
- **Durable Writes** - PostgreSQL-backed event store
- **High Test Coverage** - 102 tests, all passing

### ✅ Operational Benefits
- **Production-Ready** - Proper supervision and error handling
- **Health Checks** - Monitor component status
- **Easy Debugging** - Replay events to understand state
- **Compliance-Ready** - Complete audit log

## 📊 Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────┐
│                      ConfigApi System                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  HTTP API (Plug/Cowboy)                                     │
│         │                                                    │
│         ├─── Commands ────► ConfigStoreCQRS                 │
│         │                        │                           │
│         │                        ▼                           │
│         │                   ConfigAggregate                  │
│         │                        │                           │
│         │                        ▼                           │
│         │                  Domain Events                     │
│         │                        │                           │
│         │                        ▼                           │
│         │                   EventStore (PostgreSQL)          │
│         │                        │                           │
│         │                        ▼                           │
│         │              ConfigStateProjection (ETS)           │
│         │                        │                           │
│         └─── Queries ────────────┘                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

See [Architecture Overview](architecture/overview.md) for detailed diagrams.

## 🎓 Learning Path

### Beginner
1. **Understand the basics**: Read [Architecture Overview](architecture/overview.md)
2. **Run the app**: Follow [Quick Start](guides/quick-start.md)
3. **Try the API**: Use examples from [REST API](api/rest-api.md)

### Intermediate
1. **Learn CQRS**: Read [CQRS Explained](architecture/cqrs.md)
2. **Understand events**: Study [Event Sourcing](architecture/event-sourcing.md)
3. **See the flow**: Review [Data Flow](architecture/data-flow.md) diagrams

### Advanced
1. **Deep dive**: Explore [Components](architecture/components.md)
2. **Contribute**: Check [Development Guide](guides/development.md)
3. **Deploy**: Follow [Production Deployment](guides/deployment.md)

## 📖 Additional Resources

- **Main README**: [../README.md](../README.md) - Project overview and quick reference
- **QA Reports**: [../QA_FINAL_REPORT.md](../QA_FINAL_REPORT.md) - Test verification results
- **CLAUDE.md**: [../CLAUDE.md](../CLAUDE.md) - AI-assisted development notes

## 💡 Common Use Cases

### Store Configuration
```bash
curl -X PUT http://localhost:4000/config/database_url \
  -H "Content-Type: application/json" \
  -d '{"value":"postgres://localhost/mydb"}'
```

### View Change History
```bash
curl http://localhost:4000/config/database_url/history
```

### Time-Travel Query
```bash
curl http://localhost:4000/config/database_url/at/2026-02-12T10:00:00Z
```

See [REST API](api/rest-api.md) for complete examples.

## 🤝 Contributing

1. Read the [Development Guide](guides/development.md)
2. Check test coverage with `mix test`
3. Follow the existing patterns in [Components](architecture/components.md)

## 📝 License

MIT License - See [../LICENSE](../LICENSE) for details
