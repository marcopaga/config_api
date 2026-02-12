defmodule ConfigApiWeb.Router do
  @moduledoc """
  HTTP API router for configuration management.

  Uses CQRS implementation (ConfigStoreCQRS) for all operations.

  ## API Versioning

  This API uses URL path versioning with the `/v1` prefix:
  - **Current version**: v1
  - **Versioned routes**: All routes under `/v1/*`
  - **Backward compatibility**: Unversioned routes (e.g., `/config`) are maintained temporarily
    for backward compatibility but will be removed in a future major version

  ### Versioning Strategy

  - **Major versions** (v1, v2) indicate breaking changes
  - **Minor changes** are handled within the same version
  - **Deprecation**: Unversioned routes will be deprecated in v2.0
  - **Migration path**: Update clients to use `/v1/*` routes as soon as possible

  ### Examples

  ```
  # Versioned (recommended)
  GET /v1/config
  GET /v1/config/api_key
  PUT /v1/config/api_key

  # Unversioned (deprecated, backward compatibility only)
  GET /config
  GET /config/api_key
  ```
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

  ## API v1 Routes (recommended)

  # GET /v1/health - Health check endpoint
  get "/v1/health" do
    health_status = check_health()

    case health_status do
      {:ok, status} ->
        send_resp(conn, 200, Jason.encode!(status))

      {:error, status} ->
        send_resp(conn, 503, Jason.encode!(status))
    end
  end

  # GET /v1/config - List all configurations
  # Returns JSON array of {name, value} objects
  get "/v1/config" do
    configs = ConfigStoreCQRS.all()
    send_resp(conn, 200, Jason.encode!(configs))
  end

  # GET /v1/config/:name - Get a specific configuration value
  # Returns plain text value or 404
  get "/v1/config/:name" do
    case ConfigStoreCQRS.get(name) do
      {:ok, value} ->
        send_resp(conn, 200, "#{value}")

      {:error, :not_found} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # PUT /v1/config/:name - Set a configuration value
  # Expects JSON body: {"value": "..."}
  put "/v1/config/:name" do
    value = conn.body_params["value"]

    case ConfigStoreCQRS.put(name, value) do
      {:ok, _value} ->
        send_resp(conn, 200, "OK")

      {:error, reason} ->
        Logger.error("Failed to put config #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # DELETE /v1/config/:name - Delete a configuration
  delete "/v1/config/:name" do
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

  # GET /v1/config/:name/history - Get complete event history for a configuration
  # Returns JSON array of events with timestamps and metadata
  get "/v1/config/:name/history" do
    case ConfigStoreCQRS.get_history(name) do
      {:ok, history} ->
        send_resp(conn, 200, Jason.encode!(history))

      {:error, reason} ->
        Logger.error("Failed to get history for #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # GET /v1/config/:name/at/:timestamp - Get configuration value at a specific point in time
  # Timestamp format: ISO8601 (e.g., 2024-01-15T10:30:00Z)
  # Returns plain text value or 404
  get "/v1/config/:name/at/:timestamp" do
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

  ## Backward Compatibility Routes (deprecated)
  ## These routes are maintained for backward compatibility but will be removed in v2.0
  ## Clients should migrate to /v1/* routes as soon as possible

  # GET /health - Health check endpoint (deprecated, use /v1/health)
  get "/health" do
    health_status = check_health()

    case health_status do
      {:ok, status} ->
        send_resp(conn, 200, Jason.encode!(status))

      {:error, status} ->
        send_resp(conn, 503, Jason.encode!(status))
    end
  end

  # GET /config - List all configurations (deprecated, use /v1/config)
  get "/config" do
    configs = ConfigStoreCQRS.all()
    send_resp(conn, 200, Jason.encode!(configs))
  end

  # GET /config/:name - Get a specific configuration value (deprecated, use /v1/config/:name)
  get "/config/:name" do
    case ConfigStoreCQRS.get(name) do
      {:ok, value} ->
        send_resp(conn, 200, "#{value}")

      {:error, :not_found} ->
        send_resp(conn, 404, "Not Found")
    end
  end

  # PUT /config/:name - Set a configuration value (deprecated, use /v1/config/:name)
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

  # DELETE /config/:name - Delete a configuration (deprecated, use /v1/config/:name)
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

  # GET /config/:name/history - Get event history (deprecated, use /v1/config/:name/history)
  get "/config/:name/history" do
    case ConfigStoreCQRS.get_history(name) do
      {:ok, history} ->
        send_resp(conn, 200, Jason.encode!(history))

      {:error, reason} ->
        Logger.error("Failed to get history for #{name}: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  # GET /config/:name/at/:timestamp - Time-travel query (deprecated, use /v1/config/:name/at/:timestamp)
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

  defp check_health do
    checks = %{
      eventstore: check_eventstore(),
      projection: check_projection(),
      database: check_database()
    }

    all_healthy = Enum.all?(checks, fn {_key, status} -> status == :ok end)

    status = %{
      status: if(all_healthy, do: "healthy", else: "unhealthy"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: checks
    }

    if all_healthy do
      {:ok, status}
    else
      {:error, status}
    end
  end

  defp check_eventstore do
    case Process.whereis(ConfigApi.EventStore) do
      nil -> :down
      pid when is_pid(pid) -> :ok
    end
  end

  defp check_projection do
    case Process.whereis(ConfigApi.Projections.ConfigStateProjection) do
      nil -> :down
      pid when is_pid(pid) -> :ok
    end
  end

  defp check_database do
    # Try to get all configs - if this works, the projection is functional
    try do
      _configs = ConfigStoreCQRS.all()
      :ok
    rescue
      _ -> :error
    end
  end
end
