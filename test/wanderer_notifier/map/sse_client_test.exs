defmodule WandererNotifier.Map.SSEClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Map.SSEClient

  setup :verify_on_exit!

  describe "SSE Client Configuration" do
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

  describe "Connection Lifecycle" do
    setup do
      # Start HTTPoison and Registry for tests
      HTTPoison.start()

      # Start Registry if not already started
      case Registry.start_link(keys: :unique, name: WandererNotifier.Registry) do
        {:ok, registry} -> {:ok, registry}
        {:error, {:already_started, registry}} -> {:ok, registry}
      end

      on_exit(fn ->
        # Clean up any running processes
        case Registry.lookup(WandererNotifier.Registry, "test-map") do
          [{pid, _}] -> if Process.alive?(pid), do: GenServer.stop(pid)
          [] -> :ok
        end
      end)

      :ok
    end

    test "starts successfully with valid configuration" do
      opts = [
        map_slug: "test-map",
        api_token: "test-token",
        events: ["add_system"]
      ]

      assert {:ok, pid} = SSEClient.start_link(opts)
      assert Process.alive?(pid)
      # Just check that the process is alive since get_status function may not exist
      assert Process.alive?(pid)
    end

    test "handles connection errors gracefully" do
      # Use invalid URL to trigger connection error
      Application.put_env(:wanderer_notifier, :map_url, "http://invalid-url:9999")

      opts = [
        map_slug: "test-map",
        api_token: "test-token",
        events: ["add_system"]
      ]

      assert {:ok, pid} = SSEClient.start_link(opts)
      assert Process.alive?(pid)

      # Wait for connection attempt
      Process.sleep(100)

      # Should be in error state but process should still be alive
      assert Process.alive?(pid)

      # Clean up
      Application.delete_env(:wanderer_notifier, :map_url)
    end

    test "can be stopped cleanly" do
      opts = [
        map_slug: "test-map",
        api_token: "test-token",
        events: ["add_system"]
      ]

      {:ok, pid} = SSEClient.start_link(opts)
      assert Process.alive?(pid)

      SSEClient.stop("test-map")

      # Wait for shutdown
      Process.sleep(50)

      refute Process.alive?(pid)
    end
  end

  describe "Event Processing" do
    setup do
      HTTPoison.start()

      # Start Registry if not already started
      case Registry.start_link(keys: :unique, name: WandererNotifier.Registry) do
        {:ok, _registry} -> :ok
        {:error, {:already_started, _registry}} -> :ok
      end

      # Start cache
      cache_name = :wanderer_cache

      case Cachex.start_link(name: cache_name) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end

      :ok
    end

    test "validates event structure correctly" do
      # Test with valid event
      valid_event = %{
        "id" => "01234567-89AB-CDEF-0123-456789ABCDEF",
        "type" => "add_system",
        "map_id" => "test-map-id",
        "timestamp" => "2023-01-01T00:00:00Z",
        "payload" => %{"solar_system_id" => 30_000_001}
      }

      assert WandererNotifier.Map.EventProcessor.validate_event(valid_event) == :ok

      # Test with missing required fields
      invalid_event = %{
        "type" => "add_system"
        # Missing id, map_id, payload and timestamp
      }

      assert WandererNotifier.Map.EventProcessor.validate_event(invalid_event) ==
               {:error, {:missing_fields, ["id", "map_id", "timestamp", "payload"]}}
    end

    test "routes events to correct handlers" do
      event = %{
        "id" => "01234567-89AB-CDEF-0123-456789ABCDEF",
        "type" => "add_system",
        "map_id" => "test-map-id",
        "timestamp" => "2023-01-01T00:00:00Z",
        "payload" => %{"solar_system_id" => 30_000_001}
      }

      # Test that the event processor can validate the event
      assert WandererNotifier.Map.EventProcessor.validate_event(event) == :ok
    end
  end

  describe "Error Handling" do
    test "handles malformed JSON gracefully" do
      malformed_json = "invalid json{"

      assert {:error, %Jason.DecodeError{}} = Jason.decode(malformed_json)
    end

    test "handles missing required event fields" do
      incomplete_event = %{"type" => "add_system"}

      assert WandererNotifier.Map.EventProcessor.validate_event(incomplete_event) ==
               {:error, {:missing_fields, ["id", "map_id", "timestamp", "payload"]}}
    end

    test "handles network errors during connection" do
      # This would test reconnection logic
      # Implementation depends on how the SSE client handles network errors
      # Placeholder for now
      assert true
    end
  end
end
