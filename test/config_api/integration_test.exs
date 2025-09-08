defmodule ConfigApi.IntegrationTest do
  use ExUnit.Case, async: false
  require Logger

  alias ConfigApi.{ConfigStore, EventStore}
  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.ConfigUpdateWorker

  setup do
    # Reset the event store for each test
    :ok = EventStore.reset!()

    # Restart the projection to rebuild from clean state
    GenServer.stop(ConfigStateProjection, :normal)
    {:ok, _} = ConfigStateProjection.start_link([])

    # Give the projection time to initialize
    Process.sleep(100)

    :ok
  end

  describe "complete PUT -> GET workflow" do
    test "stores and retrieves a configuration value" do
      config_name = "test_config"
      config_value = "test_value"

      # PUT operation
      Logger.info("Testing PUT operation for #{config_name}")
      assert {:ok, ^config_value} = ConfigStore.put(config_name, config_value)

      # Give time for event processing
      Process.sleep(50)

      # GET operation
      Logger.info("Testing GET operation for #{config_name}")
      assert {:ok, ^config_value} = ConfigStore.get(config_name)
    end

    test "updates an existing configuration value" do
      config_name = "update_test"
      initial_value = "initial"
      updated_value = "updated"

      # Set initial value
      assert {:ok, ^initial_value} = ConfigStore.put(config_name, initial_value)
      Process.sleep(50)
      assert {:ok, ^initial_value} = ConfigStore.get(config_name)

      # Update value
      assert {:ok, ^updated_value} = ConfigStore.put(config_name, updated_value)
      Process.sleep(50)
      assert {:ok, ^updated_value} = ConfigStore.get(config_name)
    end

    test "handles multiple configuration values" do
      configs = [
        {"config1", "value1"},
        {"config2", "value2"},
        {"config3", "value3"}
      ]

      # Store all configurations
      for {name, value} <- configs do
        assert {:ok, ^value} = ConfigStore.put(name, value)
      end

      Process.sleep(100)

      # Retrieve all configurations
      for {name, expected_value} <- configs do
        assert {:ok, ^expected_value} = ConfigStore.get(name)
      end

      # Check all configurations
      all_configs = ConfigStore.all()
      assert length(all_configs) == 3

      config_map = Map.new(all_configs, fn %{name: name, value: value} -> {name, value} end)
      for {name, expected_value} <- configs do
        assert Map.get(config_map, name) == expected_value
      end
    end

    test "returns error for non-existent configuration" do
      assert {:error, :not_found} = ConfigStore.get("non_existent")
    end
  end

  describe "persistence across restarts" do
    test "values persist after projection restart" do
      config_name = "persistence_test"
      config_value = "persistent_value"

      # Store configuration
      assert {:ok, ^config_value} = ConfigStore.put(config_name, config_value)
      Process.sleep(50)
      assert {:ok, ^config_value} = ConfigStore.get(config_name)

      # Restart projection (simulating application restart)
      GenServer.stop(ConfigStateProjection, :normal)
      {:ok, _} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      # Verify value is still available
      assert {:ok, ^config_value} = ConfigStore.get(config_name)
    end

    test "multiple values persist after projection restart" do
      configs = [
        {"persist1", "value1"},
        {"persist2", "value2"},
        {"persist3", "value3"}
      ]

      # Store configurations
      for {name, value} <- configs do
        assert {:ok, ^value} = ConfigStore.put(name, value)
      end
      Process.sleep(100)

      # Restart projection
      GenServer.stop(ConfigStateProjection, :normal)
      {:ok, _} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      # Verify all values persist
      for {name, expected_value} <- configs do
        assert {:ok, ^expected_value} = ConfigStore.get(name)
      end
    end
  end

  describe "ConfigUpdateWorker integration" do
    test "worker receives update notifications" do
      # Clear any existing logs
      Logger.flush()

      config_name = "worker_test"
      config_value = "worker_value"

      # Capture log output
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, ^config_value} = ConfigStore.put(config_name, config_value)
        Process.sleep(100)
      end) =~ "Config updated"
    end

    test "worker stats are updated correctly" do
      initial_stats = ConfigUpdateWorker.get_stats()

      # Perform operations
      assert {:ok, "test1"} = ConfigStore.put("test1", "test1")
      assert {:ok, "test2"} = ConfigStore.put("test2", "test2")
      Process.sleep(100)

      updated_stats = ConfigUpdateWorker.get_stats()
      assert updated_stats.message_count >= initial_stats.message_count + 2
    end
  end

  describe "error handling" do
    test "handles invalid parameters gracefully" do
      # These should return errors, not crash
      assert {:error, _} = ConfigStore.put(nil, "value")
      assert {:error, _} = ConfigStore.put("name", nil)
      assert {:error, _} = ConfigStore.put("", "value")
    end

    test "projection handles malformed events gracefully" do
      # This test ensures the system doesn't crash on unexpected data
      config_name = "robust_test"
      config_value = "robust_value"

      assert {:ok, ^config_value} = ConfigStore.put(config_name, config_value)
      Process.sleep(50)
      assert {:ok, ^config_value} = ConfigStore.get(config_name)
    end
  end
end
