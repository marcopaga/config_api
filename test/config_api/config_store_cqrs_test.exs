defmodule ConfigApi.ConfigStoreCQRSTest do
  @moduledoc """
  Integration tests for ConfigStoreCQRS with real EventStore and Projection.

  These tests verify the complete CQRS flow with PostgreSQL/EventStore.
  Tagged with :integration - requires Docker to run.

  Run with: mix test --only integration
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  alias ConfigApi.ConfigStoreCQRS
  alias ConfigApi.Projections.ConfigStateProjection
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  # Ensure event type atoms exist for deserialization
  _ = :"ConfigApi.Events.ConfigValueSet"
  _ = :"ConfigApi.Events.ConfigValueDeleted"

  # Module attribute to track projection
  @projection_name ConfigStateProjection

  # Helper to rebuild projection from events manually
  defp rebuild_projection do
    require Logger
    Logger.info("TEST: rebuild_projection called")

    # Stop and restart the projection to rebuild from events
    pid = Process.whereis(@projection_name)

    if pid do
      Logger.info("TEST: Stopping existing projection #{inspect(pid)}")
      GenServer.stop(pid, :normal)
    end

    Process.sleep(50)

    try do
      :ets.delete(:config_state_projection)
      Logger.info("TEST: Deleted ETS table")
    rescue
      ArgumentError ->
        Logger.info("TEST: ETS table didn't exist")
        :ok
    end

    Logger.info("TEST: Starting projection to rebuild")

    case ConfigStateProjection.start_link() do
      {:ok, pid} ->
        Logger.info("TEST: Projection started with pid #{inspect(pid)}")
        :ok

      {:error, {:already_started, pid}} ->
        Logger.info("TEST: Projection already started with pid #{inspect(pid)}")
        :ok
    end

    Process.sleep(200)
    Logger.info("TEST: rebuild_projection complete")
  end

  setup do
    # Reset EventStore
    :ok = ConfigApi.EventStoreCase.reset_eventstore!()

    # Stop and restart projection to rebuild from clean state
    case Process.whereis(@projection_name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end

    Process.sleep(50)

    # Clean up ETS
    try do
      :ets.delete(:config_state_projection)
    rescue
      ArgumentError -> :ok
    end

    # Start fresh projection (may already be started by application)
    case ConfigStateProjection.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Give projection time to initialize
    Process.sleep(100)

    :ok
  end

  # Most tests moved to config_store_cqrs_unit_test.exs
  # Only keep critical integration tests that verify full CQRS flow

  describe "event sourcing workflow" do
    test "complete CQRS flow: write → event → projection → read" do
      # Write (command)
      assert {:ok, "secret"} = ConfigStoreCQRS.put("api_key", "secret")

      # Event is in EventStore
      assert {:ok, history} = ConfigStoreCQRS.get_history("api_key")
      assert length(history) == 1

      # Rebuild projection from events
      rebuild_projection()

      # Read from projection
      assert {:ok, "secret"} = ConfigStoreCQRS.get("api_key")
    end

    test "projection rebuilds correctly after restart" do
      # Add some configs
      ConfigStoreCQRS.put("key1", "value1")
      ConfigStoreCQRS.put("key2", "value2")

      # Rebuild projection from events
      rebuild_projection()

      # Data should be there
      assert {:ok, "value1"} = ConfigStoreCQRS.get("key1")
      assert {:ok, "value2"} = ConfigStoreCQRS.get("key2")
    end

    test "handles resurrection (delete then recreate)" do
      ConfigStoreCQRS.put("key", "original")
      rebuild_projection()

      ConfigStoreCQRS.delete("key")
      rebuild_projection()

      ConfigStoreCQRS.put("key", "resurrected")
      rebuild_projection()

      assert {:ok, "resurrected"} = ConfigStoreCQRS.get("key")
    end
  end
end
