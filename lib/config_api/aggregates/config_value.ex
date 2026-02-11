defmodule ConfigApi.Aggregates.ConfigValue do
  @moduledoc """
  Aggregate root for configuration values in the CQRS/Event Sourcing system.

  This aggregate enforces business rules and generates events in response to commands.
  State is rebuilt by replaying events.
  """

  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  defstruct [
    :name,
    :value,
    :version,
    :deleted
  ]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          value: String.t() | nil,
          version: non_neg_integer(),
          deleted: boolean()
        }

  @doc """
  Creates a new empty aggregate.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      name: nil,
      value: nil,
      version: 0,
      deleted: false
    }
  end

  ## Commands

  @doc """
  Executes the set_value command on the aggregate.

  Business Rules:
  - Cannot set value on a deleted config
  - Name and value must be binary strings
  - Generates ConfigValueSet event with old_value for audit trail

  Returns {:ok, event, new_aggregate} or {:error, reason}
  """
  @spec set_value(t(), String.t(), String.t()) ::
          {:ok, ConfigValueSet.t(), t()} | {:error, atom()}
  def set_value(%__MODULE__{deleted: true}, _name, _value) do
    {:error, :config_deleted}
  end

  def set_value(%__MODULE__{} = config, name, value)
      when is_binary(name) and is_binary(value) do
    event = ConfigValueSet.new(name, value, config.value)
    new_aggregate = apply_event(config, event)
    {:ok, event, new_aggregate}
  end

  def set_value(_config, _name, _value) do
    {:error, :invalid_parameters}
  end

  @doc """
  Executes the delete_value command on the aggregate.

  Business Rules:
  - Cannot delete a config that doesn't exist (name is nil)
  - Cannot delete an already deleted config
  - Generates ConfigValueDeleted event with the deleted value

  Returns {:ok, event, new_aggregate} or {:error, reason}
  """
  @spec delete_value(t()) :: {:ok, ConfigValueDeleted.t(), t()} | {:error, atom()}
  def delete_value(%__MODULE__{name: nil}) do
    {:error, :config_not_found}
  end

  def delete_value(%__MODULE__{deleted: true}) do
    {:error, :config_already_deleted}
  end

  def delete_value(%__MODULE__{name: name, value: value} = config) do
    event = ConfigValueDeleted.new(name, value)
    new_aggregate = apply_event(config, event)
    {:ok, event, new_aggregate}
  end

  ## Event Application

  @doc """
  Applies an event to the aggregate state.

  - ConfigValueSet: Updates the name, value, increments version, and marks as not deleted.
  - ConfigValueDeleted: Marks the config as deleted and increments version. Name and value remain for audit purposes.
  """
  @spec apply_event(t(), ConfigValueSet.t() | ConfigValueDeleted.t()) :: t()
  def apply_event(%__MODULE__{} = config, %ConfigValueSet{} = event) do
    %{
      config
      | name: event.config_name,
        value: event.value,
        version: config.version + 1,
        deleted: false
    }
  end

  def apply_event(%__MODULE__{} = config, %ConfigValueDeleted{}) do
    %{config | deleted: true, version: config.version + 1}
  end

  ## Event Replay

  @doc """
  Rebuilds aggregate state by replaying a list of events.

  Events are applied in order to reconstruct the current state.
  This is how we implement event sourcing - state is derived from events.

  ## Examples
      iex> events = [
      ...>   ConfigApi.Events.ConfigValueSet.new("key", "value1"),
      ...>   ConfigApi.Events.ConfigValueSet.new("key", "value2", "value1")
      ...> ]
      iex> aggregate = ConfigApi.Aggregates.ConfigValue.replay_events(events)
      iex> aggregate.value
      "value2"
  """
  @spec replay_events([ConfigValueSet.t() | ConfigValueDeleted.t()]) :: t()
  def replay_events(events) when is_list(events) do
    Enum.reduce(events, new(), &apply_event(&2, &1))
  end

  ## Getters

  @doc """
  Returns the current value of the aggregate.

  Returns {:ok, value} if the config exists and is not deleted,
  or {:error, :not_found} otherwise.
  """
  @spec current_value(t()) :: {:ok, String.t()} | {:error, :not_found}
  def current_value(%__MODULE__{deleted: true}), do: {:error, :not_found}
  def current_value(%__MODULE__{name: nil}), do: {:error, :not_found}
  def current_value(%__MODULE__{value: value}), do: {:ok, value}

  @doc """
  Checks if the aggregate represents an existing, non-deleted config.
  """
  @spec exists?(t()) :: boolean()
  def exists?(%__MODULE__{name: nil}), do: false
  def exists?(%__MODULE__{deleted: true}), do: false
  def exists?(%__MODULE__{}), do: true
end
