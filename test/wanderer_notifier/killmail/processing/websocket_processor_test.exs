defmodule WandererNotifier.Killmail.Processing.WebsocketProcessorTest do
  use ExUnit.Case, async: false

  import Mox

  alias WandererNotifier.Killmail.Core.{Context, Data, MockValidator}
  alias WandererNotifier.Killmail.Processing.WebsocketProcessor

  alias WandererNotifier.Killmail.Processing.{
    MockCache,
    MockEnrichment,
    MockNotificationDeterminer,
    MockNotification,
    MockPersistence,
    MockProcessor
  }

  # Use a setup block to verify and set expectations
  setup :verify_on_exit!

  # Set up helper functions
  setup do
    # Configure application to use our mocks during tests
    Application.put_env(:wanderer_notifier, :validator, MockValidator)
    Application.put_env(:wanderer_notifier, :enrichment, MockEnrichment)
    Application.put_env(:wanderer_notifier, :cache, MockCache)
    Application.put_env(:wanderer_notifier, :persistence_module, MockPersistence)
    Application.put_env(:wanderer_notifier, :notification_determiner, MockNotificationDeterminer)
    Application.put_env(:wanderer_notifier, :notification, MockNotification)
    Application.put_env(:wanderer_notifier, :processor, MockProcessor)

    # Start with a clean state
    state = %{processed: 0, errors: 0}

    # Mock the ZKillClient to return test data
    stub_zkill_client()

    {:ok, %{state: state}}
  end

  describe "process_zkill_message/2" do
    test "processes a valid killmail package", %{state: state} do
      # Create a valid test message with a package
      message = %{
        "package" => %{
          "killID" => 12345,
          "hash" => "abc123"
        }
      }

      # Set up a simple stub for the processor to return success
      # This avoids trying to verify all the internal steps
      WandererNotifier.Killmail.Processing.MockProcessor
      |> stub(:process_killmail, fn _killmail, _context ->
        {:ok, %{"killmail_id" => 12345}}
      end)

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_zkill_message(message, state)

      # Verify state was updated
      assert new_state.processed == 1
      assert new_state.errors == 0
    end

    test "handles a message without a killmail package", %{state: state} do
      # Create a message without a package
      message = %{"action" => "tqStatus", "tqStatus" => %{"players" => 22000}}

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_zkill_message(message, state)

      # Verify state was unchanged
      assert new_state == state
    end

    test "handles a message with invalid package data", %{state: state} do
      # Create a message with incomplete package data
      message = %{
        "package" => %{
          "killID" => 12345
          # Missing hash
        }
      }

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_zkill_message(message, state)

      # Verify errors increased
      assert new_state.errors == 1
      assert new_state.processed == 0
    end
  end

  describe "handle_message/2" do
    test "handles a JSON string message", %{state: state} do
      # Create a valid JSON message
      json = ~s({"package": {"killID": 12345, "hash": "abc123"}})

      # Set up a simple stub for the processor to return success
      WandererNotifier.Killmail.Processing.MockProcessor
      |> stub(:process_killmail, fn _killmail, _context ->
        {:ok, %{"killmail_id" => 12345}}
      end)

      # Call the function
      {:ok, new_state} = WebsocketProcessor.handle_message(json, state)

      # Verify state was updated
      assert new_state.processed == 1
    end

    test "handles a map message", %{state: state} do
      # Create a map message
      message = %{
        "killID" => 12345,
        "hash" => "abc123"
      }

      # Set up a simple stub for the processor to return success
      WandererNotifier.Killmail.Processing.MockProcessor
      |> stub(:process_killmail, fn _killmail, _context ->
        {:ok, %{"killmail_id" => 12345}}
      end)

      # Call the function
      {:ok, new_state} = WebsocketProcessor.handle_message(message, state)

      # Verify state was updated
      assert new_state.processed == 1
    end

    test "handles invalid JSON", %{state: state} do
      # Create invalid JSON
      invalid_json = ~s({"package": {"killID": 12345, "hash": "abc123")

      # Call the function
      {:ok, new_state} = WebsocketProcessor.handle_message(invalid_json, state)

      # Verify errors increased
      assert new_state.errors == 1
      assert new_state.processed == 0
    end

    test "handles non-string, non-map input", %{state: state} do
      # Try with an integer
      {:ok, new_state} = WebsocketProcessor.handle_message(42, state)

      # Verify errors increased
      assert new_state.errors == 1
      assert new_state.processed == 0
    end
  end

  describe "process_package/2" do
    test "processes a valid package", %{state: state} do
      # Create a valid package
      package = %{
        "killID" => 12345,
        "hash" => "abc123"
      }

      # Set up a simple stub for the processor to return success
      WandererNotifier.Killmail.Processing.MockProcessor
      |> stub(:process_killmail, fn _killmail, _context ->
        {:ok, %{"killmail_id" => 12345}}
      end)

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_package(package, state)

      # Verify state was updated
      assert new_state.processed == 1
    end

    test "handles a package with missing killID", %{state: state} do
      # Create package with missing killID
      package = %{
        "hash" => "abc123"
      }

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_package(package, state)

      # Verify errors increased
      assert new_state.errors == 1
    end

    test "handles a package with missing hash", %{state: state} do
      # Create package with missing hash
      package = %{
        "killID" => 12345
      }

      # Call the function
      {:ok, new_state} = WebsocketProcessor.process_package(package, state)

      # Verify errors increased
      assert new_state.errors == 1
    end
  end

  describe "process_kill/3" do
    test "processes a killmail using the processor" do
      # Set up a clear, specific test with minimal requirements
      # Set up expectations for the ZKillClient mock
      WandererNotifier.Api.ZKill.MockClient
      |> expect(:get_single_killmail, fn 12345 ->
        {:ok, %{"killmail_id" => 12345}}
      end)

      # Set up expectations for processor
      WandererNotifier.Killmail.Processing.MockProcessor
      |> expect(:process_killmail, fn killmail, _context ->
        assert Map.get(killmail, "killmail_id") == 12345
        {:ok, killmail}
      end)

      # Call the function with minimal context
      context = Context.new_realtime(nil, nil, :test)
      result = WebsocketProcessor.process_kill(12345, "abc123", context)

      # Verify result
      assert {:ok, _} = result
    end

    test "handles failure to fetch killmail" do
      # Set up expectations for the ZKillClient mock
      WandererNotifier.Api.ZKill.MockClient
      |> expect(:get_single_killmail, fn 12345 ->
        {:error, :not_found}
      end)

      # Call the function with an error response
      context = Context.new_realtime(nil, nil, :test)
      result = WebsocketProcessor.process_kill(12345, "abc123", context)

      # Verify result
      assert {:error, :not_found} = result
    end
  end

  # Helper functions for setting up mocks

  defp stub_zkill_client do
    # Stub the ZKillClient module
    Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Api.ZKill.MockClient)

    # Define the mock module
    unless Code.ensure_loaded?(WandererNotifier.Api.ZKill.MockClient) do
      Mox.defmock(WandererNotifier.Api.ZKill.MockClient,
        for: WandererNotifier.Api.ZKill.ClientBehaviour
      )
    end
  end

  defp expect_processor_to_handle_kill(kill_id, _hash) do
    # Set up expectations for ZKillClient mock directly in the tests that need it

    # Set up expectations for processor - make it a stub that just returns a successful result
    # without expectations on the internal pipeline
    WandererNotifier.Killmail.Processing.MockProcessor
    |> stub(:process_killmail, fn _killmail, _context ->
      {:ok, %{"killmail_id" => kill_id}}
    end)
  end

  defp expect_zkill_client_get_single_killmail(kill_id, return_value) do
    WandererNotifier.Api.ZKill.MockClient
    |> expect(:get_single_killmail, fn ^kill_id -> {:ok, return_value} end)
  end

  defp expect_zkill_client_get_single_killmail_error(kill_id, error) do
    WandererNotifier.Api.ZKill.MockClient
    |> expect(:get_single_killmail, fn ^kill_id -> {:error, error} end)
  end

  defp expect_processor_process_killmail(callback) do
    WandererNotifier.Killmail.Processing.MockProcessor
    |> expect(:process_killmail, callback)
  end
end
