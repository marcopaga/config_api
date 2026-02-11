defmodule ConfigApi.Projections.ConfigStateProjection do
  @moduledoc """
  Read model projection for configuration state.

  This GenServer maintains an in-memory ETS table with the current state
  of all configurations, rebuilt from events on startup and updated as
  new events arrive.

  This implements the "query side" of CQRS - fast reads from memory.
  """

  use GenServer
  require Logger

  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  # Ensure event type atoms exist for EventStore deserialization
  _ = :"ConfigApi.Events.ConfigValueSet"
  _ = :"ConfigApi.Events.ConfigValueDeleted"

  @table_name :config_state_projection

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a configuration value by name.

  Returns {:ok, value} if found, {:error, :not_found} otherwise.
  """
  @spec get_config(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get_config(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets all configuration values.

  Returns a list of maps with :name and :value keys.
  """
  @spec get_all_configs() :: [%{name: String.t(), value: String.t()}]
  def get_all_configs do
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {name, value} -> %{name: name, value: value} end)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ConfigStateProjection starting...")

    # Create ETS table
    table = :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])

    # Rebuild state from all events
    Logger.info("Rebuilding ConfigStateProjection state from existing events...")
    rebuild_from_events()

    # Subscribe to new events
    # TODO: Fix event deserialization in Publisher before enabling subscriptions
    # :ok = subscribe_to_events()
    Logger.warning("Event subscriptions disabled - projection will only update on restart")

    config_count = :ets.info(@table_name, :size)
    Logger.info("ConfigStateProjection started with #{config_count} configs")

    {:ok, %{table: table}}
  end

  @impl true
  def handle_info({:events, events}, state) do
    # Process each event
    Enum.each(events, &apply_event/1)
    {:noreply, state}
  end

  @impl true
  def handle_info({:subscribed, subscription}, state) do
    Logger.info("ConfigStateProjection subscribed to EventStore events")
    {:noreply, Map.put(state, :subscription, subscription)}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("ConfigStateProjection received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp rebuild_from_events do
    Logger.info("rebuild_from_events: Reading all config streams...")

    try do
      # Get all stream names from the database
      # Then read from each stream
      config = ConfigApi.EventStore.config()
      {:ok, conn} = Postgrex.start_link(config)

      # Query for all config-* streams
      {:ok, result} =
        Postgrex.query(
          conn,
          "SELECT stream_uuid FROM streams WHERE stream_uuid LIKE 'config-%' AND deleted_at IS NULL",
          []
        )

      GenServer.stop(conn)

      stream_names = Enum.map(result.rows, fn [name] -> name end)
      Logger.info("Found #{length(stream_names)} config streams to rebuild from")

      # Read events from each stream
      all_events =
        Enum.flat_map(stream_names, fn stream_name ->
          case ConfigApi.EventStore.read_stream_forward(stream_name) do
            {:ok, events} ->
              Logger.debug("Read #{length(events)} events from #{stream_name}")
              events

            {:error, reason} ->
              Logger.warning("Failed to read #{stream_name}: #{inspect(reason)}")
              []
          end
        end)

      case all_events do
        [] ->
          Logger.warning("No events found in any streams, starting with empty state")
          :ok

        events ->
          Logger.info("Replaying #{length(events)} events from all config streams...")

          Enum.each(events, fn recorded_event ->
            Logger.debug(
              "Applying event: #{inspect(recorded_event.event_type)}"
            )

            apply_event(recorded_event.data)
          end)

          Logger.info("Successfully rebuilt projection from #{length(events)} events")
          :ok
      end
    rescue
      error ->
        Logger.error("Failed to rebuild from events: #{inspect(error)}")
        Logger.warning("Starting with empty state due to rebuild failure")
        :ok
    end
  end

  defp subscribe_to_events do
    case ConfigApi.EventStore.subscribe_to_all_streams(
           "config_state_projection",
           self(),
           start_from: :origin
         ) do
      {:ok, subscription} ->
        send(self(), {:subscribed, subscription})
        :ok

      {:error, reason} ->
        Logger.error("Failed to subscribe to events: #{inspect(reason)}")
        :ok
    end
  end

  defp apply_event(%ConfigValueSet{config_name: name, value: value}) do
    :ets.insert(@table_name, {name, value})
  end

  defp apply_event(%ConfigValueDeleted{config_name: name}) do
    :ets.delete(@table_name, name)
  end

  defp apply_event(event) do
    Logger.debug("Ignoring unknown event type: #{inspect(event.__struct__)}")
    :ok
  end
end
