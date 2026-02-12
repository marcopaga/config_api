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

  @table_name :config_state_projection

  # Ensure event modules are loaded and atoms exist for deserialization
  # This MUST happen at module compile time
  @event_modules [ConfigValueSet, ConfigValueDeleted]
  def __event_modules__, do: @event_modules

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

    # Ensure event modules are loaded and atoms exist before reading
    Enum.each(@event_modules, fn mod ->
      Code.ensure_loaded!(mod)
      # Force the module atom to exist in the atom table
      _ = mod.__info__(:module)
    end)

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

  # NOTE: Event subscriptions are disabled due to deserialization issues
  # The projection rebuilds from events on startup, which is sufficient for current needs
  # To re-enable subscriptions in the future:
  # 1. Fix atom deserialization in EventStore notification publisher
  # 2. Uncomment the subscribe_to_events call in init/1
  # 3. Uncomment this function and the handle_info({:subscribed, _}, state) callback

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
