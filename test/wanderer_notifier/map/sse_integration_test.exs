defmodule WandererNotifier.Map.SSEIntegrationTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Map.SSEClient
  alias WandererNotifier.Map.SSESupervisor

  @moduletag :integration

  setup do
    # Start Registry for SSE client naming
    registry_pid =
      case Registry.start_link(keys: :unique, name: WandererNotifier.Registry) do
        {:ok, registry} -> registry
        {:error, {:already_started, registry}} -> registry
      end

    # Start HTTPoison/hackney
    HTTPoison.start()

    # Ensure MAP_URL is set for SSE connections
    map_url = Application.get_env(:wanderer_notifier, :map_url) || "https://example.com"
    Application.put_env(:wanderer_notifier, :map_url, map_url)

    on_exit(fn ->
      # Clean up any SSE clients that might still be running
      try do
        SSESupervisor.stop_sse_client("test-supervisor-map")
      catch
        _, _ -> :ok
      end
    end)

    {:ok, registry: registry_pid}
  end

  describe "SSE Integration" do
    test "SSE client can be configured and started" do
      # Test configuration
      opts = [
        map_id: "test-map-uuid-123",
        map_slug: "test-map",
        api_token: "test-token-123",
        events: ["add_system", "deleted_system", "system_metadata_changed"]
      ]

      # Test that SSE client can be started (will fail to connect but should handle gracefully)
      {:ok, pid} = SSEClient.start_link(opts)

      # Verify the client is running
      assert Process.alive?(pid)

      # Check initial status
      status = SSEClient.get_status("test-map")
      assert status in [:disconnected, :connecting, :connected]

      # Clean up
      SSEClient.stop("test-map")
    end

    test "SSE supervisor can manage clients" do
      # Test that supervisor can be started
      supervisor_pid =
        case SSESupervisor.start_link([]) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      # Verify supervisor is running
      assert Process.alive?(supervisor_pid)

      # Test client management
      opts = [
        map_id: "test-map-uuid-456",
        map_slug: "test-supervisor-map",
        api_token: "test-token-456",
        events: ["add_system"]
      ]

      # Start client via supervisor
      {:ok, client_pid} = SSESupervisor.start_sse_client(opts)
      assert Process.alive?(client_pid)

      # Check client status
      status = SSESupervisor.get_client_status()
      assert is_list(status)
      assert length(status) > 0

      # Stop client
      :ok = SSESupervisor.stop_sse_client("test-supervisor-map")

      # Clean up
      GenServer.stop(supervisor_pid)
    end
  end
end
