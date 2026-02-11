defmodule ConfigApi.EventSerializer do
  @moduledoc """
  Custom JSON serializer for EventStore that ensures event type modules are loaded.

  This wraps EventStore.JsonSerializer and ensures that event type atoms/modules
  exist before attempting deserialization.
  """

  @behaviour EventStore.Serializer

  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  # Ensure event modules are loaded and atoms exist
  @event_modules [ConfigValueSet, ConfigValueDeleted]

  @impl EventStore.Serializer
  def serialize(term) do
    EventStore.JsonSerializer.serialize(term)
  end

  @impl EventStore.Serializer
  def deserialize(serialized, config) do
    # Ensure all event modules are loaded before deserialization
    Enum.each(@event_modules, &Code.ensure_loaded!/1)

    require Logger
    Logger.debug("ConfigApi.EventSerializer.deserialize called with config: #{inspect(config)}")

    result = EventStore.JsonSerializer.deserialize(serialized, config)
    Logger.debug("ConfigApi.EventSerializer.deserialize result: #{inspect(result)}")
    result
  end
end
