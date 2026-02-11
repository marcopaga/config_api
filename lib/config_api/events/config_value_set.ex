defmodule ConfigApi.Events.ConfigValueSet do
  @moduledoc """
  Event fired when a configuration value is set or updated.

  This event records both the new value and the previous value (if any)
  to maintain a complete audit trail.
  """

  @derive Jason.Encoder
  defstruct [
    :config_name,
    :value,
    :old_value,
    :timestamp
  ]

  @type t :: %__MODULE__{
          config_name: String.t(),
          value: String.t(),
          old_value: String.t() | nil,
          timestamp: DateTime.t()
        }

  @doc """
  Creates a new ConfigValueSet event.

  ## Parameters
  - config_name: The name/key of the configuration
  - value: The new value being set
  - old_value: The previous value (nil if this is the first time setting)

  ## Examples
      iex> ConfigApi.Events.ConfigValueSet.new("api_key", "new_key", "old_key")
      %ConfigApi.Events.ConfigValueSet{
        config_name: "api_key",
        value: "new_key",
        old_value: "old_key",
        timestamp: ~U[...]
      }
  """
  @spec new(String.t(), String.t(), String.t() | nil) :: t()
  def new(config_name, value, old_value \\ nil) when is_binary(config_name) and is_binary(value) do
    %__MODULE__{
      config_name: config_name,
      value: value,
      old_value: old_value,
      timestamp: DateTime.utc_now()
    }
  end
end
