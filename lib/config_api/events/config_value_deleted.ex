defmodule ConfigApi.Events.ConfigValueDeleted do
  @moduledoc """
  Event fired when a configuration value is deleted.

  This event records the deleted value to maintain audit trail
  of what was removed.
  """

  @derive Jason.Encoder
  defstruct [
    :config_name,
    :deleted_value,
    :timestamp
  ]

  @type t :: %__MODULE__{
          config_name: String.t(),
          deleted_value: String.t(),
          timestamp: DateTime.t()
        }

  @doc """
  Creates a new ConfigValueDeleted event.

  ## Parameters
  - config_name: The name/key of the configuration being deleted
  - deleted_value: The value that was deleted

  ## Examples
      iex> ConfigApi.Events.ConfigValueDeleted.new("api_key", "secret123")
      %ConfigApi.Events.ConfigValueDeleted{
        config_name: "api_key",
        deleted_value: "secret123",
        timestamp: ~U[...]
      }
  """
  @spec new(String.t(), String.t()) :: t()
  def new(config_name, deleted_value) when is_binary(config_name) and is_binary(deleted_value) do
    %__MODULE__{
      config_name: config_name,
      deleted_value: deleted_value,
      timestamp: DateTime.utc_now()
    }
  end
end
