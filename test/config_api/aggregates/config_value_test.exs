defmodule ConfigApi.Aggregates.ConfigValueTest do
  use ExUnit.Case, async: true

  alias ConfigApi.Aggregates.ConfigValue
  alias ConfigApi.Events.{ConfigValueSet, ConfigValueDeleted}

  describe "new/0" do
    test "creates an empty aggregate" do
      aggregate = ConfigValue.new()

      assert aggregate.name == nil
      assert aggregate.value == nil
      assert aggregate.version == 0
      assert aggregate.deleted == false
    end
  end

  describe "set_value/3 command" do
    test "sets value on new aggregate" do
      aggregate = ConfigValue.new()

      assert {:ok, event, new_aggregate} = ConfigValue.set_value(aggregate, "api_key", "secret123")

      # Event is correct
      assert %ConfigValueSet{} = event
      assert event.config_name == "api_key"
      assert event.value == "secret123"
      assert event.old_value == nil

      # New aggregate has correct state
      assert new_aggregate.name == "api_key"
      assert new_aggregate.value == "secret123"
      assert new_aggregate.version == 1
      assert new_aggregate.deleted == false
    end

    test "updates existing value" do
      aggregate = %ConfigValue{
        name: "api_key",
        value: "old_secret",
        version: 1,
        deleted: false
      }

      assert {:ok, event, new_aggregate} = ConfigValue.set_value(aggregate, "api_key", "new_secret")

      # Event records old value
      assert event.old_value == "old_secret"
      assert event.value == "new_secret"

      # Aggregate is updated
      assert new_aggregate.value == "new_secret"
      assert new_aggregate.version == 2
    end

    test "increments version on each update" do
      aggregate = ConfigValue.new()

      {:ok, _, agg1} = ConfigValue.set_value(aggregate, "key", "value1")
      assert agg1.version == 1

      {:ok, _, agg2} = ConfigValue.set_value(agg1, "key", "value2")
      assert agg2.version == 2

      {:ok, _, agg3} = ConfigValue.set_value(agg2, "key", "value3")
      assert agg3.version == 3
    end

    test "can set value on deleted config (resurrection)" do
      aggregate = %ConfigValue{
        name: "deleted_key",
        value: "old_value",
        version: 2,
        deleted: true
      }

      assert {:ok, event, new_agg} = ConfigValue.set_value(aggregate, "deleted_key", "new_value")
      assert event.config_name == "deleted_key"
      assert event.value == "new_value"
      assert event.old_value == "old_value"
      assert new_agg.deleted == false
      assert new_agg.value == "new_value"
      assert new_agg.version == 3
    end

    test "requires binary name and value" do
      aggregate = ConfigValue.new()

      assert {:error, :invalid_parameters} = ConfigValue.set_value(aggregate, :atom_name, "value")
      assert {:error, :invalid_parameters} = ConfigValue.set_value(aggregate, "name", 123)
      assert {:error, :invalid_parameters} = ConfigValue.set_value(aggregate, 123, 456)
    end

    test "original aggregate is not modified (immutable)" do
      original = ConfigValue.new()

      {:ok, _, _new} = ConfigValue.set_value(original, "key", "value")

      # Original is unchanged
      assert original.name == nil
      assert original.value == nil
      assert original.version == 0
    end
  end

  describe "delete_value/1 command" do
    test "deletes an existing config" do
      aggregate = %ConfigValue{
        name: "api_key",
        value: "secret123",
        version: 1,
        deleted: false
      }

      assert {:ok, event, new_aggregate} = ConfigValue.delete_value(aggregate)

      # Event is correct
      assert %ConfigValueDeleted{} = event
      assert event.config_name == "api_key"
      assert event.deleted_value == "secret123"

      # Aggregate is marked as deleted
      assert new_aggregate.deleted == true
      assert new_aggregate.version == 2
      # Name and value preserved for audit
      assert new_aggregate.name == "api_key"
      assert new_aggregate.value == "secret123"
    end

    test "cannot delete non-existent config" do
      aggregate = ConfigValue.new()

      assert {:error, :config_not_found} = ConfigValue.delete_value(aggregate)
    end

    test "cannot delete already deleted config" do
      aggregate = %ConfigValue{
        name: "key",
        value: "value",
        version: 2,
        deleted: true
      }

      assert {:error, :config_already_deleted} = ConfigValue.delete_value(aggregate)
    end

    test "increments version" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 5, deleted: false}

      {:ok, _, new_aggregate} = ConfigValue.delete_value(aggregate)

      assert new_aggregate.version == 6
    end
  end

  describe "apply_event/2 with ConfigValueSet" do
    test "applies event to empty aggregate" do
      aggregate = ConfigValue.new()
      event = ConfigValueSet.new("config1", "value1")

      result = ConfigValue.apply_event(aggregate, event)

      assert result.name == "config1"
      assert result.value == "value1"
      assert result.version == 1
      assert result.deleted == false
    end

    test "applies event to existing aggregate" do
      aggregate = %ConfigValue{name: "key", value: "old", version: 1, deleted: false}
      event = ConfigValueSet.new("key", "new", "old")

      result = ConfigValue.apply_event(aggregate, event)

      assert result.value == "new"
      assert result.version == 2
    end

    test "resurrects deleted config" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 2, deleted: true}
      event = ConfigValueSet.new("key", "resurrected")

      result = ConfigValue.apply_event(aggregate, event)

      assert result.deleted == false
      assert result.value == "resurrected"
      assert result.version == 3
    end
  end

  describe "apply_event/2 with ConfigValueDeleted" do
    test "marks aggregate as deleted" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 1, deleted: false}
      event = ConfigValueDeleted.new("key", "val")

      result = ConfigValue.apply_event(aggregate, event)

      assert result.deleted == true
      assert result.version == 2
      # Preserves name and value
      assert result.name == "key"
      assert result.value == "val"
    end
  end

  describe "replay_events/1" do
    test "replays empty event list" do
      aggregate = ConfigValue.replay_events([])

      assert aggregate.name == nil
      assert aggregate.version == 0
    end

    test "replays single event" do
      events = [ConfigValueSet.new("key1", "value1")]

      aggregate = ConfigValue.replay_events(events)

      assert aggregate.name == "key1"
      assert aggregate.value == "value1"
      assert aggregate.version == 1
    end

    test "replays multiple ConfigValueSet events in order" do
      events = [
        ConfigValueSet.new("key", "value1"),
        ConfigValueSet.new("key", "value2", "value1"),
        ConfigValueSet.new("key", "value3", "value2")
      ]

      aggregate = ConfigValue.replay_events(events)

      assert aggregate.value == "value3"
      assert aggregate.version == 3
    end

    test "replays set then delete events" do
      events = [
        ConfigValueSet.new("key", "value"),
        ConfigValueDeleted.new("key", "value")
      ]

      aggregate = ConfigValue.replay_events(events)

      assert aggregate.deleted == true
      assert aggregate.version == 2
    end

    test "replays delete then set (resurrection)" do
      events = [
        ConfigValueSet.new("key", "value1"),
        ConfigValueDeleted.new("key", "value1"),
        ConfigValueSet.new("key", "value2")
      ]

      aggregate = ConfigValue.replay_events(events)

      assert aggregate.deleted == false
      assert aggregate.value == "value2"
      assert aggregate.version == 3
    end

    test "replays complex event history" do
      events = [
        ConfigValueSet.new("api_key", "v1"),
        ConfigValueSet.new("api_key", "v2", "v1"),
        ConfigValueSet.new("api_key", "v3", "v2"),
        ConfigValueDeleted.new("api_key", "v3"),
        ConfigValueSet.new("api_key", "v4"),
        ConfigValueSet.new("api_key", "v5", "v4")
      ]

      aggregate = ConfigValue.replay_events(events)

      assert aggregate.value == "v5"
      assert aggregate.deleted == false
      assert aggregate.version == 6
    end
  end

  describe "current_value/1" do
    test "returns value for existing config" do
      aggregate = %ConfigValue{name: "key", value: "secret", version: 1, deleted: false}

      assert {:ok, "secret"} = ConfigValue.current_value(aggregate)
    end

    test "returns error for deleted config" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 2, deleted: true}

      assert {:error, :not_found} = ConfigValue.current_value(aggregate)
    end

    test "returns error for empty aggregate" do
      aggregate = ConfigValue.new()

      assert {:error, :not_found} = ConfigValue.current_value(aggregate)
    end
  end

  describe "exists?/1" do
    test "returns true for existing config" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 1, deleted: false}

      assert ConfigValue.exists?(aggregate) == true
    end

    test "returns false for deleted config" do
      aggregate = %ConfigValue{name: "key", value: "val", version: 2, deleted: true}

      assert ConfigValue.exists?(aggregate) == false
    end

    test "returns false for empty aggregate" do
      aggregate = ConfigValue.new()

      assert ConfigValue.exists?(aggregate) == false
    end
  end
end
