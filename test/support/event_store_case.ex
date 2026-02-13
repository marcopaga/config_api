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

  Creates a fresh connection for each reset to avoid connection pool issues.
  """
  def reset_eventstore! do
    config = EventStore.config()

    # Create a fresh connection for this reset operation
    {:ok, conn_pid} = Postgrex.start_link(config)

    try do
      # Truncate all EventStore tables in a single statement
      Postgrex.query!(
        conn_pid,
        "TRUNCATE TABLE streams, events, subscriptions, snapshots CASCADE;",
        [],
        timeout: 10_000
      )

      :ok
    after
      # Always close the connection
      GenServer.stop(conn_pid, :normal)
    end
  rescue
    error ->
      IO.puts("Warning: Failed to reset EventStore: #{inspect(error)}")
      :ok
  end
end
