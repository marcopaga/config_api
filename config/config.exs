import Config

config :mnesia,
  dir: ".mnesia/#{Mix.env()}/#{node()}"

# Register EventStore with the application
config :config_api,
  event_stores: [ConfigApi.EventStore]

# EventStore configuration
config :config_api, ConfigApi.EventStore,
  serializer: ConfigApi.EventSerializer,
  username: "postgres",
  password: "postgres",
  database: "config_api_eventstore",
  hostname: "localhost",
  port: 5432,
  pool_size: 10,
  pool_overflow: 5

# Import environment-specific config
import_config "#{config_env()}.exs"
