defmodule WandererNotifier.Killmail.ProcessorTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.{Processor, Context}
  alias WandererNotifier.ESI.ServiceMock
  alias WandererNotifier.Notifications.Determiner.KillMock

  # Define MockConfig for testing
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
  end

  # Define MockCache for the tests
  defmodule MockCache do
    def get("map:systems") do
      {:ok, [%{solar_system_id: "30000142", name: "Test System"}]}
    end

    def get("character:list") do
      {:ok, [%{character_id: "123", name: "Test Character"}]}
    end

    def get("tracked_character:" <> _) do
      {:error, :not_found}
    end

    def get(key) do
      if key == WandererNotifier.Cache.Keys.zkill_recent_kills() do
        {:ok,
         [
           %{
             "killmail_id" => "12345",
             "zkb" => %{"hash" => "test_hash"}
           }
         ]}
      else
        {:error, :not_found}
      end
    end

    def put(_key, _value), do: {:ok, :mock}
    def put(_key, _value, _ttl), do: {:ok, :mock}
    def delete(_key), do: {:ok, :mock}
    def clear(), do: {:ok, :mock}
    def get_and_update(_key, _fun), do: {:ok, :mock, :mock}
    def set(_key, _value, _opts), do: {:ok, :mock}
    def init_batch_logging(), do: :ok
    def get_recent_kills(), do: []
  end

  # Define MockDeduplication for the tests
  defmodule MockDeduplication do
    def check(:kill, _id), do: {:ok, :new}
    def clear_key(_type, _id), do: {:ok, :cleared}
  end

  # Define MockMetrics for the tests
  defmodule MockMetrics do
    def track_processing_start(_), do: :ok
    def track_processing_end(_, _), do: :ok
    def track_error(_, _), do: :ok
    def track_notification_sent(_, _), do: :ok
    def track_skipped_notification(_, _), do: :ok
    def track_zkill_webhook_received(), do: :ok
    def track_zkill_processing_status(_, _), do: :ok
  end

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Store original environment settings
    original_esi_service = Application.get_env(:wanderer_notifier, :esi_service)
    original_kill_determiner = Application.get_env(:wanderer_notifier, :kill_determiner)
    original_metrics = Application.get_env(:wanderer_notifier, :metrics)

    # Override with mocks for testing
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)

    Application.put_env(
      :wanderer_notifier,
      :kill_determiner,
      WandererNotifier.Notifications.Determiner.KillMock
    )

    Application.put_env(:wanderer_notifier, :metrics, MockMetrics)

    # Set up config module
    Application.put_env(:wanderer_notifier, :config, MockConfig)

    # Set up cache and deduplication modules
    Application.put_env(:wanderer_notifier, :cache_repo, MockCache)
    Application.put_env(:wanderer_notifier, :deduplication_module, MockDeduplication)

    # Set up metrics module
    Application.put_env(:wanderer_notifier, :killmail_metrics, MockMetrics)

    # Set up HTTP client mock
    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HttpClient.HttpoisonMock
    )

    # Add mock for HttpClient.HttpoisonMock.get/2
    WandererNotifier.HttpClient.HttpoisonMock
    |> stub(:get, fn url, _headers ->
      if String.contains?(url, "killmails/12345/test_hash") do
        {:ok,
         %{
           status_code: 200,
           body: %{
             "killmail_id" => 12_345,
             "victim" => %{
               "character_id" => 123,
               "corporation_id" => 456,
               "ship_type_id" => 789
             },
             "attackers" => [
               %{"character_id" => 321, "corporation_id" => 654, "ship_type_id" => 987}
             ],
             "solar_system_id" => 30_000_142,
             "killmail_time" => "2023-01-01T00:00:00Z"
           }
         }}
      else
        {:ok, %{status_code: 404, body: %{"error" => "Not found"}}}
      end
    end)

    # Set up default stubs
    ServiceMock
    |> stub(:get_system, fn system_id, _opts ->
      if system_id == 30_000_142 do
        {:ok, %{"name" => "Test System"}}
      else
        {:error, :not_found}
      end
    end)
    |> stub(:get_system, fn system_id ->
      if system_id == 30_000_142 do
        {:ok, %{"name" => "Test System"}}
      else
        {:error, :not_found}
      end
    end)
    |> stub(:get_killmail, fn _kill_id, _hash ->
      {:ok,
       %{
         "victim" => %{"character_id" => 123, "corporation_id" => 456, "ship_type_id" => 789},
         "attackers" => [%{"character_id" => 321, "corporation_id" => 654, "ship_type_id" => 987}],
         "solar_system_id" => 30_000_142
       }}
    end)
    |> stub(:get_character_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Character", "corporation_id" => 456}}
    end)
    |> stub(:get_corporation_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Corporation", "ticker" => "TSTC"}}
    end)
    |> stub(:get_type_info, fn _id, _opts ->
      {:ok, %{"name" => "Test Ship"}}
    end)

    # Mock KillDeterminer to allow notification by default
    KillMock
    |> stub(:should_notify?, fn _kill_data ->
      {:ok, %{should_notify: true}}
    end)

    on_exit(fn ->
      # Restore original settings
      if original_esi_service,
        do: Application.put_env(:wanderer_notifier, :esi_service, original_esi_service),
        else: Application.delete_env(:wanderer_notifier, :esi_service)

      if original_kill_determiner,
        do: Application.put_env(:wanderer_notifier, :kill_determiner, original_kill_determiner),
        else: Application.delete_env(:wanderer_notifier, :kill_determiner)

      if original_metrics,
        do: Application.put_env(:wanderer_notifier, :metrics, original_metrics),
        else: Application.delete_env(:wanderer_notifier, :metrics)
    end)

    :ok
  end

  describe "process_zkill_message/2" do
    test "successfully processes a valid ZKill message" do
      # Setup
      test_context = %Context{
        mode: %{mode: :test},
        character_id: 123,
        character_name: "Test Character",
        source: :test
      }

      valid_message =
        Jason.encode!(%{
          "killmail_id" => "12345",
          "zkb" => %{"hash" => "test_hash"},
          "solar_system_id" => 30_000_142
        })

      # We need to test that the message gets decoded
      # and the result matches what we expect
      result = Processor.process_zkill_message(valid_message, test_context)

      # Since process_kill_data returns {:ok, kill_id} and process_zkill_message calls it,
      # we expect the same return value
      assert match?({:ok, _}, result)
    end

    test "skips processing when notification is not needed" do
      # Setup
      test_context = %Context{
        mode: %{mode: :test},
        character_id: 123,
        character_name: "Test Character",
        source: :test
      }

      valid_message =
        Jason.encode!(%{
          "killmail_id" => "12345",
          "zkb" => %{"hash" => "test_hash"},
          "solar_system_id" => 30_000_142
        })

      # Override the default stub specifically for this test
      KillMock
      |> stub(:should_notify?, fn _kill_data ->
        {:ok, %{should_notify: false, reason: "Test skip reason"}}
      end)

      # Execute
      result = Processor.process_zkill_message(valid_message, test_context)

      # When should_notify? returns false, it skips processing and logs
      # But it doesn't actually return the state, it returns {:ok, :skipped}
      assert result == {:ok, :skipped}
    end

    test "handles invalid JSON message" do
      # Setup
      test_context = %Context{
        mode: %{mode: :test},
        character_id: 123,
        character_name: "Test Character",
        source: :test
      }

      invalid_message = "not valid json"

      # Execute
      result = Processor.process_zkill_message(invalid_message, test_context)

      # When there's an error, it should return the state (context)
      assert result == test_context
    end
  end

  # We'll use dependency injection pattern to test these functions
  defmodule TestPipeline do
    def process_killmail(kill_data, _ctx) do
      case kill_data do
        %{"zkb" => %{"hash" => "test_hash"}} ->
          {:ok,
           %WandererNotifier.Killmail.Killmail{
             killmail_id: "12345",
             victim_name: "Test Victim",
             system_name: "Test System",
             zkb: %{}
           }}

        %{"zkb" => %{"hash" => "skip_hash"}} ->
          {:ok, :skipped}

        %{"zkb" => %{"hash" => "error_hash"}} ->
          {:error, :test_error}
      end
    end
  end

  defmodule TestNotifier do
    def send_kill_notification(_killmail, _type, _opts) do
      {:ok, :sent}
    end
  end

  describe "process_kill_data/2" do
    test "successfully processes kill data" do
      # Setup - use dependency injection to test
      state = %{}
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Create a process pipeline module for testing
      defmodule TestPipeline do
        def process_killmail(data, _ctx) do
          case data do
            %{"zkb" => %{"hash" => "test_hash"}} ->
              {:ok,
               %WandererNotifier.Killmail.Killmail{
                 killmail_id: "12345",
                 victim_name: "Test Victim",
                 system_name: "Test System",
                 zkb: %{}
               }}

            _ ->
              {:error, :invalid_data}
          end
        end
      end

      # Create a test notification module
      defmodule TestNotification do
        def send_kill_notification(_killmail, _type, _opts) do
          {:ok, :sent}
        end
      end

      # Set up the processor with our test dependencies
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestPipeline)
      Application.put_env(:wanderer_notifier, :killmail_notification, TestNotification)

      # Execute
      result = Processor.process_kill_data(kill_data, test_context)

      # Cleanup
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)
      Application.delete_env(:wanderer_notifier, :killmail_notification)

      # Verify the result shows success
      assert match?({:ok, _}, result)
    end

    test "handles skipped kills" do
      # Setup - use dependency injection to test
      state = %{}
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "skip_hash"},
        "solar_system_id" => 30_000_142
      }

      # Create a process pipeline module for testing
      defmodule TestPipelineSkip do
        def process_killmail(data, _ctx) do
          case data do
            %{"zkb" => %{"hash" => "skip_hash"}} -> {:ok, :skipped}
            _ -> {:error, :invalid_data}
          end
        end
      end

      # Set up the processor with our test dependencies
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestPipelineSkip)

      # Execute
      result = Processor.process_kill_data(kill_data, test_context)

      # Cleanup
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)

      # Verify the result shows skipped
      assert match?({:ok, :skipped}, result)
    end

    test "handles processing errors" do
      # Setup - use dependency injection to test
      state = %{}
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "error_hash"},
        "solar_system_id" => 30_000_142
      }

      # Create a process pipeline module for testing
      defmodule TestPipelineError do
        def process_killmail(data, _ctx) do
          case data do
            %{"zkb" => %{"hash" => "error_hash"}} -> {:error, :test_error}
            _ -> {:ok, :valid}
          end
        end
      end

      # Set up the processor with our test dependencies
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestPipelineError)

      # Execute
      result = Processor.process_kill_data(kill_data, test_context)

      # Cleanup
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)

      # Verify the result shows error
      assert match?({:error, :test_error}, result)
    end
  end

  describe "send_test_kill_notification/0" do
    test "sends a test notification when recent kills available" do
      # Setup - mock the cache behavior to return a recent kill
      test_kill = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142
      }

      # Create a module to return test data
      defmodule TestCacheRepo do
        def get(cache_key) do
          if cache_key == WandererNotifier.Cache.Keys.zkill_recent_kills() do
            {:ok,
             [
               %{
                 "killmail_id" => "12345",
                 "zkb" => %{"hash" => "test_hash"}
               }
             ]}
          else
            {:error, :not_found}
          end
        end
      end

      # Create pipeline module for testing
      defmodule TestKillPipeline do
        def process_killmail(_kill_data, _context) do
          {:ok,
           %WandererNotifier.Killmail.Killmail{
             killmail_id: "12345",
             victim_name: "Test Victim",
             system_name: "Test System",
             zkb: %{"hash" => "test_hash"}
           }}
        end
      end

      # Create a test notification module
      defmodule TestNotification do
        def send_kill_notification(_killmail, _type, _opts) do
          {:ok, :sent}
        end
      end

      # Set up dependencies
      Application.put_env(:wanderer_notifier, :cache_repo, TestCacheRepo)
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestKillPipeline)
      Application.put_env(:wanderer_notifier, :killmail_notification, TestNotification)

      # Execute
      result = Processor.send_test_kill_notification()

      # Cleanup
      Application.delete_env(:wanderer_notifier, :cache_repo)
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)
      Application.delete_env(:wanderer_notifier, :killmail_notification)

      # Verify
      assert {:ok, "12345"} = result
    end

    test "handles no recent kills available" do
      # Setup - mock the cache behavior to return no kills
      defmodule TestEmptyCacheRepo do
        def get(_cache_key) do
          {:ok, []}
        end
      end

      # Set up dependencies
      Application.put_env(:wanderer_notifier, :cache_repo, TestEmptyCacheRepo)

      # Execute
      result = Processor.send_test_kill_notification()

      # Cleanup
      Application.delete_env(:wanderer_notifier, :cache_repo)

      # Verify
      assert {:error, :no_recent_kills} = result
    end

    test "handles processing errors during test notification" do
      # Setup - mock the cache behavior to return a kill but fail processing
      defmodule TestErrorCacheRepo do
        def get(cache_key) do
          if cache_key == WandererNotifier.Cache.Keys.zkill_recent_kills() do
            {:ok,
             [
               %{
                 "killmail_id" => "12345",
                 "zkb" => %{"hash" => "error_hash"}
               }
             ]}
          else
            {:error, :not_found}
          end
        end
      end

      # Create pipeline module that errors
      defmodule TestErrorPipeline do
        def process_killmail(_kill_data, _context) do
          {:error, :test_error}
        end
      end

      # Set up dependencies
      Application.put_env(:wanderer_notifier, :cache_repo, TestErrorCacheRepo)
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestErrorPipeline)

      # Execute
      result = Processor.send_test_kill_notification()

      # Cleanup
      Application.delete_env(:wanderer_notifier, :cache_repo)
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)

      # Verify
      assert {:error, _} = result
    end
  end
end
