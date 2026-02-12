defmodule ConfigApi.Spec.EventSchemaTest do
  @moduledoc """
  Tests that validate domain events against JSON Schema specifications.

  These tests ensure that the Elixir event structs match the JSON schemas
  defined in spec/json-schema/events/.
  """
  use ExUnit.Case, async: true

  alias ConfigApi.Events.ConfigValueSet
  alias ConfigApi.Events.ConfigValueDeleted

  # Helper to load and parse JSON schema
  defp load_schema(schema_path) do
    File.read!(schema_path)
    |> Jason.decode!()
    |> ExJsonSchema.Schema.resolve()
  end

  describe "ConfigValueSet event schema validation" do
    setup do
      schema = load_schema("spec/json-schema/events/config-value-set.json")
      {:ok, schema: schema}
    end

    test "validates event with all required fields", %{schema: schema} do
      event = ConfigValueSet.new("api_key", "secret123", nil)
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates first set (old_value is null)", %{schema: schema} do
      event = ConfigValueSet.new("api_key", "secret123", nil)
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
      assert is_nil(event_map["old_value"])
    end

    test "validates update (old_value is present)", %{schema: schema} do
      event = ConfigValueSet.new("api_key", "new_secret", "old_secret")
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
      assert event_map["old_value"] == "old_secret"
    end

    test "validates empty string value", %{schema: schema} do
      event = ConfigValueSet.new("optional", "", "previous")
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
      assert event_map["value"] == ""
    end

    test "validates unicode value", %{schema: schema} do
      event = ConfigValueSet.new("welcome", "你好世界 🚀", nil)
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates resurrection (old_value null after delete)", %{schema: schema} do
      # After deletion, setting again has old_value as nil
      event = ConfigValueSet.new("api_key", "resurrected", nil)
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates timestamp format", %{schema: schema} do
      event = ConfigValueSet.new("key", "value", nil)
      event_map = event_to_map(event)

      # Timestamp should be ISO8601 format
      assert Map.has_key?(event_map, "timestamp")
      assert is_binary(event_map["timestamp"])
      # Should be parseable as DateTime
      assert {:ok, _, _} = DateTime.from_iso8601(event_map["timestamp"])

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "event has correct structure", %{schema: schema} do
      event = ConfigValueSet.new("key", "value", nil)
      event_map = event_to_map(event)

      # Check required fields
      assert Map.has_key?(event_map, "config_name")
      assert Map.has_key?(event_map, "value")
      assert Map.has_key?(event_map, "timestamp")

      # Check types
      assert is_binary(event_map["config_name"])
      assert is_binary(event_map["value"])
      assert is_binary(event_map["timestamp"])

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end
  end

  describe "ConfigValueDeleted event schema validation" do
    setup do
      schema = load_schema("spec/json-schema/events/config-value-deleted.json")
      {:ok, schema: schema}
    end

    test "validates event with all required fields", %{schema: schema} do
      event = ConfigValueDeleted.new("api_key", "secret123")
      event_map = event_to_map(event)

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates deleted_value is preserved", %{schema: schema} do
      event = ConfigValueDeleted.new("api_key", "secret123")
      event_map = event_to_map(event)

      assert event_map["deleted_value"] == "secret123"
      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates empty string deleted_value", %{schema: schema} do
      event = ConfigValueDeleted.new("optional", "")
      event_map = event_to_map(event)

      assert event_map["deleted_value"] == ""
      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "validates timestamp format", %{schema: schema} do
      event = ConfigValueDeleted.new("key", "value")
      event_map = event_to_map(event)

      # Timestamp should be ISO8601 format
      assert Map.has_key?(event_map, "timestamp")
      assert is_binary(event_map["timestamp"])
      # Should be parseable as DateTime
      assert {:ok, _, _} = DateTime.from_iso8601(event_map["timestamp"])

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end

    test "event has correct structure", %{schema: schema} do
      event = ConfigValueDeleted.new("key", "value")
      event_map = event_to_map(event)

      # Check required fields
      assert Map.has_key?(event_map, "config_name")
      assert Map.has_key?(event_map, "deleted_value")
      assert Map.has_key?(event_map, "timestamp")

      # Check types
      assert is_binary(event_map["config_name"])
      assert is_binary(event_map["deleted_value"])
      assert is_binary(event_map["timestamp"])

      assert :ok == ExJsonSchema.Validator.validate(schema, event_map)
    end
  end

  describe "Event JSON encoding/decoding" do
    test "ConfigValueSet encodes to valid JSON" do
      event = ConfigValueSet.new("api_key", "secret123", nil)

      # Encode to JSON
      json = Jason.encode!(event)
      assert is_binary(json)

      # Decode back
      decoded = Jason.decode!(json, keys: :atoms)
      assert decoded.config_name == "api_key"
      assert decoded.value == "secret123"
      assert is_nil(decoded.old_value)
    end

    test "ConfigValueDeleted encodes to valid JSON" do
      event = ConfigValueDeleted.new("api_key", "secret123")

      # Encode to JSON
      json = Jason.encode!(event)
      assert is_binary(json)

      # Decode back
      decoded = Jason.decode!(json, keys: :atoms)
      assert decoded.config_name == "api_key"
      assert decoded.deleted_value == "secret123"
    end
  end

  describe "Schema metadata validation" do
    test "ConfigValueSet schema has correct metadata" do
      schema_json = File.read!("spec/json-schema/events/config-value-set.json")
      schema = Jason.decode!(schema_json)

      # Validate schema metadata (using draft-07 for ex_json_schema compatibility)
      assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
      assert Map.has_key?(schema, "$id")
      assert schema["title"] == "ConfigValueSet Event"
      assert Map.has_key?(schema, "description")

      # Validate custom extensions
      assert schema["x-elixir-module"] == "ConfigApi.Events.ConfigValueSet"
      assert schema["x-aggregate"] == "ConfigValue"
      assert schema["x-cqrs-pattern"] == "event"
    end

    test "ConfigValueDeleted schema has correct metadata" do
      schema_json = File.read!("spec/json-schema/events/config-value-deleted.json")
      schema = Jason.decode!(schema_json)

      # Validate schema metadata (using draft-07 for ex_json_schema compatibility)
      assert schema["$schema"] == "http://json-schema.org/draft-07/schema#"
      assert Map.has_key?(schema, "$id")
      assert schema["title"] == "ConfigValueDeleted Event"
      assert Map.has_key?(schema, "description")

      # Validate custom extensions
      assert schema["x-elixir-module"] == "ConfigApi.Events.ConfigValueDeleted"
      assert schema["x-aggregate"] == "ConfigValue"
      assert schema["x-cqrs-pattern"] == "event"
      assert schema["x-creates-tombstone"] == true
    end
  end

  # Helper function to convert event struct to map for JSON schema validation
  defp event_to_map(%ConfigValueSet{} = event) do
    %{
      "config_name" => event.config_name,
      "value" => event.value,
      "old_value" => event.old_value,
      "timestamp" => DateTime.to_iso8601(event.timestamp)
    }
  end

  defp event_to_map(%ConfigValueDeleted{} = event) do
    %{
      "config_name" => event.config_name,
      "deleted_value" => event.deleted_value,
      "timestamp" => DateTime.to_iso8601(event.timestamp)
    }
  end
end
