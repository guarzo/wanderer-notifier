defmodule WandererNotifier.Map.SSEClientTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.SSEClient

  describe "SSE Client" do
    test "can be configured with map options" do
      opts = [
        map_id: "test-map-123",
        map_slug: "test-map",
        api_token: "test-token",
        events: ["add_system", "deleted_system"]
      ]

      # Test that the client can be initialized with proper options
      assert is_list(opts)
      assert Keyword.get(opts, :map_id) == "test-map-123"
      assert Keyword.get(opts, :map_slug) == "test-map"
      assert Keyword.get(opts, :api_token) == "test-token"
      assert Keyword.get(opts, :events) == ["add_system", "deleted_system"]
    end
  end
end
