defmodule WandererNotifier.Map.SSERealTest do
  use ExUnit.Case, async: false

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
        map_id: "your-real-map-id",
        map_slug: "your-real-map-slug",
        api_token: "your-real-api-token",
        events: ["add_system", "deleted_system", "system_metadata_changed"]
      ]

      # This test is skipped by default since it requires real credentials
      # To run: set up your real map credentials and remove @moduletag :skip
      {:ok, pid} = SSEClient.start_link(opts)

      # Give it time to attempt connection
      Process.sleep(5000)

      # Check status
      status = SSEClient.get_status("your-real-map-slug")
      Logger.info("SSE Connection Status: #{status}")

      # Clean up
      SSEClient.stop("your-real-map-slug")
    end
  end
end
