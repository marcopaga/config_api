defmodule ConfigApi.ConfigStoreCQRSTest do
  use ExUnit.Case, async: false

  alias ConfigApi.ConfigStoreCQRS
  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  # Ensure event type atoms exist for deserialization
  _ = :"ConfigApi.Events.ConfigValueSet"
  _ = :"ConfigApi.Events.ConfigValueDeleted"

  # Module attribute to track projection
  @projection_name ConfigStateProjection

  # Helper to rebuild projection from events manually
  defp rebuild_projection do
    require Logger
    Logger.info("TEST: rebuild_projection called")

    # Stop and restart the projection to rebuild from events
    pid = Process.whereis(@projection_name)

    if pid do
      Logger.info("TEST: Stopping existing projection #{inspect(pid)}")
      GenServer.stop(pid, :normal)
    end

    Process.sleep(50)

    try do
      :ets.delete(:config_state_projection)
      Logger.info("TEST: Deleted ETS table")
    rescue
      ArgumentError ->
        Logger.info("TEST: ETS table didn't exist")
        :ok
    end

    Logger.info("TEST: Starting projection to rebuild")

    case ConfigStateProjection.start_link() do
      {:ok, pid} ->
        Logger.info("TEST: Projection started with pid #{inspect(pid)}")
        :ok

      {:error, {:already_started, pid}} ->
        Logger.info("TEST: Projection already started with pid #{inspect(pid)}")
        :ok
    end

    Process.sleep(200)
    Logger.info("TEST: rebuild_projection complete")
  end

  setup do
    # Reset EventStore
    :ok = ConfigApi.EventStoreCase.reset_eventstore!()

    # Stop and restart projection to rebuild from clean state
    case Process.whereis(@projection_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    Process.sleep(50)

    # Clean up ETS
    try do
      :ets.delete(:config_state_projection)
    rescue
      ArgumentError -> :ok
    end

    # Start fresh projection (may already be started by application)
    case ConfigStateProjection.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Give projection time to initialize
    Process.sleep(100)

    :ok
  end

  describe "get/1" do
    test "returns error for non-existent config" do
      assert {:error, :not_found} = ConfigStoreCQRS.get("non_existent")
    end

    test "returns value after put" do
      assert {:ok, "test_value"} = ConfigStoreCQRS.put("test_key", "test_value")

      # Rebuild projection from events
      rebuild_projection()

      assert {:ok, "test_value"} = ConfigStoreCQRS.get("test_key")
    end
  end

  describe "put/2" do
    test "stores a new configuration value" do
      assert {:ok, "secret123"} = ConfigStoreCQRS.put("api_key", "secret123")

      # Rebuild projection from events
      rebuild_projection()

      assert {:ok, "secret123"} = ConfigStoreCQRS.get("api_key")
    end

    test "updates an existing configuration value" do
      assert {:ok, "value1"} = ConfigStoreCQRS.put("key", "value1")
      rebuild_projection()

      assert {:ok, "value2"} = ConfigStoreCQRS.put("key", "value2")
      rebuild_projection()

      assert {:ok, "value2"} = ConfigStoreCQRS.get("key")
    end

    test "multiple updates preserve latest value" do
      assert {:ok, "v1"} = ConfigStoreCQRS.put("key", "v1")
      assert {:ok, "v2"} = ConfigStoreCQRS.put("key", "v2")
      assert {:ok, "v3"} = ConfigStoreCQRS.put("key", "v3")

      rebuild_projection()

      assert {:ok, "v3"} = ConfigStoreCQRS.get("key")
    end

    test "stores multiple different configs" do
      assert {:ok, "value1"} = ConfigStoreCQRS.put("key1", "value1")
      assert {:ok, "value2"} = ConfigStoreCQRS.put("key2", "value2")
      assert {:ok, "value3"} = ConfigStoreCQRS.put("key3", "value3")

      rebuild_projection()

      assert {:ok, "value1"} = ConfigStoreCQRS.get("key1")
      assert {:ok, "value2"} = ConfigStoreCQRS.get("key2")
      assert {:ok, "value3"} = ConfigStoreCQRS.get("key3")
    end
  end

  describe "delete/1" do
    test "deletes an existing config" do
      assert {:ok, "value"} = ConfigStoreCQRS.put("to_delete", "value")
      rebuild_projection()

      assert {:ok, "value"} = ConfigStoreCQRS.get("to_delete")

      assert :ok = ConfigStoreCQRS.delete("to_delete")
      rebuild_projection()

      assert {:error, :not_found} = ConfigStoreCQRS.get("to_delete")
    end

    test "returns error when deleting non-existent config" do
      assert {:error, :config_not_found} = ConfigStoreCQRS.delete("non_existent")
    end

    test "returns error when deleting already deleted config" do
      assert {:ok, "value"} = ConfigStoreCQRS.put("key", "value")
      rebuild_projection()

      assert :ok = ConfigStoreCQRS.delete("key")
      rebuild_projection()

      assert {:error, :config_already_deleted} = ConfigStoreCQRS.delete("key")
    end
  end

  describe "all/0" do
    test "returns empty list when no configs" do
      assert [] = ConfigStoreCQRS.all()
    end

    test "returns all configs" do
      ConfigStoreCQRS.put("key1", "value1")
      ConfigStoreCQRS.put("key2", "value2")
      ConfigStoreCQRS.put("key3", "value3")

      rebuild_projection()

      configs = ConfigStoreCQRS.all()
      assert length(configs) == 3

      assert %{name: "key1", value: "value1"} in configs
      assert %{name: "key2", value: "value2"} in configs
      assert %{name: "key3", value: "value3"} in configs
    end

    test "does not include deleted configs" do
      ConfigStoreCQRS.put("key1", "value1")
      ConfigStoreCQRS.put("key2", "value2")
      ConfigStoreCQRS.put("key3", "value3")
      rebuild_projection()

      ConfigStoreCQRS.delete("key2")
      rebuild_projection()

      configs = ConfigStoreCQRS.all()
      assert length(configs) == 2

      assert %{name: "key1", value: "value1"} in configs
      assert %{name: "key3", value: "value3"} in configs
      refute Enum.any?(configs, &(&1.name == "key2"))
    end
  end

  describe "get_history/1" do
    test "returns empty history for non-existent config" do
      assert {:ok, []} = ConfigStoreCQRS.get_history("non_existent")
    end

    test "returns single event for new config" do
      ConfigStoreCQRS.put("key", "value")

      assert {:ok, history} = ConfigStoreCQRS.get_history("key")
      assert length(history) == 1

      [event] = history
      assert event.event_type == "Elixir.ConfigApi.Events.ConfigValueSet"
      assert event.data.config_name == "key"
      assert event.data.value == "value"
    end

    test "returns all events for updated config" do
      ConfigStoreCQRS.put("key", "v1")
      ConfigStoreCQRS.put("key", "v2")
      ConfigStoreCQRS.put("key", "v3")

      assert {:ok, history} = ConfigStoreCQRS.get_history("key")
      assert length(history) == 3

      values = Enum.map(history, & &1.data.value)
      assert values == ["v1", "v2", "v3"]
    end

    test "includes delete events" do
      ConfigStoreCQRS.put("key", "value")
      ConfigStoreCQRS.delete("key")

      assert {:ok, history} = ConfigStoreCQRS.get_history("key")
      assert length(history) == 2

      [set_event, delete_event] = history
      assert set_event.event_type == "Elixir.ConfigApi.Events.ConfigValueSet"
      assert delete_event.event_type == "Elixir.ConfigApi.Events.ConfigValueDeleted"
    end
  end

  describe "get_at_timestamp/2" do
    test "returns error for config that didn't exist at timestamp" do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      ConfigStoreCQRS.put("key", "value")

      assert {:error, :not_found} = ConfigStoreCQRS.get_at_timestamp("key", past)
    end

    test "returns value at specific timestamp" do
      ConfigStoreCQRS.put("key", "v1")
      Process.sleep(100)

      timestamp_after_v1 = DateTime.utc_now()
      Process.sleep(100)

      ConfigStoreCQRS.put("key", "v2")
      Process.sleep(100)

      ConfigStoreCQRS.put("key", "v3")

      # At timestamp_after_v1, value should be v1
      assert {:ok, "v1"} = ConfigStoreCQRS.get_at_timestamp("key", timestamp_after_v1)
    end

    test "returns not_found if deleted before timestamp" do
      ConfigStoreCQRS.put("key", "value")
      Process.sleep(100)

      ConfigStoreCQRS.delete("key")
      Process.sleep(100)

      timestamp_after_delete = DateTime.utc_now()

      assert {:error, :not_found} = ConfigStoreCQRS.get_at_timestamp("key", timestamp_after_delete)
    end
  end

  describe "event sourcing workflow" do
    test "complete CQRS flow: write → event → projection → read" do
      # Write (command)
      assert {:ok, "secret"} = ConfigStoreCQRS.put("api_key", "secret")

      # Event is in EventStore
      assert {:ok, history} = ConfigStoreCQRS.get_history("api_key")
      assert length(history) == 1

      # Rebuild projection from events
      rebuild_projection()

      # Read from projection
      assert {:ok, "secret"} = ConfigStoreCQRS.get("api_key")
    end

    test "projection rebuilds correctly after restart" do
      # Add some configs
      ConfigStoreCQRS.put("key1", "value1")
      ConfigStoreCQRS.put("key2", "value2")

      # Rebuild projection from events
      rebuild_projection()

      # Data should be there
      assert {:ok, "value1"} = ConfigStoreCQRS.get("key1")
      assert {:ok, "value2"} = ConfigStoreCQRS.get("key2")
    end

    test "handles resurrection (delete then recreate)" do
      ConfigStoreCQRS.put("key", "original")
      rebuild_projection()

      ConfigStoreCQRS.delete("key")
      rebuild_projection()

      ConfigStoreCQRS.put("key", "resurrected")
      rebuild_projection()

      assert {:ok, "resurrected"} = ConfigStoreCQRS.get("key")
    end
  end
end
