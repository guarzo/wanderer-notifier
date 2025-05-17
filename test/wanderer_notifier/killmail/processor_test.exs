defmodule WandererNotifier.Killmail.ProcessorTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.Processor
  alias WandererNotifier.Notifications.MockDeduplication
  alias WandererNotifier.Notifications.MockConfig
  alias WandererNotifier.Map.MapSystemMock
  alias WandererNotifier.Map.MapCharacterMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Allow Mox in spawned processes
    # (Removed Mox.allow/3 calls as they are not needed when both PIDs are self())

    # Store original application environment
    original_config = Application.get_env(:wanderer_notifier, :config_module)
    original_system = Application.get_env(:wanderer_notifier, :system_module)
    original_character = Application.get_env(:wanderer_notifier, :character_module)
    original_deduplication = Application.get_env(:wanderer_notifier, :deduplication_module)
    original_http = Application.get_env(:wanderer_notifier, :http_module)
    original_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)

    # Define a mock module for the Pipeline that we can control in tests
    # This way we don't need to rely on other mocks working correctly
    defmodule MockPipeline do
      def process_killmail(_zkb_data, _ctx) do
        # Default to an error so tests must explicitly set expectations
        {:error, :unexpected_call}
      end
    end

    # Override with test mocks
    Application.put_env(
      :wanderer_notifier,
      :config_module,
      WandererNotifier.Notifications.MockConfig
    )

    Application.put_env(:wanderer_notifier, :system_module, WandererNotifier.Map.MapSystemMock)

    Application.put_env(
      :wanderer_notifier,
      :character_module,
      WandererNotifier.Map.MapCharacterMock
    )

    Application.put_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Notifications.MockDeduplication
    )

    Application.put_env(
      :wanderer_notifier,
      :http_module,
      WandererNotifier.HttpClient.HttpoisonMock
    )

    Application.put_env(:wanderer_notifier, :esi_client, WandererNotifier.Api.ESI.ServiceMock)

    # Set up HTTP mock expectations
    WandererNotifier.HttpClient.HttpoisonMock
    |> stub(:get, fn url, _headers ->
      case url do
        "https://esi.evetech.net/latest/universe/systems/30000142/" ->
          {:ok, %{status_code: 200, body: %{"name" => "Test System"}}}

        "https://esi.evetech.net/latest/characters/123/" ->
          {:ok, %{status_code: 200, body: %{"name" => "Test Character"}}}

        "https://esi.evetech.net/latest/corporations/456/" ->
          {:ok, %{status_code: 200, body: %{"name" => "Test Corporation"}}}

        "https://esi.evetech.net/latest/universe/types/789/" ->
          {:ok, %{status_code: 200, body: %{"name" => "Test Ship"}}}

        _ ->
          {:ok, %{status_code: 404, body: %{"error" => "Not found"}}}
      end
    end)

    # Set up default stubs
    Mox.stub(MockDeduplication, :check, fn _, _ -> {:ok, :new} end)

    Mox.stub(MockConfig, :get_config, fn ->
      %{
        notifications_enabled: true,
        kill_notifications_enabled: true,
        system_notifications_enabled: true,
        character_notifications_enabled: true
      }
    end)

    # Set up ESI client mock
    WandererNotifier.Api.ESI.ServiceMock
    |> stub(:get_killmail, fn id, hash, _opts ->
      case {id, hash} do
        {123, "test_hash"} ->
          {:ok,
           %{
             "killmail_id" => 123,
             "killmail_time" => "2024-01-01T00:00:00Z",
             "solar_system_id" => 30_000_142,
             "victim" => %{
               "character_id" => 100,
               "corporation_id" => 300,
               "ship_type_id" => 200,
               "alliance_id" => 400
             },
             "attackers" => []
           }}

        _ ->
          {:error, :not_found}
      end
    end)
    |> stub(:get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Test Character", "corporation_id" => 300, "alliance_id" => 400}}
        _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
      end
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Test Corporation", "ticker" => "TSTC"}}
        _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
      end
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Test Alliance", "ticker" => "TSTA"}}
        _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
      end
    end)
    |> stub(:get_system, fn id, _opts ->
      case id do
        30_000_142 ->
          {:ok,
           %{
             "name" => "Test System",
             "system_id" => 30_000_142,
             "constellation_id" => 20_000_020,
             "security_status" => 0.9,
             "security_class" => "B"
           }}

        _ ->
          {:ok, %{"name" => "Unknown System", "system_id" => id}}
      end
    end)
    |> stub(:get_universe_type, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Test Ship"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)
    |> stub(:get_system_kills, fn _id, _limit, _opts ->
      {:ok, []}
    end)

    # Add notification mock with proper options handling
    Mox.stub(
      WandererNotifier.Notifications.DiscordNotifierMock,
      :send_kill_notification,
      fn _killmail, _type, opts ->
        # Convert map to keyword list if needed
        opts = if is_map(opts), do: Map.to_list(opts), else: opts

        # Check for skip or duplicate flags
        if opts == nil do
          :ok
        else
          # Handle options as either keyword list or map
          skip =
            if is_map(opts),
              do: Map.get(opts, :skip_notification),
              else: Keyword.get(opts, :skip_notification)

          duplicate =
            if is_map(opts), do: Map.get(opts, :duplicate), else: Keyword.get(opts, :duplicate)

          if skip || duplicate do
            {:ok, :skipped}
          else
            :ok
          end
        end
      end
    )

    Mox.stub(MapSystemMock, :is_tracked?, fn _id -> true end)
    Mox.stub(MapCharacterMock, :is_tracked?, fn _id -> true end)

    on_exit(fn ->
      # Restore original environment
      Application.put_env(:wanderer_notifier, :config_module, original_config)
      Application.put_env(:wanderer_notifier, :system_module, original_system)
      Application.put_env(:wanderer_notifier, :character_module, original_character)
      Application.put_env(:wanderer_notifier, :deduplication_module, original_deduplication)
      Application.put_env(:wanderer_notifier, :http_module, original_http)

      # Also restore the original pipeline
      if original_pipeline do
        Application.put_env(:wanderer_notifier, :killmail_pipeline, original_pipeline)
      else
        Application.delete_env(:wanderer_notifier, :killmail_pipeline)
      end
    end)

    :ok
  end

  describe "process_zkill_message/2" do
    test "successfully processes a valid ZKill message" do
      # Create a mock pipeline module for this test
      defmodule SuccessProcessorPipeline do
        def process_killmail(_zkb_data, _ctx) do
          # Return a successful result
          {:ok,
           %WandererNotifier.Killmail.Killmail{
             killmail_id: "123",
             zkb: %{"hash" => "test_hash"},
             system_name: "Test System"
           }}
        end
      end

      # Save original pipeline module
      original_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)

      # Use our mock pipeline
      Application.put_env(:wanderer_notifier, :killmail_pipeline, SuccessProcessorPipeline)

      message =
        Jason.encode!(%{
          "killmail_id" => 123,
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 123,
            "corporation_id" => 456,
            "ship_type_id" => 789
          },
          "attackers" => [],
          "zkb" => %{"hash" => "test_hash"}
        })

      try do
        assert {:ok, _} = Processor.process_zkill_message(message, "test_source")
      after
        # Restore original pipeline
        Application.put_env(:wanderer_notifier, :killmail_pipeline, original_pipeline)
      end
    end

    test "skips processing when notifications are not needed" do
      message =
        Jason.encode!(%{
          "killmail_id" => 123,
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 123,
            "corporation_id" => 456,
            "ship_type_id" => 789
          },
          "attackers" => [],
          "zkb" => %{"hash" => "test_hash"}
        })

      Mox.stub(MockDeduplication, :check, fn _, _ -> {:ok, :duplicate} end)
      assert {:ok, :skipped} = Processor.process_zkill_message(message, "test_source")
    end
  end

  describe "process_kill_data/2" do
    test "successfully processes kill data" do
      # Create a mock pipeline module for this test
      defmodule SuccessKillPipeline do
        def process_killmail(_zkb_data, _ctx) do
          # Return a successful result
          {:ok,
           %WandererNotifier.Killmail.Killmail{
             killmail_id: "123",
             zkb: %{"hash" => "test_hash"},
             system_name: "Test System"
           }}
        end
      end

      # Save original pipeline module
      original_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)

      # Use our mock pipeline
      Application.put_env(:wanderer_notifier, :killmail_pipeline, SuccessKillPipeline)

      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      try do
        assert {:ok, _} = Processor.process_kill_data(kill_data, "test_source")
      after
        # Restore original pipeline
        Application.put_env(:wanderer_notifier, :killmail_pipeline, original_pipeline)
      end
    end

    test "process_kill_data/2 skips processing when notifications are not needed" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      # Define a custom pipeline function specifically for this test
      defmodule SkipTestPipeline do
        def process_killmail(_zkb_data, _ctx) do
          # Return :skipped which will be passed through
          {:ok, :skipped}
        end
      end

      # Set up our pipeline for this specific test
      original_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)
      Application.put_env(:wanderer_notifier, :killmail_pipeline, SkipTestPipeline)

      try do
        # This will execute our mocked pipeline which returns :skipped directly
        result = Processor.process_kill_data(kill_data, "test_source")

        # Directly check the result - don't use pattern matching
        assert result == {:ok, :skipped}
      after
        # Restore original pipeline
        if original_pipeline do
          Application.put_env(:wanderer_notifier, :killmail_pipeline, original_pipeline)
        else
          Application.delete_env(:wanderer_notifier, :killmail_pipeline)
        end
      end
    end

    test "handles processing errors" do
      kill_data = %{
        "killmail_id" => 123,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 123,
          "corporation_id" => 456,
          "ship_type_id" => 789
        },
        "attackers" => [],
        "zkb" => %{"hash" => "test_hash"}
      }

      # Define a custom pipeline function specifically for this test that returns an error
      defmodule ErrorTestPipeline do
        def process_killmail(_zkb_data, _ctx) do
          # Return an error that will be passed through
          {:error, :test_error}
        end
      end

      # Set up our pipeline for this specific test
      original_pipeline = Application.get_env(:wanderer_notifier, :killmail_pipeline)
      Application.put_env(:wanderer_notifier, :killmail_pipeline, ErrorTestPipeline)

      try do
        # This will execute our mocked pipeline which returns the error directly
        result = Processor.process_kill_data(kill_data, "test_source")

        # Verify we get the expected error
        assert result == {:error, :test_error}
      after
        # Restore original pipeline
        if original_pipeline do
          Application.put_env(:wanderer_notifier, :killmail_pipeline, original_pipeline)
        else
          Application.delete_env(:wanderer_notifier, :killmail_pipeline)
        end
      end
    end
  end
end
