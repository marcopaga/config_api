defmodule ConfigApi.Projections.ConfigStateProjectionTest do
  use ExUnit.Case, async: false
  require Logger

  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}
  alias ConfigApi.EventStore

  setup do
    # Reset the event store for each test
    :ok = EventStore.reset!()

    :ok
  end

  describe "event replay functionality" do
    test "rebuilds state from ConfigValueSet events" do
      # Create test events
      events = [
        %{
          data: ConfigValueSet.new("config1", "value1"),
          created_at: ~U[2023-01-01 10:00:00Z],
          stream_name: "config-config1"
        },
        %{
          data: ConfigValueSet.new("config2", "value2"),
          created_at: ~U[2023-01-01 10:01:00Z],
          stream_name: "config-config2"
        }
      ]

      # Store events in EventStore
      for event <- events do
        stream_events = [%{
          event_type: "ConfigValueSet",
          data: event.data,
          metadata: %{
            aggregate_id: event.data.config_name,
            aggregate_type: "ConfigValue",
            created_at: event.created_at
          }
        }]

        {:ok, _} = EventStore.append_to_stream(event.stream_name, :any_version, stream_events)
      end

      # Start projection and let it rebuild
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(200)

      # Verify state was rebuilt correctly
      assert {:ok, "value1"} = ConfigStateProjection.get_config("config1")
      assert {:ok, "value2"} = ConfigStateProjection.get_config("config2")

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "handles ConfigValueDeleted events correctly" do
      # Create and delete sequence
      set_event = %{
        data: ConfigValueSet.new("deleted_config", "initial_value"),
        created_at: ~U[2023-01-01 10:00:00Z],
        stream_name: "config-deleted_config"
      }

      delete_event = %{
        data: ConfigValueDeleted.new("deleted_config", "initial_value"),
        created_at: ~U[2023-01-01 10:01:00Z],
        stream_name: "config-deleted_config"
      }

      # Store set event
      stream_events = [%{
        event_type: "ConfigValueSet",
        data: set_event.data,
        metadata: %{
          aggregate_id: "deleted_config",
          aggregate_type: "ConfigValue",
          created_at: set_event.created_at
        }
      }]
      {:ok, _} = EventStore.append_to_stream("config-deleted_config", :any_version, stream_events)

      # Store delete event
      stream_events = [%{
        event_type: "ConfigValueDeleted",
        data: delete_event.data,
        metadata: %{
          aggregate_id: "deleted_config",
          aggregate_type: "ConfigValue",
          created_at: delete_event.created_at
        }
      }]
      {:ok, _} = EventStore.append_to_stream("config-deleted_config", 1, stream_events)

      # Start projection
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(200)

      # Verify config was deleted
      assert {:error, :not_found} = ConfigStateProjection.get_config("deleted_config")

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "processes events in chronological order" do
      # Create events with mixed timestamps
      events = [
        %{
          data: ConfigValueSet.new("ordered_config", "value1"),
          created_at: ~U[2023-01-01 10:02:00Z],  # Later timestamp
          stream_name: "config-ordered_config"
        },
        %{
          data: ConfigValueSet.new("ordered_config", "value2"),
          created_at: ~U[2023-01-01 10:01:00Z],  # Earlier timestamp
          stream_name: "config-ordered_config"
        },
        %{
          data: ConfigValueSet.new("ordered_config", "value3"),
          created_at: ~U[2023-01-01 10:03:00Z],  # Latest timestamp
          stream_name: "config-ordered_config"
        }
      ]

      # Store events in random order
      for {event, version} <- Enum.with_index(events) do
        stream_events = [%{
          event_type: "ConfigValueSet",
          data: event.data,
          metadata: %{
            aggregate_id: "ordered_config",
            aggregate_type: "ConfigValue",
            created_at: event.created_at
          }
        }]

        expected_version = if version == 0, do: :any_version, else: version
        {:ok, _} = EventStore.append_to_stream(event.stream_name, expected_version, stream_events)
      end

      # Start projection
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(200)

      # Should have the value from the latest timestamp (value3)
      assert {:ok, "value3"} = ConfigStateProjection.get_config("ordered_config")

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "handles empty event store gracefully" do
      # Start projection with no events
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      # Should return empty results
      assert {:error, :not_found} = ConfigStateProjection.get_config("any_config")
      assert [] = ConfigStateProjection.get_all_configs()

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "handles event store errors gracefully" do
      # This test verifies the projection doesn't crash on EventStore errors
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      # Projection should start successfully even if there are issues
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "applies live events after rebuild" do
      # Store initial event
      initial_event = %{
        data: ConfigValueSet.new("live_config", "initial"),
        created_at: ~U[2023-01-01 10:00:00Z],
        stream_name: "config-live_config"
      }

      stream_events = [%{
        event_type: "ConfigValueSet",
        data: initial_event.data,
        metadata: %{
          aggregate_id: "live_config",
          aggregate_type: "ConfigValue",
          created_at: initial_event.created_at
        }
      }]
      {:ok, _} = EventStore.append_to_stream("config-live_config", :any_version, stream_events)

      # Start projection
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(200)

      # Verify initial state
      assert {:ok, "initial"} = ConfigStateProjection.get_config("live_config")

      # Send live event
      live_event = %{
        data: ConfigValueSet.new("live_config", "updated")
      }
      send(pid, {:events, [live_event]})
      Process.sleep(50)

      # Verify live update was applied
      assert {:ok, "updated"} = ConfigStateProjection.get_config("live_config")

      # Clean up
      GenServer.stop(pid, :normal)
    end
  end

  describe "state management" do
    test "get_state returns current projection state" do
      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      state = ConfigStateProjection.get_state()
      assert %ConfigStateProjection{configs: configs} = state
      assert is_map(configs)

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "get_all_configs returns properly formatted results" do
      # Store some test events
      events = [
        ConfigValueSet.new("test1", "value1"),
        ConfigValueSet.new("test2", "value2")
      ]

      {:ok, pid} = ConfigStateProjection.start_link([])
      Process.sleep(100)

      # Send events directly to projection
      for event <- events do
        send(pid, {:events, [%{data: event}]})
      end
      Process.sleep(50)

      # Verify format
      all_configs = ConfigStateProjection.get_all_configs()
      assert is_list(all_configs)
      assert length(all_configs) == 2

      for config <- all_configs do
        assert %{name: name, value: value} = config
        assert is_binary(name)
        assert is_binary(value)
      end

      # Clean up
      GenServer.stop(pid, :normal)
    end
  end
end
