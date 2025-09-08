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
    Logger.info("ConfigUpdateWorker starting...")
    Logger.info("ConfigUpdateWorker registered as :config_update_worker and ready to receive messages")

    {:ok, %{message_count: 0, started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:config_updated, name, old_value, new_value, timestamp}, state) do
    iso_timestamp = DateTime.to_iso8601(timestamp)
    message_count = state.message_count + 1

    Logger.info(
      "Config updated at #{iso_timestamp}: name=#{name}, old_value=#{format_value(old_value)}, new_value=#{format_value(new_value)} [msg ##{message_count}]"
    )

    {:noreply, %{state | message_count: message_count}}
  end

  @impl true
  def handle_info({:config_deleted, name, deleted_value, timestamp}, state) do
    iso_timestamp = DateTime.to_iso8601(timestamp)
    message_count = state.message_count + 1

    Logger.info(
      "Config deleted at #{iso_timestamp}: name=#{name}, deleted_value=#{format_value(deleted_value)} [msg ##{message_count}]"
    )

    {:noreply, %{state | message_count: message_count}}
  end

  # Health check for monitoring
  @impl true
  def handle_info(:health_check, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)
    Logger.info("ConfigUpdateWorker health check: #{state.message_count} messages processed, uptime: #{uptime_seconds}s")
    {:noreply, state}
  end

  # Handle unexpected messages
  @impl true
  def handle_info(msg, state) do
    Logger.warning("ConfigUpdateWorker received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Add client functions for health monitoring
  def get_stats do
    GenServer.call(:config_update_worker, :get_stats)
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at)
    stats = %{
      message_count: state.message_count,
      uptime_seconds: uptime_seconds,
      started_at: state.started_at
    }
    {:reply, stats, state}
  end

  # Private helper functions
  defp format_value(nil), do: "nil"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)
end
