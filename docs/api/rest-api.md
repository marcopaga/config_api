# REST API Reference

Complete HTTP API reference for ConfigApi.

## 📋 Base Information

- **Base URL:** `http://localhost:4000`
- **Content-Type:** `application/json` (for POST/PUT)
- **Response Format:** JSON or plain text (depending on endpoint)
- **Authentication:** None (add as needed)

## 🏥 Health Check

### GET /health

Check if the application and all components are running properly.

**Request:**
```bash
curl http://localhost:4000/health
```

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2026-02-12T10:30:00.123456Z",
  "checks": {
    "eventstore": "ok",
    "projection": "ok",
    "database": "ok"
  }
}
```

**Response (503 Service Unavailable):**
```json
{
  "status": "unhealthy",
  "timestamp": "2026-02-12T10:30:00.123456Z",
  "checks": {
    "eventstore": "ok",
    "projection": "down",
    "database": "ok"
  }
}
```

**Use Cases:**
- Load balancer health checks
- Monitoring alerts
- Deployment verification
- Troubleshooting

---

## 📝 Configuration Management

### GET /config

List all configurations.

**Request:**
```bash
curl http://localhost:4000/config
```

**Response (200 OK):**
```json
[
  {
    "name": "database_url",
    "value": "postgres://localhost/mydb"
  },
  {
    "name": "api_key",
    "value": "secret-key-123"
  }
]
```

**Response (Empty):**
```json
[]
```

**Notes:**
- Returns data from projection (ETS)
- Requires restart to see new writes
- Fast response (sub-millisecond)

---

### GET /config/:name

Get a specific configuration value.

**Request:**
```bash
curl http://localhost:4000/config/database_url
```

**Response (200 OK):**
```
postgres://localhost/mydb
```
*Note: Plain text response, not JSON*

**Response (404 Not Found):**
```
Not Found
```

**Example with jq:**
```bash
# Store as variable
DB_URL=$(curl -s http://localhost:4000/config/database_url)
echo $DB_URL
# postgres://localhost/mydb
```

---

### PUT /config/:name

Set or update a configuration value.

**Request:**
```bash
curl -X PUT http://localhost:4000/config/database_url \
  -H "Content-Type: application/json" \
  -d '{"value":"postgres://production/mydb"}'
```

**Request Body:**
```json
{
  "value": "postgres://production/mydb"
}
```

**Response (200 OK):**
```
OK
```

**Response (500 Internal Server Error):**
```
Internal Server Error
```

**Important:**
- Event is immediately persisted to EventStore
- Projection updates on next restart
- Use `/config/:name/history` to verify immediately

**Examples:**

```bash
# Simple string value
curl -X PUT http://localhost:4000/config/app_name \
  -H "Content-Type: application/json" \
  -d '{"value":"MyApp"}'

# Empty string (valid)
curl -X PUT http://localhost:4000/config/empty_config \
  -H "Content-Type: application/json" \
  -d '{"value":""}'

# Unicode characters
curl -X PUT http://localhost:4000/config/greeting \
  -H "Content-Type: application/json" \
  -d '{"value":"Hello 世界 🌍"}'

# JSON string (store as string)
curl -X PUT http://localhost:4000/config/settings \
  -H "Content-Type: application/json" \
  -d '{"value":"{\"timeout\":30,\"retry\":3}"}'

# Long value
curl -X PUT http://localhost:4000/config/long_value \
  -H "Content-Type: application/json" \
  -d "{\"value\":\"$(printf 'A%.0s' {1..1000})\"}"
```

---

### DELETE /config/:name

Delete a configuration.

**Request:**
```bash
curl -X DELETE http://localhost:4000/config/old_key
```

**Response (200 OK):**
```
OK
```

**Response (404 Not Found):**
```
Not Found
```

**Response (410 Gone):**
```
Gone
```
*Returned if configuration was already deleted*

**Response (500 Internal Server Error):**
```
Internal Server Error
```

**Notes:**
- Deletion is recorded as `ConfigValueDeleted` event
- Once deleted, configuration cannot be set again (in current version)
- Deletion event preserved in event history

---

## 📜 Event History

### GET /config/:name/history

Get complete event history for a configuration.

**Request:**
```bash
curl http://localhost:4000/config/database_url/history
```

**Response (200 OK):**
```json
[
  {
    "event_type": "Elixir.ConfigApi.Events.ConfigValueSet",
    "data": {
      "config_name": "database_url",
      "value": "postgres://localhost/mydb",
      "old_value": null,
      "timestamp": "2026-02-12T10:00:00.123456Z"
    },
    "metadata": {
      "aggregate_id": "database_url",
      "aggregate_type": "ConfigValue"
    },
    "created_at": "2026-02-12T10:00:00.123456Z",
    "stream_version": 1
  },
  {
    "event_type": "Elixir.ConfigApi.Events.ConfigValueSet",
    "data": {
      "config_name": "database_url",
      "value": "postgres://production/mydb",
      "old_value": "postgres://localhost/mydb",
      "timestamp": "2026-02-12T11:00:00.654321Z"
    },
    "metadata": {
      "aggregate_id": "database_url",
      "aggregate_type": "ConfigValue"
    },
    "created_at": "2026-02-12T11:00:00.654321Z",
    "stream_version": 2
  }
]
```

**Response (Empty stream):**
```json
[]
```

**Response (500 Internal Server Error):**
```
Internal Server Error
```

**Use Cases:**
- Audit trail
- Debugging changes
- Compliance reporting
- Understanding who changed what when

**Example Analysis:**
```bash
# Get history
curl -s http://localhost:4000/config/api_key/history | jq

# Count changes
curl -s http://localhost:4000/config/api_key/history | jq 'length'

# Get first change
curl -s http://localhost:4000/config/api_key/history | jq '.[0]'

# Get all timestamps
curl -s http://localhost:4000/config/api_key/history | jq '.[].data.timestamp'
```

---

## ⏰ Time-Travel Queries

### GET /config/:name/at/:timestamp

Get configuration value as it existed at a specific point in time.

**Request:**
```bash
curl http://localhost:4000/config/database_url/at/2026-02-12T10:30:00Z
```

**Timestamp Format:** ISO8601 (e.g., `2026-02-12T10:30:00Z`)

**Response (200 OK):**
```
postgres://localhost/mydb
```

**Response (404 Not Found):**
```
Not Found
```
*Configuration didn't exist at that time*

**Response (400 Bad Request):**
```
Invalid timestamp format. Use ISO8601 (e.g., 2024-01-15T10:30:00Z)
```

**Response (500 Internal Server Error):**
```
Internal Server Error
```

**Examples:**

```bash
# Value at 10:00 AM
curl http://localhost:4000/config/database_url/at/2026-02-12T10:00:00Z
# postgres://localhost/mydb

# Value at 11:00 AM (after update)
curl http://localhost:4000/config/database_url/at/2026-02-12T11:00:00Z
# postgres://production/mydb

# Value before it existed
curl http://localhost:4000/config/database_url/at/2026-02-11T10:00:00Z
# Not Found

# Current time (or future time)
curl http://localhost:4000/config/database_url/at/2026-02-13T10:00:00Z
# Latest value
```

**Use Cases:**
- Debugging: "What was the value when the bug occurred?"
- Auditing: "When did this configuration change?"
- Recovery: "What was the working configuration?"
- Analysis: "How has this value changed over time?"

---

## 📊 Response Status Codes

| Code | Meaning | When |
|------|---------|------|
| 200 | OK | Request succeeded |
| 400 | Bad Request | Invalid timestamp format |
| 404 | Not Found | Configuration doesn't exist |
| 410 | Gone | Configuration was deleted |
| 500 | Internal Server Error | Server-side error |
| 503 | Service Unavailable | Health check failed |

---

## 🔄 Complete Workflow Example

### Scenario: Update Database URL

```bash
# 1. Check current value
curl http://localhost:4000/config/database_url
# postgres://localhost/mydb

# 2. Update to production
curl -X PUT http://localhost:4000/config/database_url \
  -H "Content-Type: application/json" \
  -d '{"value":"postgres://production/mydb"}'
# OK

# 3. Verify event was created (immediate)
curl http://localhost:4000/config/database_url/history | jq '.[-1]'
# Shows the new ConfigValueSet event

# 4. Restart application
# (In iex: Ctrl+C twice, then: iex -S mix)

# 5. Verify new value
curl http://localhost:4000/config/database_url
# postgres://production/mydb

# 6. Check when it changed
curl -s http://localhost:4000/config/database_url/history | \
  jq '.[].data | {timestamp, value}'

# 7. Time-travel to see old value
curl http://localhost:4000/config/database_url/at/2026-02-12T10:00:00Z
# postgres://localhost/mydb
```

---

## 🎯 Best Practices

### For Writes

1. **Verify with history endpoint**
   ```bash
   # After PUT, check event was created
   curl http://localhost:4000/config/key/history
   ```

2. **Meaningful values**
   ```bash
   # Good: Descriptive values
   {"value":"postgres://production-primary/mydb"}

   # Bad: Cryptic values
   {"value":"pg://192.168.1.1/db"}
   ```

3. **Consider event history**
   - Every write creates an event
   - Events are permanent
   - Use meaningful configuration names

### For Reads

1. **Use projection for current state**
   ```bash
   # Fast, optimized
   curl http://localhost:4000/config/key
   ```

2. **Use history for audit trail**
   ```bash
   # Complete change log
   curl http://localhost:4000/config/key/history
   ```

3. **Use time-travel for debugging**
   ```bash
   # State at specific time
   curl http://localhost:4000/config/key/at/2026-02-12T10:00:00Z
   ```

### For Monitoring

1. **Health checks**
   ```bash
   # Include in monitoring
   */5 * * * * curl -f http://localhost:4000/health || alert
   ```

2. **Log analysis**
   ```bash
   # Check audit logs
   curl http://localhost:4000/config/critical_setting/history
   ```

---

## 🔐 Security Considerations

**Current Implementation:**
- ❌ No authentication
- ❌ No authorization
- ❌ No rate limiting
- ❌ No HTTPS (use reverse proxy)

**Recommendations for Production:**

1. **Add authentication**
   - API keys
   - OAuth 2.0
   - JWT tokens

2. **Add authorization**
   - Role-based access control
   - Per-configuration permissions

3. **Use HTTPS**
   - Reverse proxy (nginx, caddy)
   - TLS certificates

4. **Rate limiting**
   - Per-IP limits
   - Per-user limits

5. **Audit logging**
   - Log all API calls
   - Log authentication attempts
   - Already have event history ✅

---

## 📚 Related Documentation

- **[CQRS Operations](cqrs-operations.md)** - Command and query examples
- **[Event History](event-history.md)** - Working with event streams
- **[Time-Travel Queries](time-travel.md)** - Point-in-time retrieval
- **[Architecture Overview](../architecture/overview.md)** - System design

---

## 🐛 Troubleshooting

### 404 Not Found after PUT

**Problem:** Wrote a value but GET returns 404

**Solution:** Restart the application
```bash
# In iex
Ctrl+C (twice)
iex -S mix

# Or in production
systemctl restart config_api
```

### 503 Service Unavailable on /health

**Problem:** One or more components down

**Check logs:**
```bash
# See what's failing
curl http://localhost:4000/health | jq '.checks'
```

**Solutions:**
- `eventstore: down` → Check PostgreSQL connection
- `projection: down` → Check EventStore initialized
- `database: error` → Check projection can query

### Invalid timestamp format

**Problem:** Time-travel query fails with 400

**Solution:** Use ISO8601 format
```bash
# Wrong
curl http://localhost:4000/config/key/at/2026-02-12

# Right
curl http://localhost:4000/config/key/at/2026-02-12T00:00:00Z
```
