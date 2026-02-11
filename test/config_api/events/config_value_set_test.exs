defmodule ConfigApi.Events.ConfigValueSetTest do
  use ExUnit.Case, async: true

  alias ConfigApi.Events.ConfigValueSet

  describe "new/3" do
    test "creates event with all required fields" do
      event = ConfigValueSet.new("api_key", "secret123", "old_secret")

      assert event.config_name == "api_key"
      assert event.value == "secret123"
      assert event.old_value == "old_secret"
      assert %DateTime{} = event.timestamp
    end

    test "creates event with nil old_value for new configs" do
      event = ConfigValueSet.new("new_config", "value123")

      assert event.config_name == "new_config"
      assert event.value == "value123"
      assert event.old_value == nil
      assert %DateTime{} = event.timestamp
    end

    test "timestamp is in UTC" do
      event = ConfigValueSet.new("test", "value")

      assert event.timestamp.time_zone == "Etc/UTC"
    end

    test "timestamp is recent" do
      before = DateTime.utc_now()
      event = ConfigValueSet.new("test", "value")
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(event.timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "JSON serialization" do
    test "can encode to JSON" do
      event = ConfigValueSet.new("test_key", "test_value", "old")

      {:ok, json} = Jason.encode(event)

      assert is_binary(json)
      assert String.contains?(json, "test_key")
      assert String.contains?(json, "test_value")
      assert String.contains?(json, "old")
    end

    test "can decode from JSON" do
      event = ConfigValueSet.new("test_key", "test_value", "old")
      {:ok, json} = Jason.encode(event)

      {:ok, decoded} = Jason.decode(json)

      assert decoded["config_name"] == "test_key"
      assert decoded["value"] == "test_value"
      assert decoded["old_value"] == "old"
      assert is_binary(decoded["timestamp"])
    end

    test "serialization preserves nil old_value" do
      event = ConfigValueSet.new("test", "value")
      {:ok, json} = Jason.encode(event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["old_value"] == nil
    end
  end

  describe "struct validation" do
    test "struct has correct type definition" do
      event = ConfigValueSet.new("test", "value")

      assert is_struct(event, ConfigValueSet)
    end

    test "struct is immutable" do
      event = ConfigValueSet.new("test", "value")

      # Trying to pattern match and update creates a new struct
      updated = %{event | value: "new_value"}

      assert event.value == "value"
      assert updated.value == "new_value"
      # They are different structs
      refute event == updated
    end
  end
end
