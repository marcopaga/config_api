defmodule ConfigApi.EventStore do
  use EventStore, otp_app: :config_api, adapter: EventStore.Adapters.Postgres

  # Custom event store configuration
  def init(config) do
    config = config
    |> Keyword.put(:username, System.get_env("DB_USERNAME", "postgres"))
    |> Keyword.put(:password, System.get_env("DB_PASSWORD", "postgres"))
    |> Keyword.put(:database, System.get_env("DB_NAME", "config_api_eventstore"))
    |> Keyword.put(:hostname, System.get_env("DB_HOST", "localhost"))
    |> Keyword.put(:port, System.get_env("DB_PORT", "5432") |> String.to_integer())

    {:ok, config}
  end
end
