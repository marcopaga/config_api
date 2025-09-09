defmodule ConfigApi.ConfigUpdateWorkerTest do
  use ExUnit.Case, async: false
  require Logger

  alias ConfigApi.ConfigUpdateWorker

  setup do
    # Start a fresh worker for each test
    if Process.whereis(:config_update_worker) do
      GenServer.stop(:config_update_worker, :normal)
      Process.sleep(50)
    end

    {:ok, pid} = ConfigUpdateWorker.start_link([])

    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal)
      end
    end)

    {:ok, worker_pid: pid}
  end

  describe "worker initialization" do
    test "starts successfully and registers process name", %{worker_pid: pid} do
      assert Process.alive?(pid)
      assert Process.whereis(:config_update_worker) == pid
    end

    test "initializes with correct state", %{worker_pid: _pid} do
      stats = ConfigUpdateWorker.get_stats()

      assert %{
        message_count: 0,
        uptime_seconds: uptime,
        started_at: started_at
      } = stats

      assert is_integer(uptime)
      assert uptime >= 0
      assert %DateTime{} = started_at
    end
  end

  describe "config update message handling" do
    test "processes config_updated messages correctly", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      # Capture log output
      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:config_updated, "test_config", "old_value", "new_value", timestamp})
        Process.sleep(50)
      end)

      # Verify log contains expected information
      assert log_output =~ "Config updated"
      assert log_output =~ "test_config"
      assert log_output =~ "old_value"
      assert log_output =~ "new_value"
      assert log_output =~ "[msg #1]"
    end

    test "processes config_deleted messages correctly", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:config_deleted, "deleted_config", "deleted_value", timestamp})
        Process.sleep(50)
      end)

      assert log_output =~ "Config deleted"
      assert log_output =~ "deleted_config"
      assert log_output =~ "deleted_value"
      assert log_output =~ "[msg #1]"
    end

    test "increments message count correctly", %{worker_pid: pid} do
      initial_stats = ConfigUpdateWorker.get_stats()
      assert initial_stats.message_count == 0

      timestamp = DateTime.utc_now()

      # Send multiple messages
      send(pid, {:config_updated, "config1", nil, "value1", timestamp})
      send(pid, {:config_updated, "config2", "old", "new", timestamp})
      send(pid, {:config_deleted, "config3", "deleted", timestamp})

      Process.sleep(100)

      updated_stats = ConfigUpdateWorker.get_stats()
      assert updated_stats.message_count == 3
    end

    test "handles nil values in messages correctly", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:config_updated, "nil_test", nil, "new_value", timestamp})
        Process.sleep(50)
      end)

      assert log_output =~ "old_value=nil"
      assert log_output =~ "new_value=new_value"
    end

    test "formats different value types correctly", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      test_cases = [
        {nil, "nil"},
        {"string_value", "string_value"},
        {123, "123"},
        {%{key: "value"}, "%{key: \"value\"}"}
      ]

      for {value, expected_format} <- test_cases do
        log_output = ExUnit.CaptureLog.capture_log(fn ->
          send(pid, {:config_updated, "format_test", value, "new", timestamp})
          Process.sleep(50)
        end)

        assert log_output =~ expected_format
      end
    end
  end

  describe "health check functionality" do
    test "responds to health check messages", %{worker_pid: pid} do
      # Send some messages first to have data
      timestamp = DateTime.utc_now()
      send(pid, {:config_updated, "health_test", nil, "value", timestamp})
      Process.sleep(50)

      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, :health_check)
        Process.sleep(50)
      end)

      assert log_output =~ "ConfigUpdateWorker health check"
      assert log_output =~ "1 messages processed"
      assert log_output =~ "uptime:"
    end

    test "health check shows correct uptime", %{worker_pid: pid} do
      Process.sleep(100)

      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, :health_check)
        Process.sleep(50)
      end)

      # Should show at least some uptime
      assert log_output =~ ~r/uptime: \d+s/
    end
  end

  describe "unexpected message handling" do
    test "logs warnings for unexpected messages", %{worker_pid: pid} do
      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:unexpected_message, "some_data"})
        send(pid, "invalid_message")
        send(pid, 12345)
        Process.sleep(100)
      end)

      assert log_output =~ "received unexpected message"
      # Should contain at least 3 warning messages
      warning_count =
        (log_output
          |> String.split("unexpected message")
          |> length()) - 1
      assert warning_count >= 3
    end

    test "continues processing after unexpected messages", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      # Send unexpected message
      send(pid, {:invalid, "message"})
      Process.sleep(50)

      # Send valid message
      log_output = ExUnit.CaptureLog.capture_log(fn ->
        send(pid, {:config_updated, "after_invalid", nil, "value", timestamp})
        Process.sleep(50)
      end)

      # Should still process valid messages
      assert log_output =~ "Config updated"
      assert log_output =~ "after_invalid"
    end
  end

  describe "statistics tracking" do
    test "get_stats returns complete information", %{worker_pid: _pid} do
      stats = ConfigUpdateWorker.get_stats()

      assert Map.has_key?(stats, :message_count)
      assert Map.has_key?(stats, :uptime_seconds)
      assert Map.has_key?(stats, :started_at)

      assert is_integer(stats.message_count)
      assert is_integer(stats.uptime_seconds)
      assert %DateTime{} = stats.started_at
    end

    test "stats are updated in real-time", %{worker_pid: pid} do
      initial_stats = ConfigUpdateWorker.get_stats()
      initial_time = DateTime.utc_now()

      # Wait a bit and send messages
      Process.sleep(100)
      timestamp = DateTime.utc_now()
      send(pid, {:config_updated, "stats_test", nil, "value", timestamp})
      Process.sleep(50)

      updated_stats = ConfigUpdateWorker.get_stats()

      # Message count should increase
      assert updated_stats.message_count > initial_stats.message_count

      # Uptime should increase
      assert updated_stats.uptime_seconds > initial_stats.uptime_seconds

      # Started time should remain the same
      assert updated_stats.started_at == initial_stats.started_at
    end
  end

  describe "concurrent message handling" do
    test "handles multiple concurrent messages", %{worker_pid: pid} do
      timestamp = DateTime.utc_now()

      # Send many messages concurrently
      tasks = for i <- 1..10 do
        Task.async(fn ->
          send(pid, {:config_updated, "concurrent_#{i}", nil, "value_#{i}", timestamp})
        end)
      end

      # Wait for all tasks
      Task.await_many(tasks)
      Process.sleep(200)

      # Check final message count
      stats = ConfigUpdateWorker.get_stats()
      assert stats.message_count == 10
    end
  end

  describe "integration with ConfigStore" do
    test "receives messages when using notify_config_update/3", %{worker_pid: _pid} do
      initial_stats = ConfigUpdateWorker.get_stats()

      log_output = ExUnit.CaptureLog.capture_log(fn ->
        ConfigUpdateWorker.notify_config_update("integration_test", "old", "new")
        Process.sleep(100)
      end)

      # Should see the log message
      assert log_output =~ "Config updated"
      assert log_output =~ "integration_test"

      # Stats should be updated
      updated_stats = ConfigUpdateWorker.get_stats()
      assert updated_stats.message_count > initial_stats.message_count
    end
  end
end
