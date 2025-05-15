defmodule WandererNotifier.Killmail.ProcessorTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.{Processor, Context}

  # Define the ESI Client behaviour
  defmodule ESIClientBehaviour do
    @callback get_killmail(String.t(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
    @callback get_character_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
    @callback get_corporation_info(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
    @callback get_universe_type(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
    @callback get_system(String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  end

  # Define mocks
  Mox.defmock(WandererNotifier.ESI.ClientMock, for: ESIClientBehaviour)

  # Define MockConfig for testing
  defmodule MockConfig do
    def notifications_enabled?, do: true
    def system_notifications_enabled?, do: true
    def character_notifications_enabled?, do: true
    def chain_kills_mode?, do: false
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
    # Create ETS tables for mock caching and deduplication
    :ets.new(:mock_cache, [:named_table, :public, :set])
    :ets.new(:mock_deduplication, [:named_table, :public, :set])

    # Store original application env
    original_config = Application.get_env(:wanderer_notifier, :config)
    original_system_module = Application.get_env(:wanderer_notifier, :system_module)
    original_character_module = Application.get_env(:wanderer_notifier, :character_module)
    original_deduplication_module = Application.get_env(:wanderer_notifier, :deduplication_module)
    original_http_client = Application.get_env(:wanderer_notifier, :http_client)
    original_esi_client = Application.get_env(:wanderer_notifier, :esi_client)
    original_killmail_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)

    # Override configuration for testing
    Application.put_env(:wanderer_notifier, :config, MockConfig)
    Application.put_env(:wanderer_notifier, :config_module, MockConfig)
    Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.Map.MapSystemMock)

    Application.put_env(
      :wanderer_notifier,
      :character_module,
      WandererNotifier.Map.MapCharacterMock
    )

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.MockDeduplication
    )

    Application.put_env(
      :wanderer_notifier,
      :http_client,
      WandererNotifier.HttpClient.HttpoisonMock
    )

    Application.put_env(:wanderer_notifier, :esi_client, WandererNotifier.ESI.ClientMock)

    # Create a test pipeline module
    defmodule TestPipeline do
      def process_killmail(data, _ctx) do
        case data do
          %{"killmail_id" => id, "zkb" => %{"hash" => "test_hash"}} ->
            {:ok, id}

          _ ->
            {:error, :esi_data_missing}
        end
      end
    end

    Application.put_env(:wanderer_notifier, :killmail_pipeline, TestPipeline)

    # Reset deduplication state
    WandererNotifier.MockDeduplication.configure(false)

    # Set up default mock expectations
    WandererNotifier.Map.MapSystemMock
    |> stub(:is_tracked?, fn _ -> {:ok, false} end)

    WandererNotifier.Map.MapCharacterMock
    |> stub(:is_tracked?, fn _ -> {:ok, false} end)

    on_exit(fn ->
      # Restore original application env
      Application.put_env(:wanderer_notifier, :config, original_config)
      Application.put_env(:wanderer_notifier, :config_module, original_config)
      Application.put_env(:wanderer_notifier, :system_module, original_system_module)
      Application.put_env(:wanderer_notifier, :character_module, original_character_module)

      Application.put_env(
        :wanderer_notifier,
        :deduplication_module,
        original_deduplication_module
      )

      Application.put_env(:wanderer_notifier, :http_client, original_http_client)
      Application.put_env(:wanderer_notifier, :esi_client, original_esi_client)
      Application.put_env(:wanderer_notifier, :killmail_pipeline, original_killmail_pipeline)

      # Clean up ETS tables
      try do
        :ets.delete(:mock_cache)
        :ets.delete(:mock_deduplication)
      catch
        :error, :badarg -> :ok
      end
    end)

    :ok
  end

  describe "process_zkill_message/2" do
    setup do
      # Reset deduplication state for each test
      WandererNotifier.MockDeduplication.configure(false)
      :ok
    end

    test "successfully processes a valid ZKill message" do
      # Create a valid ZKill message
      valid_message =
        Jason.encode!(%{
          "killmail_id" => "12345",
          "solar_system_id" => "30000142",
          "victim" => %{
            "character_id" => "1000001",
            "character_name" => "Test Character",
            "corporation_id" => "2000001",
            "corporation_name" => "Test Corp",
            "ship_type_id" => "12345",
            "ship_type_name" => "Test Ship"
          },
          "attackers" => [
            %{
              "character_id" => "1000002",
              "character_name" => "Attacker 1",
              "corporation_id" => "2000002",
              "corporation_name" => "Attacker Corp"
            }
          ],
          "zkb" => %{
            "totalValue" => 100_000_000,
            "points" => 100,
            "hash" => "test_hash"
          }
        })

      # Configure system tracking to handle multiple calls
      WandererNotifier.Map.MapSystemMock
      |> stub(:is_tracked?, fn "30000142" -> {:ok, true} end)

      # Configure character tracking
      WandererNotifier.Map.MapCharacterMock
      |> stub(:is_tracked?, fn _ -> {:ok, false} end)

      # Configure ESI client to return the killmail data
      WandererNotifier.ESI.ClientMock
      |> stub(:get_killmail, fn "12345", "test_hash", _opts ->
        {:ok,
         %{
           "killmail_id" => 12345,
           "killmail_time" => "2024-01-01T00:00:00Z",
           "solar_system_id" => 30_000_142,
           "victim" => %{
             "character_id" => 1_000_001,
             "corporation_id" => 2_000_001,
             "ship_type_id" => 12345
           },
           "attackers" => [
             %{
               "character_id" => 1_000_002,
               "corporation_id" => 2_000_002,
               "final_blow" => true
             }
           ]
         }}
      end)

      # Create test context
      test_context = %Context{}

      # Execute
      result = Processor.process_zkill_message(valid_message, test_context)

      # Verify
      assert {:ok, "12345"} = result
    end

    test "skips processing when notification is not needed" do
      # Setup
      test_context = %Context{}

      valid_message =
        Jason.encode!(%{
          "killmail_id" => "12345",
          "zkb" => %{"hash" => "test_hash"},
          "solar_system_id" => "30000142"
        })

      # Configure system and character tracking to return false
      WandererNotifier.Map.MapSystemMock
      |> stub(:is_tracked?, fn _ -> {:ok, false} end)

      WandererNotifier.Map.MapCharacterMock
      |> stub(:is_tracked?, fn _ -> {:ok, false} end)

      # Execute
      result = Processor.process_zkill_message(valid_message, test_context)

      # Verify
      assert {:ok, :skipped} = result
    end

    test "handles invalid JSON message" do
      # Setup
      test_context = %Context{}
      invalid_message = "not valid json"

      # Execute
      result = Processor.process_zkill_message(invalid_message, test_context)

      # Verify
      assert {:error, {:decode_error, %Jason.DecodeError{}}} = result
    end
  end

  describe "process_kill_data/2" do
    setup do
      # Reset deduplication state for each test
      WandererNotifier.MockDeduplication.configure(false)
      :ok
    end

    test "successfully processes kill data" do
      # Setup - use dependency injection to test
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => "30000142"
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
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "skip_hash"},
        "solar_system_id" => "30000142"
      }

      # Create a process pipeline module for testing
      defmodule TestPipelineSkip do
        def process_killmail(data, _ctx) do
          case data do
            %{"zkb" => %{"hash" => "skip_hash"}} -> {:ok, "12345"}
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

      # The pipeline returns {:ok, "12345"} for skipped kills in this test
      assert match?({:ok, "12345"}, result)
    end

    test "handles processing errors" do
      # Setup - use dependency injection to test
      test_context = %Context{}

      kill_data = %{
        "killmail_id" => "12345",
        "zkb" => %{"hash" => "error_hash"},
        "solar_system_id" => "30000142"
      }

      # Create a process pipeline module for testing
      defmodule TestPipelineError do
        def process_killmail(_data, _ctx) do
          {:error, :test_error}
        end
      end

      # Set up the processor with our test dependencies
      Application.put_env(:wanderer_notifier, :killmail_pipeline, TestPipelineError)

      # Execute
      result = Processor.process_kill_data(kill_data, test_context)

      # Cleanup
      Application.delete_env(:wanderer_notifier, :killmail_pipeline)

      # Verify the result shows error
      assert {:error, :test_error} = result
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
