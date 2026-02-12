defmodule ConfigApiWeb.Router do
  @moduledoc """
  HTTP API router for configuration management.

  Uses CQRS implementation (ConfigStoreCQRS) for all operations.
  """

  use Plug.Router
  require Logger

  alias ConfigApi.ConfigStoreCQRS

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  # Standard CRUD endpoints (migrated to CQRS)

  @doc """
  GET /config - List all configurations
  Returns JSON array of {name, value} objects
  """
  get "/config" do
    configs = ConfigStoreCQRS.all()
    send_resp(conn, 200, Jason.encode!(configs))
  end

  @doc """
  GET /config/:name - Get a specific configuration value
  Returns plain text value or 404
  """
  get "/config/:name" do
    case ConfigStoreCQRS.get(name) do
      {:ok, value} ->
        send_resp(conn, 200, "#{value}")

      {:error, :not_found} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  @doc """
  PUT /config/:name - Set a configuration value
  Expects JSON body: {"value": "..."}
  """
  put "/config/:name" do
    value = conn.body_params["value"]

    case ConfigStoreCQRS.put(name, value) do
      {:ok, _value} ->
        send_resp(conn, 200, "OK")

      {:error, reason} ->
        Logger.error("Failed to put config #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  @doc """
  DELETE /config/:name - Delete a configuration
  """
  delete "/config/:name" do
    case ConfigStoreCQRS.delete(name) do
      :ok ->
        send_resp(conn, 200, "OK")

      {:error, :config_not_found} ->
        send_resp(conn, 404, "Not Found")

      {:error, :config_already_deleted} ->
        send_resp(conn, 410, "Gone")

      {:error, reason} ->
        Logger.error("Failed to delete config #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # CQRS-specific endpoints (new functionality)

  @doc """
  GET /config/:name/history - Get complete event history for a configuration
  Returns JSON array of events with timestamps and metadata
  """
  get "/config/:name/history" do
    case ConfigStoreCQRS.get_history(name) do
      {:ok, history} ->
        send_resp(conn, 200, Jason.encode!(history))

      {:error, reason} ->
        Logger.error("Failed to get history for #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  @doc """
  GET /config/:name/at/:timestamp - Get configuration value at a specific point in time
  Timestamp format: ISO8601 (e.g., 2024-01-15T10:30:00Z)
  Returns plain text value or 404
  """
  get "/config/:name/at/:timestamp" do
    case parse_timestamp(timestamp) do
      {:ok, datetime} ->
        case ConfigStoreCQRS.get_at_timestamp(name, datetime) do
          {:ok, value} ->
            send_resp(conn, 200, "#{value}")

          {:error, :not_found} ->
            send_resp(conn, 404, "Not Found")

          {:error, reason} ->
            Logger.error("Failed to get #{name} at timestamp: #{inspect(reason)}")
            send_resp(conn, 500, "Internal Server Error")
        end

      {:error, _reason} ->
        send_resp(conn, 400, "Invalid timestamp format. Use ISO8601 (e.g., 2024-01-15T10:30:00Z)")
    end
  end

  # Catch-all for undefined routes
  match _ do
    send_resp(conn, 404, "Not Found")
  end

  ## Private Helpers

  defp parse_timestamp(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end
end
