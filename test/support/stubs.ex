defmodule ConfigApi.Test.Stubs do
  @moduledoc """
  Simple stub implementations for testing without database.
  No mocking library required - just pure Elixir modules with Agent-based state.

  These stubs allow unit tests to run without PostgreSQL/EventStore dependencies,
  dramatically improving test performance (2-3 seconds vs 60+ seconds).
  """

  defmodule ProjectionStub do
    @moduledoc """
    Stub implementation of ConfigStateProjection for unit testing.
    Uses Agent to maintain in-memory state without ETS or GenServer complexity.
    """

    @doc "Start stub projection with optional initial state"
    def start_link(state \\ %{}) do
      Agent.start_link(fn -> state end, name: __MODULE__)
    end

    @doc "Get configuration value by name"
    def get_config(name) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state, name) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      end)
    end

    @doc "Get all configurations"
    def get_all_configs do
      Agent.get(__MODULE__, fn state ->
        Enum.map(state, fn {name, value} -> %{name: name, value: value} end)
      end)
    end

    @doc "Put configuration value (for test setup)"
    def put_config(name, value) do
      Agent.update(__MODULE__, fn state -> Map.put(state, name, value) end)
      :ok
    end

    @doc "Delete configuration value (for test setup)"
    def delete_config(name) do
      Agent.update(__MODULE__, fn state -> Map.delete(state, name) end)
      :ok
    end

    @doc "Clear all configurations (for test cleanup)"
    def clear_all do
      Agent.update(__MODULE__, fn _ -> %{} end)
      :ok
    end

    @doc "Stop the stub agent"
    def stop do
      Agent.stop(__MODULE__)
    end
  end

  defmodule EventStoreStub do
    @moduledoc """
    Stub implementation of EventStore for unit testing.
    Holds events in memory without PostgreSQL dependency.
    """

    @doc "Start stub EventStore with empty event list"
    def start_link do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    @doc "Append events to stream (simulates EventStore.append_to_stream)"
    def append_to_stream(_stream_uuid, _expected_version, events) when is_list(events) do
      Agent.update(__MODULE__, fn state -> state ++ events end)
      {:ok, length(events)}
    end

    @doc "Stream all events forward (simulates EventStore.stream_all_forward)"
    def stream_all_forward do
      events = Agent.get(__MODULE__, fn state -> state end)
      {:ok, events}
    end

    @doc "Read stream forward (simulates EventStore.read_stream_forward)"
    def read_stream_forward(stream_uuid, start_version \\ 0, count \\ 1000) do
      events = Agent.get(__MODULE__, fn state ->
        state
        |> Enum.filter(fn event -> event.stream_uuid == stream_uuid end)
        |> Enum.drop(start_version)
        |> Enum.take(count)
      end)

      {:ok, events}
    end

    @doc "Reset all events (for test cleanup)"
    def reset do
      Agent.update(__MODULE__, fn _ -> [] end)
      :ok
    end

    @doc "Get event count (for test assertions)"
    def count do
      Agent.get(__MODULE__, fn state -> length(state) end)
    end

    @doc "Stop the stub agent"
    def stop do
      Agent.stop(__MODULE__)
    end
  end

  defmodule ConfigStoreCQRSStub do
    @moduledoc """
    Stub implementation of ConfigStoreCQRS for HTTP layer testing.
    Allows testing Router without any CQRS/EventStore dependencies.
    """

    @doc "Start stub with optional initial state"
    def start_link(state \\ %{}) do
      Agent.start_link(fn -> state end, name: __MODULE__)
    end

    @doc "Get configuration value"
    def get(name) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state, name) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      end)
    end

    @doc "Get all configurations"
    def all do
      Agent.get(__MODULE__, fn state ->
        Enum.map(state, fn {name, value} -> %{name: name, value: value} end)
      end)
    end

    @doc "Put configuration value"
    def put(name, value) do
      Agent.update(__MODULE__, fn state -> Map.put(state, name, value) end)
      :ok
    end

    @doc "Delete configuration"
    def delete(name) do
      Agent.update(__MODULE__, fn state -> Map.delete(state, name) end)
      :ok
    end

    @doc "Get history (returns empty list in stub)"
    def get_history(_name) do
      {:ok, []}
    end

    @doc "Get value at timestamp (returns current value in stub)"
    def get_at_timestamp(name, _timestamp) do
      get(name)
    end

    @doc "Clear all (for test cleanup)"
    def clear_all do
      Agent.update(__MODULE__, fn _ -> %{} end)
      :ok
    end

    @doc "Stop the stub agent"
    def stop do
      Agent.stop(__MODULE__)
    end
  end
end
