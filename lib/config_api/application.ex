defmodule ConfigApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    ConfigApi.DB.setup()

    children = [
      ConfigApi.ConfigUpdateWorker,
      {Plug.Cowboy, scheme: :http, plug: ConfigApiWeb.Router, options: [port: 4000]}
    ]
    Logger.info("Server running on http://HOST:4000")
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ConfigApi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
