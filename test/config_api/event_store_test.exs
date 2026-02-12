defmodule ConfigApi.EventStoreTest do
  use ConfigApi.EventStoreCase, async: false

  alias ConfigApi.EventStore, as: ES

  # Define event type atoms so deserialization works
  _ = :TestEvent
  _ = :ResetTest

  describe "basic EventStore functionality" do
    test "can connect to EventStore" do
      # This test passes if setup succeeds
      assert true
    end

    test "can append events to a stream" do
      stream_name = "test_stream_#{System.unique_integer([:positive])}"

      event = %Elixir.EventStore.EventData{
        event_type: "TestEvent",
        data: %{test: "data", value: 42},
        metadata: %{created_by: "test"}
      }

      # Just verify we can append
      assert :ok = ES.append_to_stream(stream_name, :any_version, [event])
    end

    test "reading non-existent stream returns error" do
      stream_name = "non_existent_#{System.unique_integer([:positive])}"

      assert {:error, :stream_not_found} = ES.read_stream_forward(stream_name)
    end
  end

  describe "EventStore reset functionality" do
    test "reset function exists and can be called" do
      # Just verify reset works without errors
      assert :ok = reset_eventstore!()
    end
  end
end
