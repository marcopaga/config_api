defmodule ConfigApi.Aggregates.ConfigValue do
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

  def new do
    %__MODULE__{
      name: nil,
      value: nil,
      version: 0,
      deleted: false
    }
  end

  # Commands
  def set_value(%__MODULE__{deleted: true}, _name, _value) do
    {:error, :config_deleted}
  end

  def set_value(%__MODULE__{} = config, name, value) when is_binary(name) and is_binary(value) do
    event = ConfigValueSet.new(name, value, config.value)
    {:ok, event, apply_event(config, event)}
  end

  def set_value(_config, _name, _value) do
    {:error, :invalid_parameters}
  end

  def delete_value(%__MODULE__{name: nil}) do
    {:error, :config_not_found}
  end

  def delete_value(%__MODULE__{deleted: true}) do
    {:error, :config_already_deleted}
  end

  def delete_value(%__MODULE__{name: name, value: value} = config) do
    event = ConfigValueDeleted.new(name, value)
    {:ok, event, apply_event(config, event)}
  end

  # Event application
  def apply_event(%__MODULE__{} = config, %ConfigValueSet{} = event) do
    %{config |
      name: event.config_name,
      value: event.value,
      version: config.version + 1,
      deleted: false
    }
  end

  def apply_event(%__MODULE__{} = config, %ConfigValueDeleted{}) do
    %{config |
      deleted: true,
      version: config.version + 1
    }
  end

  # Replay events to rebuild state
  def replay_events(events) when is_list(events) do
    Enum.reduce(events, new(), &apply_event(&2, &1))
  end

  # Getters
  def current_value(%__MODULE__{deleted: true}), do: {:error, :not_found}
  def current_value(%__MODULE__{name: nil}), do: {:error, :not_found}
  def current_value(%__MODULE__{value: value}), do: {:ok, value}

  def exists?(%__MODULE__{name: nil}), do: false
  def exists?(%__MODULE__{deleted: true}), do: false
  def exists?(%__MODULE__{}), do: true
end
