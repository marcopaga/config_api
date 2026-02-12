defmodule ConfigApi.ConfigStoreCQRS do
  @moduledoc """
  CQRS-based configuration store using Event Sourcing.

  This module implements the complete CQRS pattern:
  - Write path: Command → Aggregate → Event → EventStore
  - Read path: Projection → ETS → Response

  This is the new implementation that will eventually replace ConfigStore (Memento).
  """

  alias ConfigApi.Aggregates.ConfigValue
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}
  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.EventStore
  require Logger

  ## Public API

  @doc """
  Gets a configuration value by name.

  Uses the projection for fast reads (CQRS read path).

  Returns {:ok, value} if found, {:error, :not_found} otherwise.
  """
  @spec get(String.t()) :: {:ok, String.t()} | {:error, :not_found | :internal_error}
  def get(name) do
    Logger.debug("ConfigStoreCQRS.get/1 called with name=#{inspect(name)}")

    try do
      result = ConfigStateProjection.get_config(name)
      Logger.debug("ConfigStoreCQRS.get/1 result for #{name}: #{inspect(result)}")
      result
    rescue
      error ->
        Logger.error("ConfigStoreCQRS.get/1 exception for #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Sets a configuration value.

  CQRS write path:
  1. Load aggregate events from EventStore
  2. Replay events to rebuild aggregate state
  3. Execute command on aggregate
  4. Append new event to EventStore
  5. Projection automatically updates via subscription

  Returns {:ok, value} on success, {:error, reason} on failure.
  """
  @spec put(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def put(name, value) when is_binary(name) and is_binary(value) do
    Logger.debug("ConfigStoreCQRS.put/2 called with name=#{inspect(name)}, value=#{inspect(value)}")

    with {:ok, events} <- load_aggregate_events(name),
         aggregate <- ConfigValue.replay_events(events),
         {:ok, event, _new_aggregate} <- ConfigValue.set_value(aggregate, name, value),
         :ok <- append_event(name, event) do
      Logger.debug("ConfigStoreCQRS.put/2 successfully stored config #{name}")

      # Immediately update projection (synchronous for immediate consistency)
      ConfigApi.Projections.ConfigStateProjection.apply_event_immediately(event)

      # Notify worker (async, non-blocking)
      notify_worker(:config_updated, name, aggregate, value)

      {:ok, value}
    else
      {:error, reason} = error ->
        Logger.error("ConfigStoreCQRS.put/2 failed for #{name}: #{inspect(reason)}")
        error

      error ->
        Logger.error("ConfigStoreCQRS.put/2 unexpected error for #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Deletes a configuration value.

  CQRS write path with delete command.

  Returns :ok on success, {:error, reason} on failure.
  """
  @spec delete(String.t()) :: :ok | {:error, atom()}
  def delete(name) when is_binary(name) do
    Logger.debug("ConfigStoreCQRS.delete/1 called with name=#{inspect(name)}")

    with {:ok, events} <- load_aggregate_events(name),
         aggregate <- ConfigValue.replay_events(events),
         {:ok, event, _new_aggregate} <- ConfigValue.delete_value(aggregate),
         :ok <- append_event(name, event) do
      Logger.debug("ConfigStoreCQRS.delete/1 successfully deleted config #{name}")

      # Immediately update projection (synchronous for immediate consistency)
      ConfigApi.Projections.ConfigStateProjection.apply_event_immediately(event)

      # Notify worker
      notify_worker(:config_deleted, name, aggregate, nil)

      :ok
    else
      {:error, reason} = error ->
        Logger.error("ConfigStoreCQRS.delete/1 failed for #{name}: #{inspect(reason)}")
        error

      error ->
        Logger.error("ConfigStoreCQRS.delete/1 unexpected error for #{name}: #{inspect(error)}")
        {:error, :internal_error}
    end
  end

  @doc """
  Gets all configuration values.

  Uses the projection for fast reads.

  Returns a list of maps with :name and :value keys.
  """
  @spec all() :: [%{name: String.t(), value: String.t()}]
  def all do
    Logger.debug("ConfigStoreCQRS.all/0 called")

    try do
      result = ConfigStateProjection.get_all_configs()
      Logger.debug("ConfigStoreCQRS.all/0 returned #{length(result)} configs")
      result
    rescue
      error ->
        Logger.error("ConfigStoreCQRS.all/0 exception: #{inspect(error)}")
        []
    end
  end

  @doc """
  Gets the complete event history for a configuration.

  Returns all events for the given config name in chronological order.

  Returns {:ok, history} where history is a list of event maps,
  or {:error, reason} on failure.
  """
  @spec get_history(String.t()) :: {:ok, [map()]} | {:error, atom()}
  def get_history(name) when is_binary(name) do
    stream_name = build_stream_name(name)

    case EventStore.read_stream_forward(stream_name) do
      {:ok, events} ->
        history =
          Enum.map(events, fn event ->
            %{
              event_type: event.event_type,
              data: event.data,
              metadata: event.metadata,
              created_at: event.created_at,
              stream_version: event.stream_version
            }
          end)

        {:ok, history}

      {:error, :stream_not_found} ->
        {:ok, []}

      error ->
        error
    end
  end

  @doc """
  Gets configuration value at a specific point in time.

  Replays events up to the given timestamp to reconstruct historical state.

  Returns {:ok, value} or {:error, reason}.
  """
  @spec get_at_timestamp(String.t(), DateTime.t()) ::
          {:ok, String.t()} | {:error, :not_found | atom()}
  def get_at_timestamp(name, %DateTime{} = timestamp) when is_binary(name) do
    stream_name = build_stream_name(name)

    with {:ok, recorded_events} <- EventStore.read_stream_forward(stream_name),
         filtered_recorded <- filter_recorded_events_by_timestamp(recorded_events, timestamp),
         domain_events <- Enum.map(filtered_recorded, & &1.data),
         aggregate <- ConfigValue.replay_events(domain_events) do
      ConfigValue.current_value(aggregate)
    else
      {:error, :stream_not_found} -> {:error, :not_found}
      error -> error
    end
  end

  ## Private Functions

  defp load_aggregate_events(name) do
    stream_name = build_stream_name(name)

    case EventStore.read_stream_forward(stream_name) do
      {:ok, events} ->
        domain_events = Enum.map(events, & &1.data)
        {:ok, domain_events}

      {:error, :stream_not_found} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp append_event(name, event) do
    stream_name = build_stream_name(name)
    event_type = event_type_from_struct(event)

    Logger.info("append_event: stream=#{stream_name}, event_type=#{event_type}")

    event_data = %Elixir.EventStore.EventData{
      event_type: event_type,
      data: event,
      metadata: %{
        aggregate_id: name,
        aggregate_type: "ConfigValue"
      }
    }

    case EventStore.append_to_stream(stream_name, :any_version, [event_data]) do
      :ok ->
        Logger.info("append_event: Successfully appended to #{stream_name}")
        :ok

      error ->
        Logger.error("append_event: Failed to append to #{stream_name}: #{inspect(error)}")
        error
    end
  end

  defp build_stream_name(name) do
    "config-#{name}"
  end

  defp event_type_from_struct(%ConfigValueSet{} = event) do
    event.__struct__
    |> Atom.to_string()
  end

  defp event_type_from_struct(%ConfigValueDeleted{} = event) do
    event.__struct__
    |> Atom.to_string()
  end

  defp filter_recorded_events_by_timestamp(recorded_events, timestamp) do
    Enum.filter(recorded_events, fn recorded_event ->
      DateTime.compare(recorded_event.created_at, timestamp) != :gt
    end)
  end

  defp notify_worker(:config_updated, name, aggregate, new_value) do
    old_value =
      case ConfigValue.current_value(aggregate) do
        {:ok, val} -> val
        {:error, :not_found} -> nil
      end

    timestamp = DateTime.utc_now()

    try do
      send(:config_update_worker, {:config_updated, name, old_value, new_value, timestamp})
      Logger.debug("ConfigStoreCQRS notified ConfigUpdateWorker")
    rescue
      error ->
        Logger.warning("ConfigStoreCQRS failed to notify worker: #{inspect(error)}")
    end
  end

  defp notify_worker(:config_deleted, name, aggregate, _) do
    old_value =
      case ConfigValue.current_value(aggregate) do
        {:ok, val} -> val
        {:error, :not_found} -> nil
      end

    timestamp = DateTime.utc_now()

    try do
      send(:config_update_worker, {:config_deleted, name, old_value, timestamp})
      Logger.debug("ConfigStoreCQRS notified ConfigUpdateWorker of deletion")
    rescue
      error ->
        Logger.warning("ConfigStoreCQRS failed to notify worker: #{inspect(error)}")
    end
  end
end
