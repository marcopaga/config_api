defmodule ConfigApi.ConfigStoreCQRSUnitTest do
  @moduledoc """
  Unit tests for ConfigStoreCQRS using dependency injection.

  These tests run WITHOUT database/EventStore - using simple stub modules
  for fast feedback (2-3 seconds vs 60+ seconds for integration tests).

  Tests focus on the CQRS query logic with mocked projection.
  """
  # Must be false because ProjectionStub uses named Agent
  use ExUnit.Case, async: false

  alias ConfigApi.ConfigStoreCQRS
  alias ConfigApi.Test.Stubs.ProjectionStub

  setup do
    # Stop any existing Agent
    if Process.whereis(ProjectionStub) do
      try do
        Agent.stop(ProjectionStub)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(10)
    end

    # Start stub projection with predefined test data
    {:ok, _pid} =
      ProjectionStub.start_link(%{
        "existing_key" => "existing_value",
        "api_key" => "secret123",
        "database_url" => "postgres://localhost"
      })

    on_exit(fn ->
      # Safely stop the Agent if it exists
      if Process.whereis(ProjectionStub) do
        try do
          Agent.stop(ProjectionStub)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "get/2 with projection stub" do
    test "returns value from projection for existing key" do
      assert {:ok, "existing_value"} = ConfigStoreCQRS.get("existing_key", ProjectionStub)
    end

    test "returns error for non-existent key" do
      assert {:error, :not_found} = ConfigStoreCQRS.get("non_existent", ProjectionStub)
    end

    test "returns specific value for api_key" do
      assert {:ok, "secret123"} = ConfigStoreCQRS.get("api_key", ProjectionStub)
    end

    test "returns specific value for database_url" do
      assert {:ok, "postgres://localhost"} = ConfigStoreCQRS.get("database_url", ProjectionStub)
    end

    test "handles empty string as key" do
      ProjectionStub.put_config("", "empty_key_value")
      assert {:ok, "empty_key_value"} = ConfigStoreCQRS.get("", ProjectionStub)
    end

    test "handles keys with special characters" do
      ProjectionStub.put_config("key:with:colons", "special_value")
      assert {:ok, "special_value"} = ConfigStoreCQRS.get("key:with:colons", ProjectionStub)
    end

    test "handles very long keys" do
      long_key = String.duplicate("a", 1000)
      ProjectionStub.put_config(long_key, "long_key_value")
      assert {:ok, "long_key_value"} = ConfigStoreCQRS.get(long_key, ProjectionStub)
    end

    test "handles unicode in keys" do
      ProjectionStub.put_config("emoji_🔥_key", "unicode_value")
      assert {:ok, "unicode_value"} = ConfigStoreCQRS.get("emoji_🔥_key", ProjectionStub)
    end
  end

  describe "all/1 with projection stub" do
    test "returns all configs from projection" do
      configs = ConfigStoreCQRS.all(ProjectionStub)

      assert length(configs) == 3
      assert %{name: "existing_key", value: "existing_value"} in configs
      assert %{name: "api_key", value: "secret123"} in configs
      assert %{name: "database_url", value: "postgres://localhost"} in configs
    end

    test "returns empty list when no configs" do
      # Clear all configs
      ProjectionStub.clear_all()

      assert [] = ConfigStoreCQRS.all(ProjectionStub)
    end

    test "returns updated list after adding config" do
      ProjectionStub.put_config("new_key", "new_value")

      configs = ConfigStoreCQRS.all(ProjectionStub)
      assert length(configs) == 4
      assert %{name: "new_key", value: "new_value"} in configs
    end

    test "returns correct list after deleting config" do
      ProjectionStub.delete_config("api_key")

      configs = ConfigStoreCQRS.all(ProjectionStub)
      assert length(configs) == 2
      refute Enum.any?(configs, &(&1.name == "api_key"))
    end

    test "handles projection with many configs" do
      # Add 100 configs
      for i <- 1..100 do
        ProjectionStub.put_config("key_#{i}", "value_#{i}")
      end

      configs = ConfigStoreCQRS.all(ProjectionStub)
      # 3 initial + 100 new
      assert length(configs) == 103
    end
  end

  describe "query performance characteristics" do
    test "get is fast with stub projection" do
      # This test demonstrates the performance benefit
      {time, result} =
        :timer.tc(fn ->
          ConfigStoreCQRS.get("api_key", ProjectionStub)
        end)

      assert {:ok, "secret123"} = result

      # Should be much faster than database queries (typically sub-millisecond, but CI can be slower)
      assert time < 10_000, "get/2 should be fast with stub (was #{time}μs)"
    end

    test "all is fast with stub projection" do
      {time, result} =
        :timer.tc(fn ->
          ConfigStoreCQRS.all(ProjectionStub)
        end)

      assert length(result) == 3

      # Should be much faster than database queries (typically sub-millisecond, but CI can be slower)
      assert time < 10_000, "all/1 should be fast with stub (was #{time}μs)"
    end
  end

  describe "projection interface consistency" do
    test "stub projection matches real projection interface for get_config" do
      # This test ensures our stub matches the real projection's behavior
      assert {:ok, _value} = ProjectionStub.get_config("existing_key")
      assert {:error, :not_found} = ProjectionStub.get_config("missing")
    end

    test "stub projection matches real projection interface for get_all_configs" do
      result = ProjectionStub.get_all_configs()
      assert is_list(result)

      assert Enum.all?(result, fn item ->
               is_map(item) and Map.has_key?(item, :name) and Map.has_key?(item, :value)
             end)
    end
  end
end
