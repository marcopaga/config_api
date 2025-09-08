defmodule ConfigApi.Events.ConfigValueSet do
  @derive Jason.Encoder
  defstruct [
    :config_name,
    :value,
    :previous_value,
    :timestamp,
    :metadata
  ]

  @type t :: %__MODULE__{
    config_name: String.t(),
    value: String.t(),
    previous_value: String.t() | nil,
    timestamp: DateTime.t(),
    metadata: map()
  }

  def new(config_name, value, previous_value \\ nil, metadata \\ %{}) do
    %__MODULE__{
      config_name: config_name,
      value: value,
      previous_value: previous_value,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end
end
