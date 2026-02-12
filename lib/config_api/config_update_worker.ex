defmodule ConfigApi.ConfigUpdateWorker do
  use GenServer
  require Logger

  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: :config_update_worker)
  end

  def notify_config_update(name, old_value, new_value) do
    timestamp = DateTime.utc_now()
    send(:config_update_worker, {:config_updated, name, old_value, new_value, timestamp})
    :ok
  end

  # Server Callbacks
  @impl true
  def init(_opts) do
    Logger.info("ConfigUpdateWorker started")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:config_updated, name, old_value, new_value, timestamp}, state) do
    iso_timestamp = DateTime.to_iso8601(timestamp)

    Logger.info(
      "Config updated at #{iso_timestamp}: name=#{name}, old_value=#{format_value(old_value)}, new_value=#{format_value(new_value)}"
    )

    {:noreply, state}
  end

  # Handle unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.warning("ConfigUpdateWorker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helper functions
  defp format_value(nil), do: "nil"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)
end
