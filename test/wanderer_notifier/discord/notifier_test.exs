defmodule WandererNotifier.Discord.NotifierTest do
  use WandererNotifier.TestCase
  alias WandererNotifier.Discord.Notifier

  # Import mocks
  alias WandererNotifier.MockHTTPClient
  alias WandererNotifier.MockESIService

  # Setup with proper global mocks
  setup do
    # Make sure the right implementations are used for tests
    Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTPClient)
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.MockESIService)

    :ok
  end

  describe "send_message/2" do
    test "sends a plain text message to Discord" do
      # The function should pass in test environment without actually sending
      result = Notifier.send_message("Test message")
      assert result == :ok
    end

    test "correctly handles feature-specific messages" do
      result = Notifier.send_message("Test feature message", :test_feature)
      assert result == :ok
    end

    test "handles test kill notification requests" do
      # Mock the get_recent_kills function
      original_module = WandererNotifier.Services.KillProcessor

      if Code.ensure_loaded?(original_module) do
        # Only run this test if KillProcessor is loaded
        mock_kill = sample_killmail()

        # This is a workaround for mocking without mocking the entire module
        # We temporarily redefine the function
        try do
          :meck.new(WandererNotifier.Services.KillProcessor, [:passthrough])

          :meck.expect(WandererNotifier.Services.KillProcessor, :get_recent_kills, fn ->
            [mock_kill]
          end)

          result = Notifier.send_message("test kill notification")
          assert result == :ok
        after
          # Clean up the mock
          :meck.unload(WandererNotifier.Services.KillProcessor)
        end
      else
        # Skip this test if KillProcessor is not loaded
        :ok
      end
    end
  end

  describe "send_embed/4" do
    test "sends a basic embed message to Discord" do
      result = Notifier.send_embed("Test Title", "Test Description")
      assert result == :ok
    end

    test "includes URL and color when provided" do
      result =
        Notifier.send_embed("Test Title", "Test Description", "https://example.com", 0xFF0000)

      assert result == :ok
    end
  end

  describe "send_enriched_kill_embed/2" do
    test "handles sample killmail data" do
      kill_data = sample_killmail()

      # Mock the ESI service response for enrichment if needed
      MockESIService
      |> stub(:get_killmail, fn _kill_id, _hash ->
        {:ok, kill_data}
      end)

      result = Notifier.send_enriched_kill_embed(kill_data, kill_data["killmail_id"])
      assert result == :ok
    end

    test "handles minimal killmail and performs enrichment" do
      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{
          "hash" => "abc123"
        }
      }

      enriched_data = sample_killmail()

      # Stub the enrichment function to return our enriched data
      try do
        :meck.new(WandererNotifier.Api.ESI.Service, [:passthrough])

        :meck.expect(WandererNotifier.Api.ESI.Service, :get_killmail, fn _kill_id, _hash ->
          {:ok, enriched_data}
        end)

        result = Notifier.send_enriched_kill_embed(kill_data, kill_data["killmail_id"])
        assert result == :ok
      after
        # Clean up the mock
        :meck.unload(WandererNotifier.Api.ESI.Service)
      end
    end
  end

  describe "integration with http client" do
    test "actual API interaction in prod mode with mocked client" do
      # Temporarily set to prod for this test
      prev_env = Application.get_env(:wanderer_notifier, :env)
      Application.put_env(:wanderer_notifier, :env, :prod)

      # Mock the HTTP client for Discord API call
      MockHTTPClient
      |> expect(:post, fn _url, _payload, _headers, _opts ->
        {:ok, %{status_code: 200, body: "success"}}
      end)

      # Test the message sending
      result = Notifier.send_message("Test prod message")

      # Reset environment
      Application.put_env(:wanderer_notifier, :env, prev_env)

      assert result == :ok
    end
  end
end
