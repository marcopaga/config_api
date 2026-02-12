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
