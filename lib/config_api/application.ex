defmodule ConfigApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  # Ensure event type atoms exist for EventStore deserialization
  # These must be referenced at compile time so String.to_existing_atom works
  alias ConfigApi.Events.ConfigValueSet
  alias ConfigApi.Events.ConfigValueDeleted

  # Create the string-form atoms that EventStore.RecordedEvent.deserialize expects
  # When EventStore stores "ConfigApi.Events.ConfigValueSet", it later tries String.to_existing_atom
  @event_type_atoms [
    :"ConfigApi.Events.ConfigValueSet",
    :"ConfigApi.Events.ConfigValueDeleted"
  ]

  @impl true
  def start(_type, _args) do
    ConfigApi.DB.setup()

    # Ensure event type atoms exist before EventStore starts
    # This is critical for EventStore deserialization to work
    Code.ensure_loaded!(ConfigValueSet)
    Code.ensure_loaded!(ConfigValueDeleted)
    _ = ConfigValueSet.__info__(:module)
    _ = ConfigValueDeleted.__info__(:module)
    _ = @event_type_atoms

    Logger.info("Event modules loaded: ConfigValueSet, ConfigValueDeleted")

    # In test mode, EventStore and Projection are managed by test_helper.exs for isolation
    # In production, they must be in the supervision tree
    base_children = [
      ConfigApi.ConfigUpdateWorker,
      {Plug.Cowboy, scheme: :http, plug: ConfigApiWeb.Router, options: [port: 4000]}
    ]

    children =
      if Mix.env() == :test do
        base_children
      else
        [
          # EventStore must start first (other components depend on it)
          ConfigApi.EventStore,
          # Projection rebuilds from EventStore on startup
          ConfigApi.Projections.ConfigStateProjection
          | base_children
        ]
      end
    Logger.info("Server running on http://HOST:4000")
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConfigApi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
