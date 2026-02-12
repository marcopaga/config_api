defmodule ConfigApi.EventStore do
  use EventStore, otp_app: :config_api

  # Custom initialization to support environment variables
  def init(config) do
    {:ok, config}
  end
end
