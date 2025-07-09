defmodule WandererNotifier.Map.EventProcessorTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.EventProcessor

  describe "EventProcessor" do
    test "validates event structure" do
      valid_event = %{
        "id" => "test-123",
        "type" => "add_system",
        "map_id" => "map-123",
        "timestamp" => "2024-01-01T12:00:00Z",
        "payload" => %{"test" => "data"}
      }

      assert EventProcessor.validate_event(valid_event) == :ok
    end

    test "rejects invalid event structure" do
      invalid_event = %{
        "id" => "test-123",
        "type" => "add_system"
        # Missing required fields
      }

      assert {:error, {:missing_fields, _}} = EventProcessor.validate_event(invalid_event)
    end

    test "extracts event metadata" do
      event = %{
        "id" => "test-123",
        "type" => "add_system",
        "map_id" => "map-123",
        "timestamp" => "2024-01-01T12:00:00Z",
        "payload" => %{"system_id" => "sys-123", "name" => "Test System"}
      }

      metadata = EventProcessor.extract_event_metadata(event)

      assert metadata.id == "test-123"
      assert metadata.type == "add_system"
      assert metadata.map_id == "map-123"
      assert metadata.timestamp == "2024-01-01T12:00:00Z"
      assert metadata.payload_keys == ["name", "system_id"]
    end

    test "processes different event categories correctly" do
      # Test unknown event (returns :ok for ignored events)
      unknown_event = %{
        "id" => "test-789",
        "type" => "future_event_type",
        "map_id" => "map-123",
        "timestamp" => "2024-01-01T12:00:00Z",
        "payload" => %{}
      }

      assert EventProcessor.process_event(unknown_event, "test-map") == :ok

      # Test special event (connected)
      connected_event = %{
        "id" => "test-conn",
        "type" => "connected",
        "map_id" => "map-123",
        "timestamp" => "2024-01-01T12:00:00Z",
        "payload" => %{},
        "server_time" => "2024-01-01T12:00:00Z"
      }

      assert EventProcessor.process_event(connected_event, "test-map") == :ok
    end
  end
end
