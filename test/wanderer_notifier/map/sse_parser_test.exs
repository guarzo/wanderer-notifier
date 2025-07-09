defmodule WandererNotifier.Map.SSEParserTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.SSEParser

  describe "parse_chunk/1" do
    test "parses a simple SSE chunk" do
      chunk = """
      event: add_system
      data: {"id": "123", "name": "Test System"}
      id: event-123

      """

      assert {:ok, [event]} = SSEParser.parse_chunk(chunk)
      assert event["type"] == "add_system"
      assert event["id"] == "event-123"
      assert event["name"] == "Test System"
    end

    test "parses multiple events in a chunk" do
      chunk = """
      event: add_system
      data: {"id": "123", "name": "System 1"}
      id: event-123

      event: deleted_system
      data: {"id": "456", "name": "System 2"}
      id: event-456

      """

      assert {:ok, events} = SSEParser.parse_chunk(chunk)
      assert length(events) == 2
      assert Enum.at(events, 0)["type"] == "add_system"
      assert Enum.at(events, 1)["type"] == "deleted_system"
    end

    test "handles malformed JSON gracefully" do
      chunk = """
      event: add_system
      data: {invalid json}
      id: event-123

      """

      assert {:ok, []} = SSEParser.parse_chunk(chunk)
    end

    test "handles empty chunks" do
      assert {:ok, []} = SSEParser.parse_chunk("")
      assert {:ok, []} = SSEParser.parse_chunk("\n\n")
    end
  end

  describe "parse_single_event/1" do
    test "parses a single event string" do
      event_str = """
      event: add_system
      data: {"id": "123", "name": "Test System"}
      id: event-123
      """

      assert {:ok, event} = SSEParser.parse_single_event(event_str)
      assert event["type"] == "add_system"
      assert event["id"] == "event-123"
      assert event["name"] == "Test System"
    end

    test "handles missing data" do
      event_str = """
      event: add_system
      id: event-123
      """

      assert {:error, :no_data} = SSEParser.parse_single_event(event_str)
    end
  end
end
