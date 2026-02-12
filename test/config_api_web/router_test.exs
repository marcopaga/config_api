defmodule ConfigApiWeb.RouterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias ConfigApiWeb.Router
  alias ConfigApi.ConfigStoreCQRS

  @opts Router.init([])
  @projection_name ConfigApi.Projections.ConfigStateProjection

  # Helper to rebuild projection from events
  defp rebuild_projection do
    pid = Process.whereis(@projection_name)
    if pid, do: GenServer.stop(pid, :normal)
    Process.sleep(50)

    try do
      :ets.delete(:config_state_projection)
    rescue
      ArgumentError -> :ok
    end

    case ConfigApi.Projections.ConfigStateProjection.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    Process.sleep(200)
  end

  setup do
    # Reset EventStore
    :ok = ConfigApi.EventStoreCase.reset_eventstore!()

    # Stop and restart projection for clean state
    case Process.whereis(ConfigApi.Projections.ConfigStateProjection) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    Process.sleep(50)

    try do
      :ets.delete(:config_state_projection)
    rescue
      ArgumentError -> :ok
    end

    # Start fresh projection
    case ConfigApi.Projections.ConfigStateProjection.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Process.sleep(100)

    :ok
  end

  describe "GET /config" do
    test "returns empty list when no configs" do
      conn = conn(:get, "/config")
      conn = Router.call(conn, @opts)

      assert conn.state == :sent
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == []
    end

    test "returns all configs as JSON" do
      ConfigStoreCQRS.put("key1", "value1")
      ConfigStoreCQRS.put("key2", "value2")
      ConfigStoreCQRS.put("key3", "value3")
      rebuild_projection()

      conn = conn(:get, "/config")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      configs = Jason.decode!(conn.resp_body, keys: :atoms)
      assert length(configs) == 3
      assert %{name: "key1", value: "value1"} in configs
      assert %{name: "key2", value: "value2"} in configs
      assert %{name: "key3", value: "value3"} in configs
    end
  end

  describe "GET /config/:name" do
    test "returns 404 for non-existent config" do
      conn = conn(:get, "/config/nonexistent")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end

    test "returns value for existing config" do
      ConfigStoreCQRS.put("test_key", "test_value")
      rebuild_projection()

      conn = conn(:get, "/config/test_key")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body == "test_value"
    end
  end

  describe "PUT /config/:name" do
    test "creates a new config" do
      conn =
        conn(:put, "/config/new_key", Jason.encode!(%{value: "new_value"}))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body == "OK"

      # Verify it was created
      rebuild_projection()
      assert {:ok, "new_value"} = ConfigStoreCQRS.get("new_key")
    end

    test "updates an existing config" do
      ConfigStoreCQRS.put("existing", "old_value")
      rebuild_projection()

      conn =
        conn(:put, "/config/existing", Jason.encode!(%{value: "new_value"}))
        |> put_req_header("content-type", "application/json")

      conn = Router.call(conn, @opts)

      assert conn.status == 200

      rebuild_projection()
      assert {:ok, "new_value"} = ConfigStoreCQRS.get("existing")
    end
  end

  describe "DELETE /config/:name" do
    test "deletes an existing config" do
      ConfigStoreCQRS.put("to_delete", "value")
      rebuild_projection()

      conn = conn(:delete, "/config/to_delete")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body == "OK"

      rebuild_projection()
      assert {:error, :not_found} = ConfigStoreCQRS.get("to_delete")
    end

    test "returns 404 for non-existent config" do
      conn = conn(:delete, "/config/nonexistent")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
    end

    test "returns 410 Gone for already deleted config" do
      ConfigStoreCQRS.put("key", "value")
      rebuild_projection()

      ConfigStoreCQRS.delete("key")
      rebuild_projection()

      conn = conn(:delete, "/config/key")
      conn = Router.call(conn, @opts)

      assert conn.status == 410
    end
  end

  describe "GET /config/:name/history" do
    test "returns empty array for non-existent config" do
      conn = conn(:get, "/config/nonexistent/history")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == []
    end

    test "returns event history for a config" do
      ConfigStoreCQRS.put("tracked", "v1")
      ConfigStoreCQRS.put("tracked", "v2")
      ConfigStoreCQRS.put("tracked", "v3")

      conn = conn(:get, "/config/tracked/history")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      history = Jason.decode!(conn.resp_body, keys: :atoms)
      assert length(history) == 3

      values = Enum.map(history, & &1.data.value)
      assert values == ["v1", "v2", "v3"]
    end

    test "includes delete events in history" do
      ConfigStoreCQRS.put("key", "value")
      ConfigStoreCQRS.delete("key")

      conn = conn(:get, "/config/key/history")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      history = Jason.decode!(conn.resp_body, keys: :atoms)
      assert length(history) == 2

      event_types = Enum.map(history, & &1.event_type)
      assert "Elixir.ConfigApi.Events.ConfigValueSet" in event_types
      assert "Elixir.ConfigApi.Events.ConfigValueDeleted" in event_types
    end
  end

  describe "GET /config/:name/at/:timestamp" do
    test "returns 400 for invalid timestamp format" do
      conn = conn(:get, "/config/key/at/invalid-timestamp")
      conn = Router.call(conn, @opts)

      assert conn.status == 400
      assert conn.resp_body =~ "Invalid timestamp format"
    end

    test "returns 404 for config that didn't exist at timestamp" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.to_iso8601()

      ConfigStoreCQRS.put("key", "value")

      conn = conn(:get, "/config/key/at/#{past}")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
    end

    test "returns value at specific timestamp" do
      ConfigStoreCQRS.put("key", "v1")
      Process.sleep(200)

      timestamp_after_v1 = DateTime.utc_now() |> DateTime.to_iso8601()
      Process.sleep(200)

      ConfigStoreCQRS.put("key", "v2")
      ConfigStoreCQRS.put("key", "v3")

      conn = conn(:get, "/config/key/at/#{timestamp_after_v1}")
      conn = Router.call(conn, @opts)

      assert conn.status == 200
      assert conn.resp_body == "v1"
    end
  end

  describe "undefined routes" do
    test "returns 404 for undefined route" do
      conn = conn(:get, "/undefined/route")
      conn = Router.call(conn, @opts)

      assert conn.status == 404
      assert conn.resp_body == "Not Found"
    end
  end
end
