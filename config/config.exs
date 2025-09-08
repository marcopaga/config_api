import Config

# EventStore configuration
config :config_api, ConfigApi.EventStore,
  serializer: EventStore.JsonSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  pool_size: 10,
  pool_overflow: 5

# Configure the event stores
config :config_api, event_stores: [ConfigApi.EventStore]

# Logger configuration
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Environment specific configuration
import_config "#{config_env()}.exs"
