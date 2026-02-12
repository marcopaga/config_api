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
  """
  def reset_eventstore! do
    config = EventStore.config()

    {:ok, conn} = Postgrex.start_link(config)

    # Truncate all EventStore tables
    Postgrex.query!(
      conn,
      "TRUNCATE TABLE streams, events, subscriptions, snapshots CASCADE;",
      []
    )

    GenServer.stop(conn)

    :ok
  rescue
    error ->
      IO.puts("Warning: Failed to reset EventStore: #{inspect(error)}")
      :ok
  end
end
