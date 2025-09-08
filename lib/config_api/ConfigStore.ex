defmodule ConfigApi.ConfigStore do
  alias ConfigApi.Aggregates.ConfigValue
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}
  alias ConfigApi.Projections.ConfigStateProjection
  require Logger

  # Ensure atoms exist for event deserialization
  @event_types ["ConfigValueSet", "ConfigValueDeleted"]
  Module.eval_quoted(__MODULE__, quote do
    Enum.each(@event_types, &String.to_atom/1)
  end)

  @doc """
  Get a configuration value by name.
  Uses the projection for fast reads.
  """
  def get(name) do
    Logger.debug("ConfigStore.get/1 called with name=#{inspect(name)}")

    try do
      result = ConfigStateProjection.get_config(name)
      Logger.debug("ConfigStore.get/1 result for #{name}: #{inspect(result)}")
      result
    rescue
      error ->
        Logger.error("ConfigStore.get/1 exception for #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Set a configuration value.
  Uses event sourcing with the ConfigValue aggregate.
  """
  def put(name, value) do
    Logger.debug("ConfigStore.put/2 called with name=#{inspect(name)}, value=#{inspect(value)}")

    with {:ok, events} <- load_aggregate_events(name),
         aggregate <- ConfigValue.replay_events(events),
         {:ok, event, _new_aggregate} <- ConfigValue.set_value(aggregate, name, value),
         :ok <- append_event(name, event) do

      # Get old value for worker notification
      old_value = case ConfigValue.current_value(aggregate) do
        {:ok, val} -> val
        {:error, :not_found} -> nil
      end

      Logger.debug("ConfigStore.put/2 successfully stored config #{name}")

      # Notify worker (async, non-blocking)
      timestamp = DateTime.utc_now()
      try do
        send(:config_update_worker, {:config_updated, name, old_value, value, timestamp})
        Logger.debug("ConfigStore.put/2 sent notification to ConfigUpdateWorker")
      rescue
        error ->
          Logger.warning("ConfigStore.put/2 failed to notify worker: #{inspect(error)}")
      end

      {:ok, value}
    else
      {:error, reason} = error ->
        Logger.error("ConfigStore.put/2 failed for #{name}: #{inspect(reason)}")
        error
      error ->
        Logger.error("ConfigStore.put/2 unexpected error for #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Delete a configuration value.
  """
  def delete(name) do
    with {:ok, events} <- load_aggregate_events(name),
         aggregate <- ConfigValue.replay_events(events),
         {:ok, event, _new_aggregate} <- ConfigValue.delete_value(aggregate),
         {:ok, _} <- append_event(name, event) do

      # Get old value for worker notification
      old_value = case ConfigValue.current_value(aggregate) do
        {:ok, val} -> val
        {:error, :not_found} -> nil
      end

      # Notify worker (async, non-blocking)
      timestamp = DateTime.utc_now()
      send(:config_update_worker, {:config_deleted, name, old_value, timestamp})

      :ok
    else
      {:error, reason} -> {:error, reason}
      error ->
        Logger.error("Failed to delete config #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Get all configuration values.
  Uses the projection for fast reads.
  """
  def all do
    Logger.debug("ConfigStore.all/0 called")

    try do
      result = ConfigStateProjection.get_all_configs()
      Logger.debug("ConfigStore.all/0 returned #{length(result)} configs")
      result
    rescue
      error ->
        Logger.error("ConfigStore.all/0 exception: #{inspect(error)}")
        []
    end
  end

  @doc """
  Get the history of a configuration value.
  Returns all events for the given config name.
  """
  def get_history(name) do
    stream_name = build_stream_name(name)

    case ConfigApi.EventStore.read_stream_forward(stream_name) do
      {:ok, events} ->
        history = Enum.map(events, fn event ->
          %{
            event_type: event.event_type,
            data: event.data,
            metadata: event.metadata,
            created_at: event.created_at,
            stream_version: event.stream_version
          }
        end)
        {:ok, history}

      {:error, :stream_not_found} -> {:ok, []}
      error -> error
    end
  end

  @doc """
  Get config value at a specific point in time.
  Replays events up to the given timestamp.
  """
  def get_at_timestamp(name, timestamp) do
    with {:ok, events} <- load_aggregate_events(name),
         filtered_events <- filter_events_by_timestamp(events, timestamp),
         aggregate <- ConfigValue.replay_events(filtered_events) do
      ConfigValue.current_value(aggregate)
    end
  end

  # Private functions

  defp load_aggregate_events(name) do
    stream_name = build_stream_name(name)

    case ConfigApi.EventStore.read_stream_forward(stream_name) do
      {:ok, events} ->
        domain_events = Enum.map(events, & &1.data)
        {:ok, domain_events}

      {:error, :stream_not_found} -> {:ok, []}
      error -> error
    end
  end

  defp append_event(name, event) do
    stream_name = build_stream_name(name)

    event_data = %EventStore.EventData{
      event_type: event_type_from_struct(event),
      data: event,
      metadata: %{
        aggregate_id: name,
        aggregate_type: "ConfigValue"
      }
    }

    case ConfigApi.EventStore.append_to_stream(stream_name, :any_version, [event_data]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp build_stream_name(name) do
    "config-#{name}"
  end

  defp event_type_from_struct(event), do: Atom.to_string(event.__struct__)

  defp filter_events_by_timestamp(events, timestamp) do
    Enum.filter(events, fn event ->
      case event do
        %ConfigValueSet{timestamp: event_timestamp} ->
          DateTime.compare(event_timestamp, timestamp) != :gt
        %ConfigValueDeleted{timestamp: event_timestamp} ->
          DateTime.compare(event_timestamp, timestamp) != :gt
        _ -> true
      end
    end)
  end
end
