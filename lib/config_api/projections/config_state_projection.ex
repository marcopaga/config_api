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
    :ok = subscribe_to_events()

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
    case ConfigApi.EventStore.read_stream_forward("$all") do
      {:ok, recorded_events} ->
        Logger.debug("Replaying #{length(recorded_events)} events...")
        Enum.each(recorded_events, fn recorded_event ->
          apply_event(recorded_event.data)
        end)
        :ok

      {:error, :stream_not_found} ->
        Logger.debug("No events found, starting with empty state")
        :ok

      {:error, reason} ->
        Logger.error("Failed to read $all stream: #{inspect(reason)}")
        Logger.warning("Starting with empty state due to event read failure")
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
