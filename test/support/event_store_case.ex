defmodule ConfigApi.EventStoreCase do
  @moduledoc """
  Test case helper for EventStore tests.
  Provides setup to reset EventStore between tests.
  """

  use ExUnit.CaseTemplate

  alias ConfigApi.EventStore

  using do
    quote do
      alias ConfigApi.EventStore
      import ConfigApi.EventStoreCase
    end
  end

  setup do
    # Reset EventStore before each test
    :ok = reset_eventstore!()
    :ok
  end

  @doc """
  Resets the EventStore by truncating all tables.

  Uses a persistent connection pool to avoid connection overhead.
  """
  def reset_eventstore! do
    config = EventStore.config()

    # Reuse connection from EventStore if possible
    conn_pid = case get_or_create_test_connection(config) do
      {:ok, pid} -> pid
      {:error, _} ->
        # Fallback: create temporary connection
        {:ok, pid} = Postgrex.start_link(config)
        pid
    end

    # Truncate all EventStore tables in a single statement
    Postgrex.query!(
      conn_pid,
      "TRUNCATE TABLE streams, events, subscriptions, snapshots CASCADE;",
      [],
      timeout: 5000
    )

    :ok
  rescue
    error ->
      IO.puts("Warning: Failed to reset EventStore: #{inspect(error)}")
      :ok
  end

  # Get or create a persistent test connection
  defp get_or_create_test_connection(config) do
    case Process.whereis(:test_event_store_conn) do
      nil ->
        case Postgrex.start_link([{:name, :test_event_store_conn} | config]) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          # Should never happen, but handle it anyway
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end
end
