defmodule ConfigApi.Projections.ConfigStateProjection do
  use GenServer
  require Logger

  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}
  alias ConfigApi.EventStore

  # State structure: %{config_name => %{value: value, version: version, updated_at: timestamp}}
  defstruct configs: %{}

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_config(name) do
    GenServer.call(__MODULE__, {:get_config, name})
  end

  def get_all_configs do
    GenServer.call(__MODULE__, :get_all_configs)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks
  @impl true
  def init(_opts) do
    Logger.info("ConfigStateProjection starting...")

    # Rebuild state from existing events first
    state = rebuild_state_from_events()

    # Subscribe to events from EventStore with error handling
    case subscribe_to_events() do
      {:ok, subscription} ->
        Logger.info("ConfigStateProjection subscribed to EventStore events")
        new_state = Map.put(state, :subscription, subscription)
        Logger.info("ConfigStateProjection started with #{map_size(state.configs)} configs")
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to subscribe to EventStore: #{inspect(reason)}")
        Logger.warning("Starting without event subscription - real-time updates disabled")
        Logger.info("ConfigStateProjection started with #{map_size(state.configs)} configs (no subscription)")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:get_config, name}, _from, state) do
    case Map.get(state.configs, name) do
      nil -> {:reply, {:error, :not_found}, state}
      config -> {:reply, {:ok, config.value}, state}
    end
  end

  @impl true
  def handle_call(:get_all_configs, _from, state) do
    configs =
      state.configs
      |> Enum.map(fn {name, config} -> %{name: name, value: config.value} end)

    {:reply, configs, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:events, events}, state) do
    Logger.debug("ConfigStateProjection received #{length(events)} events")
    new_state = Enum.reduce(events, state, &apply_event/2)
    Logger.debug("ConfigStateProjection processed events, total configs: #{map_size(new_state.configs)}")
    {:noreply, new_state}
  end

  # Handle subscription errors and attempt reconnection
  @impl true
  def handle_info({:subscription_error, error}, state) do
    Logger.error("EventStore subscription error: #{inspect(error)}")
    Logger.info("Attempting to reconnect to EventStore...")

    case subscribe_to_events() do
      {:ok, subscription} ->
        Logger.info("Successfully reconnected to EventStore")
        new_state = Map.put(state, :subscription, subscription)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to reconnect to EventStore: #{inspect(reason)}")
        Logger.warning("Will continue without real-time updates")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("ConfigStateProjection received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions
  defp rebuild_state_from_events do
    Logger.info("Rebuilding ConfigStateProjection state from existing events...")

    try do
      # Read all events from all config streams
      case read_all_config_events() do
        {:ok, events} ->
          Logger.info("Found #{length(events)} events to replay")

          # Sort events by creation time to ensure proper order
          sorted_events = Enum.sort_by(events, & &1.created_at, DateTime)

          # Apply events to rebuild state
          state = Enum.reduce(sorted_events, %__MODULE__{}, &apply_event/2)

          config_count = map_size(state.configs)
          Logger.info("State rebuild complete: #{config_count} configurations restored")
          state

        {:error, reason} ->
          Logger.error("Failed to read events during state rebuild: #{inspect(reason)}")
          Logger.warning("Starting with empty state due to event read failure")
          %__MODULE__{}
      end
    rescue
      error ->
        Logger.error("Exception during state rebuild: #{inspect(error)}")
        Logger.warning("Starting with empty state due to exception")
        %__MODULE__{}
    end
  end

  defp read_all_config_events do
    try do
      # Use the EventStore $all stream to read all events
      case EventStore.read_stream_forward("$all") do
        {:ok, all_events} ->
          # Filter for config-related streams only
          config_events =
            all_events
            |> Enum.filter(fn event ->
              String.starts_with?(event.stream_name, "config-")
            end)

          {:ok, config_events}

        {:error, :stream_not_found} ->
          # No events exist yet
          Logger.info("No events found in EventStore")
          {:ok, []}

        {:error, reason} = error ->
          Logger.error("Failed to read $all stream: #{inspect(reason)}")
          error

        error ->
          Logger.error("Unexpected response reading $all stream: #{inspect(error)}")
          {:error, :unexpected_response}
      end
    rescue
      error ->
        Logger.error("Exception reading all config events: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp subscribe_to_events do
    try do
      ConfigApi.EventStore.subscribe_to_all_streams("config_state_projection", self())
    rescue
      error ->
        Logger.error("Exception during EventStore subscription: #{inspect(error)}")
        {:error, {:exception, error}}
    end
  end

  defp apply_event(%{data: %ConfigValueSet{} = event}, state) do
    config_info = %{
      value: event.value,
      version: Map.get(state.configs, event.config_name, %{version: 0}).version + 1,
      updated_at: event.timestamp
    }

    new_configs = Map.put(state.configs, event.config_name, config_info)
    %{state | configs: new_configs}
  end

  defp apply_event(%{data: %ConfigValueDeleted{} = event}, state) do
    new_configs = Map.delete(state.configs, event.config_name)
    %{state | configs: new_configs}
  end

  defp apply_event(_event, state) do
    # Ignore unknown events
    state
  end
end
