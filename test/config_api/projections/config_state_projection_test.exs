defmodule ConfigApi.Projections.ConfigStateProjectionTest do
  use ExUnit.Case, async: false

  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  # Stop the application's projection if running
  setup do
    # Stop the application's projection to avoid conflicts
    case Process.whereis(ConfigStateProjection) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    # Give it time to stop
    Process.sleep(50)

    # Clean up ETS table if it exists
    try do
      :ets.delete(:config_state_projection)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the projection GenServer" do
      {:ok, pid} = ConfigStateProjection.start_link()

      assert Process.alive?(pid)
      assert Process.whereis(ConfigStateProjection) == pid

      GenServer.stop(pid)
    end

    test "creates ETS table" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # ETS table should exist
      assert :ets.info(:config_state_projection) != :undefined

      GenServer.stop(pid)
    end
  end

  describe "get_config/1" do
    test "returns error for non-existent config" do
      {:ok, pid} = ConfigStateProjection.start_link()

      assert {:error, :not_found} = ConfigStateProjection.get_config("non_existent")

      GenServer.stop(pid)
    end

    test "returns value for existing config" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Manually insert into ETS for testing
      :ets.insert(:config_state_projection, {"test_key", "test_value"})

      assert {:ok, "test_value"} = ConfigStateProjection.get_config("test_key")

      GenServer.stop(pid)
    end
  end

  describe "get_all_configs/0" do
    test "returns empty list when no configs" do
      {:ok, pid} = ConfigStateProjection.start_link()

      assert [] = ConfigStateProjection.get_all_configs()

      GenServer.stop(pid)
    end

    test "returns all configs as list of maps" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Manually insert test data
      :ets.insert(:config_state_projection, {"key1", "value1"})
      :ets.insert(:config_state_projection, {"key2", "value2"})
      :ets.insert(:config_state_projection, {"key3", "value3"})

      configs = ConfigStateProjection.get_all_configs()

      assert length(configs) == 3
      assert %{name: "key1", value: "value1"} in configs
      assert %{name: "key2", value: "value2"} in configs
      assert %{name: "key3", value: "value3"} in configs

      GenServer.stop(pid)
    end
  end

  describe "event handling" do
    test "handles ConfigValueSet event" do
      {:ok, pid} = ConfigStateProjection.start_link()

      event = ConfigValueSet.new("new_key", "new_value")

      # Send event directly to test event handling
      send(pid, {:events, [event]})

      # Give it time to process
      Process.sleep(50)

      assert {:ok, "new_value"} = ConfigStateProjection.get_config("new_key")

      GenServer.stop(pid)
    end

    test "handles ConfigValueSet update" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Insert initial value
      event1 = ConfigValueSet.new("key", "value1")
      send(pid, {:events, [event1]})
      Process.sleep(50)

      assert {:ok, "value1"} = ConfigStateProjection.get_config("key")

      # Update value
      event2 = ConfigValueSet.new("key", "value2", "value1")
      send(pid, {:events, [event2]})
      Process.sleep(50)

      assert {:ok, "value2"} = ConfigStateProjection.get_config("key")

      GenServer.stop(pid)
    end

    test "handles ConfigValueDeleted event" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Insert initial value
      :ets.insert(:config_state_projection, {"to_delete", "value"})
      assert {:ok, "value"} = ConfigStateProjection.get_config("to_delete")

      # Delete it
      event = ConfigValueDeleted.new("to_delete", "value")
      send(pid, {:events, [event]})
      Process.sleep(50)

      assert {:error, :not_found} = ConfigStateProjection.get_config("to_delete")

      GenServer.stop(pid)
    end

    test "handles multiple events in batch" do
      {:ok, pid} = ConfigStateProjection.start_link()

      events = [
        ConfigValueSet.new("key1", "value1"),
        ConfigValueSet.new("key2", "value2"),
        ConfigValueSet.new("key3", "value3")
      ]

      send(pid, {:events, events})
      Process.sleep(50)

      assert {:ok, "value1"} = ConfigStateProjection.get_config("key1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("key2")
      assert {:ok, "value3"} = ConfigStateProjection.get_config("key3")

      GenServer.stop(pid)
    end

    test "handles mixed set and delete events" do
      {:ok, pid} = ConfigStateProjection.start_link()

      events = [
        ConfigValueSet.new("key1", "value1"),
        ConfigValueSet.new("key2", "value2"),
        ConfigValueDeleted.new("key1", "value1"),
        ConfigValueSet.new("key3", "value3")
      ]

      send(pid, {:events, events})
      Process.sleep(100)

      assert {:error, :not_found} = ConfigStateProjection.get_config("key1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("key2")
      assert {:ok, "value3"} = ConfigStateProjection.get_config("key3")

      GenServer.stop(pid)
    end
  end

  describe "state persistence across restarts" do
    test "rebuilds state from EventStore on startup" do
      # This test verifies the concept - actual EventStore integration
      # will be tested in integration tests
      {:ok, pid} = ConfigStateProjection.start_link()

      # Initially empty (no events in EventStore for this test)
      assert [] = ConfigStateProjection.get_all_configs()

      GenServer.stop(pid)
    end
  end

  describe "concurrent reads" do
    test "handles concurrent read requests" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Insert test data
      :ets.insert(:config_state_projection, {"concurrent_key", "concurrent_value"})

      # Spawn multiple readers
      tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            ConfigStateProjection.get_config("concurrent_key")
          end)
        end

      # All should succeed
      results = Task.await_many(tasks)
      assert Enum.all?(results, &(&1 == {:ok, "concurrent_value"}))

      GenServer.stop(pid)
    end
  end

  describe "message handling" do
    test "handles subscribed message" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Send subscription confirmation
      send(pid, {:subscribed, :fake_subscription})

      Process.sleep(50)

      # Should still be alive and working
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "handles unexpected messages gracefully" do
      {:ok, pid} = ConfigStateProjection.start_link()

      # Send unexpected message
      send(pid, {:unexpected, "message"})

      Process.sleep(50)

      # Should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
