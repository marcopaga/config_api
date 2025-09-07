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
    ConfigApi.ConfigStore.put(name, value)
    send_resp(conn, 200, "OK")
  end


  get "/config/:name" do
    case ConfigApi.ConfigStore.get(name) do
      {:ok, value} ->
        send_resp(conn, 200, "#{value}")
      {:error, :not_found} ->
        send_resp(conn, 404, "Not Found")
      end
  end

  get "/config" do
    values = ConfigApi.ConfigStore.all()
    send_resp(conn, 200, Jason.encode!(values))
  end


end
