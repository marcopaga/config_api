defmodule ConfigApi.Events.ConfigValueDeleted do
  @derive Jason.Encoder
  defstruct [
    :config_name,
    :deleted_value,
    :timestamp,
    :metadata
  ]

  @type t :: %__MODULE__{
    config_name: String.t(),
    deleted_value: String.t(),
    timestamp: DateTime.t(),
    metadata: map()
  }

  def new(config_name, deleted_value, metadata \\ %{}) do
    %__MODULE__{
      config_name: config_name,
      deleted_value: deleted_value,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end
end
