defmodule ConfigApi.Projections.ConfigStateProjectionUnitTest do
  @moduledoc """
  Unit tests for ConfigStateProjection event application logic.

  These tests focus on the projection's event handling WITHOUT EventStore dependency.
  They run fast (async: true) and don't require database setup.
  """
  use ExUnit.Case, async: true

  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  @table_name :config_state_projection

  setup do
    # Create ETS table for this test process
    # Each async test gets its own process, so we need unique table names
    table_name = :"config_state_projection_#{:erlang.unique_integer([:positive])}"

    table = :ets.new(table_name, [:set, :public, read_concurrency: true])

    on_exit(fn ->
      try do
        :ets.delete(table_name)
      rescue
        ArgumentError -> :ok
      end
    end)

    {:ok, table: table, table_name: table_name}
  end

  describe "apply_event_immediately/1 for ConfigValueSet" do
    test "applies ConfigValueSet event to ETS table" do
      # Wait for projection to start if not already running
      ensure_projection_started()

      event = %ConfigValueSet{config_name: "test_key", value: "test_value"}

      assert :ok = ConfigStateProjection.apply_event_immediately(event)

      # Verify it was written to ETS
      assert {:ok, "test_value"} = ConfigStateProjection.get_config("test_key")
    end

    test "updates existing value with ConfigValueSet" do
      ensure_projection_started()

      # Set initial value
      event1 = %ConfigValueSet{config_name: "key", value: "value1"}
      ConfigStateProjection.apply_event_immediately(event1)

      # Update value
      event2 = %ConfigValueSet{config_name: "key", value: "value2"}
      ConfigStateProjection.apply_event_immediately(event2)

      assert {:ok, "value2"} = ConfigStateProjection.get_config("key")
    end

    test "handles multiple different keys" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key1", value: "value1"},
        %ConfigValueSet{config_name: "key2", value: "value2"},
        %ConfigValueSet{config_name: "key3", value: "value3"}
      ]

      Enum.each(events, &ConfigStateProjection.apply_event_immediately/1)

      assert {:ok, "value1"} = ConfigStateProjection.get_config("key1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("key2")
      assert {:ok, "value3"} = ConfigStateProjection.get_config("key3")
    end

    test "handles empty string as value" do
      ensure_projection_started()

      event = %ConfigValueSet{config_name: "empty_key", value: ""}
      ConfigStateProjection.apply_event_immediately(event)

      assert {:ok, ""} = ConfigStateProjection.get_config("empty_key")
    end

    test "handles unicode in value" do
      ensure_projection_started()

      event = %ConfigValueSet{config_name: "unicode_key", value: "Hello 世界 🌍"}
      ConfigStateProjection.apply_event_immediately(event)

      assert {:ok, "Hello 世界 🌍"} = ConfigStateProjection.get_config("unicode_key")
    end

    test "handles very long values" do
      ensure_projection_started()

      long_value = String.duplicate("a", 10_000)
      event = %ConfigValueSet{config_name: "long_value_key", value: long_value}
      ConfigStateProjection.apply_event_immediately(event)

      assert {:ok, ^long_value} = ConfigStateProjection.get_config("long_value_key")
    end
  end

  describe "apply_event_immediately/1 for ConfigValueDeleted" do
    test "deletes existing key from ETS" do
      ensure_projection_started()

      # First set a value
      set_event = %ConfigValueSet{config_name: "to_delete", value: "will_be_deleted"}
      ConfigStateProjection.apply_event_immediately(set_event)

      assert {:ok, "will_be_deleted"} = ConfigStateProjection.get_config("to_delete")

      # Now delete it
      delete_event = %ConfigValueDeleted{config_name: "to_delete"}
      ConfigStateProjection.apply_event_immediately(delete_event)

      assert {:error, :not_found} = ConfigStateProjection.get_config("to_delete")
    end

    test "deleting non-existent key is idempotent" do
      ensure_projection_started()

      delete_event = %ConfigValueDeleted{config_name: "never_existed"}

      # Should not raise error
      assert :ok = ConfigStateProjection.apply_event_immediately(delete_event)

      assert {:error, :not_found} = ConfigStateProjection.get_config("never_existed")
    end

    test "deleting same key twice is idempotent" do
      ensure_projection_started()

      # Set and delete
      set_event = %ConfigValueSet{config_name: "key", value: "value"}
      ConfigStateProjection.apply_event_immediately(set_event)

      delete_event = %ConfigValueDeleted{config_name: "key"}
      ConfigStateProjection.apply_event_immediately(delete_event)

      # Delete again (should be fine)
      ConfigStateProjection.apply_event_immediately(delete_event)

      assert {:error, :not_found} = ConfigStateProjection.get_config("key")
    end
  end

  describe "rebuild_from_event_list/1" do
    test "rebuilds state from list of events" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key1", value: "value1"},
        %ConfigValueSet{config_name: "key2", value: "value2"},
        %ConfigValueSet{config_name: "key3", value: "value3"}
      ]

      assert :ok = ConfigStateProjection.rebuild_from_event_list(events)

      assert {:ok, "value1"} = ConfigStateProjection.get_config("key1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("key2")
      assert {:ok, "value3"} = ConfigStateProjection.get_config("key3")
    end

    test "handles set and delete events" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key1", value: "value1"},
        %ConfigValueSet{config_name: "key2", value: "value2"},
        %ConfigValueDeleted{config_name: "key1"}
      ]

      ConfigStateProjection.rebuild_from_event_list(events)

      assert {:error, :not_found} = ConfigStateProjection.get_config("key1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("key2")
    end

    test "handles updates to same key" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key", value: "v1"},
        %ConfigValueSet{config_name: "key", value: "v2"},
        %ConfigValueSet{config_name: "key", value: "v3"}
      ]

      ConfigStateProjection.rebuild_from_event_list(events)

      # Should have latest value
      assert {:ok, "v3"} = ConfigStateProjection.get_config("key")
    end

    test "handles resurrection (delete then recreate)" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key", value: "original"},
        %ConfigValueDeleted{config_name: "key"},
        %ConfigValueSet{config_name: "key", value: "resurrected"}
      ]

      ConfigStateProjection.rebuild_from_event_list(events)

      assert {:ok, "resurrected"} = ConfigStateProjection.get_config("key")
    end

    test "handles empty event list" do
      ensure_projection_started()

      assert :ok = ConfigStateProjection.rebuild_from_event_list([])

      # No configs should exist
      assert [] = ConfigStateProjection.get_all_configs()
    end

    test "handles large event list" do
      ensure_projection_started()

      # Create 1000 events
      events = for i <- 1..1000 do
        %ConfigValueSet{config_name: "key_#{i}", value: "value_#{i}"}
      end

      assert :ok = ConfigStateProjection.rebuild_from_event_list(events)

      # Spot check a few
      assert {:ok, "value_1"} = ConfigStateProjection.get_config("key_1")
      assert {:ok, "value_500"} = ConfigStateProjection.get_config("key_500")
      assert {:ok, "value_1000"} = ConfigStateProjection.get_config("key_1000")
    end
  end

  describe "get_config/1" do
    test "returns error for non-existent key" do
      ensure_projection_started()

      assert {:error, :not_found} = ConfigStateProjection.get_config("non_existent")
    end

    test "returns value for existing key" do
      ensure_projection_started()

      event = %ConfigValueSet{config_name: "key", value: "value"}
      ConfigStateProjection.apply_event_immediately(event)

      assert {:ok, "value"} = ConfigStateProjection.get_config("key")
    end
  end

  describe "get_all_configs/0" do
    test "returns empty list when no configs" do
      ensure_projection_started()

      assert [] = ConfigStateProjection.get_all_configs()
    end

    test "returns all configs with correct format" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key1", value: "value1"},
        %ConfigValueSet{config_name: "key2", value: "value2"}
      ]

      ConfigStateProjection.rebuild_from_event_list(events)

      configs = ConfigStateProjection.get_all_configs()
      assert length(configs) == 2

      assert %{name: "key1", value: "value1"} in configs
      assert %{name: "key2", value: "value2"} in configs
    end

    test "does not include deleted configs" do
      ensure_projection_started()

      events = [
        %ConfigValueSet{config_name: "key1", value: "value1"},
        %ConfigValueSet{config_name: "key2", value: "value2"},
        %ConfigValueDeleted{config_name: "key1"}
      ]

      ConfigStateProjection.rebuild_from_event_list(events)

      configs = ConfigStateProjection.get_all_configs()
      assert length(configs) == 1
      assert %{name: "key2", value: "value2"} in configs
      refute Enum.any?(configs, &(&1.name == "key1"))
    end
  end

  # Helper to ensure projection is started for tests that use the real ETS table
  defp ensure_projection_started do
    case Process.whereis(ConfigStateProjection) do
      nil ->
        # Create ETS table manually if projection not running
        try do
          :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
        rescue
          ArgumentError -> :ok  # Table already exists
        end
      _pid ->
        :ok
    end
  end
end
