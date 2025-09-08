defmodule ConfigApiWeb.Router do
  use Plug.Router
  require Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  put "/config/:name" do
    value = conn.body_params["value"]
    Logger.info("PUT /config/#{name} - Setting value: #{inspect(value)}")

    case ConfigApi.ConfigStore.put(name, value) do
      {:ok, stored_value} ->
        Logger.info("PUT /config/#{name} - Successfully stored value: #{inspect(stored_value)}")
        send_resp(conn, 200, "OK")

      {:error, reason} ->
        Logger.error("PUT /config/#{name} - Failed to store value: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  get "/config/:name" do
    Logger.debug("GET /config/#{name} - Retrieving value")

    case ConfigApi.ConfigStore.get(name) do
      {:ok, value} ->
        Logger.debug("GET /config/#{name} - Found value: #{inspect(value)}")
        send_resp(conn, 200, "#{value}")

      {:error, :not_found} ->
        Logger.debug("GET /config/#{name} - Value not found")
        send_resp(conn, 404, "Not Found")

      {:error, reason} ->
        Logger.error("GET /config/#{name} - Error retrieving value: #{inspect(reason)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end

  get "/config" do
    Logger.debug("GET /config - Retrieving all configurations")

    try do
      values = ConfigApi.ConfigStore.all()
      Logger.debug("GET /config - Found #{length(values)} configurations")
      send_resp(conn, 200, Jason.encode!(values))
    rescue
      error ->
        Logger.error("GET /config - Exception retrieving configurations: #{inspect(error)}")
        send_resp(conn, 500, "Internal Server Error")
    end
  end


end
