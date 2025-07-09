defmodule WandererNotifier.Map.SSERealTest do
  use ExUnit.Case, async: false

  require Logger
  alias WandererNotifier.Map.SSEClient

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

      # This test is skipped by default since it requires real credentials
      # To run: set up your real map credentials and remove @moduletag :skip
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
