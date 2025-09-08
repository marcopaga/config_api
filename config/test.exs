import Config

# Configure EventStore for testing
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore_test",
  hostname: "localhost",
  port: 5432,
  pool_size: 1

# Disable logging during tests
config :logger, level: :warning
