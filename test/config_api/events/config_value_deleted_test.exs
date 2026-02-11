defmodule ConfigApi.Events.ConfigValueDeletedTest do
  use ExUnit.Case, async: true

  alias ConfigApi.Events.ConfigValueDeleted

  describe "new/2" do
    test "creates event with all required fields" do
      event = ConfigValueDeleted.new("api_key", "deleted_secret")

      assert event.config_name == "api_key"
      assert event.deleted_value == "deleted_secret"
      assert %DateTime{} = event.timestamp
    end

    test "timestamp is in UTC" do
      event = ConfigValueDeleted.new("test", "value")

      assert event.timestamp.time_zone == "Etc/UTC"
    end

    test "timestamp is recent" do
      before = DateTime.utc_now()
      event = ConfigValueDeleted.new("test", "value")
      after_time = DateTime.utc_now()

      assert DateTime.compare(event.timestamp, before) in [:gt, :eq]
      assert DateTime.compare(event.timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "JSON serialization" do
    test "can encode to JSON" do
      event = ConfigValueDeleted.new("test_key", "deleted_value")

      {:ok, json} = Jason.encode(event)

      assert is_binary(json)
      assert String.contains?(json, "test_key")
      assert String.contains?(json, "deleted_value")
    end

    test "can decode from JSON" do
      event = ConfigValueDeleted.new("test_key", "deleted_value")
      {:ok, json} = Jason.encode(event)

      {:ok, decoded} = Jason.decode(json)

      assert decoded["config_name"] == "test_key"
      assert decoded["deleted_value"] == "deleted_value"
      assert is_binary(decoded["timestamp"])
    end

    test "round-trip serialization preserves data" do
      original_event = ConfigValueDeleted.new("config_name", "value")
      {:ok, json} = Jason.encode(original_event)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["config_name"] == original_event.config_name
      assert decoded["deleted_value"] == original_event.deleted_value
    end
  end

  describe "struct validation" do
    test "struct has correct type definition" do
      event = ConfigValueDeleted.new("test", "value")

      assert is_struct(event, ConfigValueDeleted)
    end

    test "struct is immutable" do
      event = ConfigValueDeleted.new("test", "value")

      # Trying to pattern match and update creates a new struct
      updated = %{event | deleted_value: "new_value"}

      assert event.deleted_value == "value"
      assert updated.deleted_value == "new_value"
      # They are different structs
      refute event == updated
    end
  end
end
