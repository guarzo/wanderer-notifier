defmodule WandererNotifier.Map.EventProcessorTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.EventProcessor

  describe "EventProcessor" do
    test "validates event structure" do
      valid_event = %{
        "id" => "test-123",
        "type" => "add_system",
        "map_id" => "map-123",
        "ts" => "2024-01-01T12:00:00Z",
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
        "ts" => "2024-01-01T12:00:00Z",
        "payload" => %{"system_id" => "sys-123", "name" => "Test System"}
      }

      metadata = EventProcessor.extract_event_metadata(event)

      assert metadata.id == "test-123"
      assert metadata.type == "add_system"
      assert metadata.map_id == "map-123"
      assert metadata.timestamp == "2024-01-01T12:00:00Z"
      assert metadata.payload_keys == ["name", "system_id"]
    end
  end
end
