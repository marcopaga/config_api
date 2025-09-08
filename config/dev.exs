import Config

# Configure EventStore for development
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  port: 5432,
  pool_size: 10,
  pool_overflow: 5

# Enable debug logging in development
config :logger, level: :debug
