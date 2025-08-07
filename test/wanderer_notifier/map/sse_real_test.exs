defmodule WandererNotifier.Map.SSERealTest do
  use ExUnit.Case, async: false

  require Logger
  alias WandererNotifier.Map.SSEClient

  # This test is skipped by default as it requires real external credentials and network access.
  # It's useful for manual testing of SSE connectivity but not suitable for CI/automated testing.
  #
  # To enable this test:
  # 1. Set environment variables: MAP_ID, MAP_NAME, MAP_API_KEY
  # 2. Remove the @moduletag :skip line below
  # 3. Run: mix test test/wanderer_notifier/map/sse_real_test.exs
  @moduletag :skip

  describe "Real SSE Connection" do
    test "can attempt to connect to actual SSE endpoint" do
      # Start HTTPoison
      HTTPoison.start()

      # Start Registry
      {:ok, _registry} = Registry.start_link(keys: :unique, name: WandererNotifier.Registry)

      # Test with actual configuration (requires real credentials)
      opts = [
        map_id: System.get_env("MAP_ID") || "your-real-map-id",
        map_slug: System.get_env("MAP_NAME") || "your-real-map-slug",
        api_token: System.get_env("MAP_API_KEY") || "your-real-api-token",
        events: ["add_system", "deleted_system", "system_metadata_changed"]
      ]

      # This test requires real external services and credentials
      {:ok, _pid} = SSEClient.start_link(opts)

      # Give it time to attempt connection
      Process.sleep(5000)

      # Check status
      map_slug = System.get_env("MAP_NAME") || "your-real-map-slug"
      status = SSEClient.get_status(map_slug)
      Logger.info("SSE Connection Status: #{status}")

      # Clean up
      SSEClient.stop(map_slug)
    end
  end
end
