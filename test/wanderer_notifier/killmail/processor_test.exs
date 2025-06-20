defmodule WandererNotifier.Killmail.ProcessorTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.Processor
  alias WandererNotifier.ESI.ServiceMock
  alias WandererNotifier.MockSystem
  alias WandererNotifier.MockCharacter
  alias WandererNotifier.MockConfig
  alias WandererNotifier.MockDispatcher
  alias WandererNotifier.MockDeduplication
  alias WandererNotifier.Killmail.Pipeline
  alias WandererNotifier.Utils.TimeUtils

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    # Set up application environment
    Application.put_env(:wanderer_notifier, :system_module, MockSystem)
    Application.put_env(:wanderer_notifier, :character_module, MockCharacter)
    Application.put_env(:wanderer_notifier, :config_module, MockConfig)
    Application.put_env(:wanderer_notifier, :dispatcher_module, MockDispatcher)
    Application.put_env(:wanderer_notifier, :esi_service, ServiceMock)
    Application.put_env(:wanderer_notifier, :deduplication_module, MockDeduplication)
    Application.put_env(:wanderer_notifier, :killmail_pipeline, Pipeline)

    # Set up default mock responses
    MockConfig
    |> stub(:get_config, fn ->
      %{
        notifications_enabled: true,
        kill_notifications_enabled: true,
        system_notifications_enabled: true,
        character_notifications_enabled: true
      }
    end)
    |> stub(:deduplication_module, fn -> MockDeduplication end)
    |> stub(:system_track_module, fn -> MockSystem end)
    |> stub(:character_track_module, fn -> MockCharacter end)
    |> stub(:notification_determiner_module, fn ->
      WandererNotifier.Notifications.Determiner.Kill
    end)
    |> stub(:killmail_enrichment_module, fn -> WandererNotifier.Killmail.Enrichment end)
    |> stub(:notification_dispatcher_module, fn -> MockDispatcher end)
    |> stub(:killmail_notification_module, fn ->
      WandererNotifier.Notifications.KillmailNotification
    end)
    |> stub(:config_module, fn -> MockConfig end)

    # Set up default ESI client mock responses
    ServiceMock
    |> stub(:get_killmail, fn _id, _hash, _opts ->
      {:ok,
       %{
         "killmail_id" => 12_345,
         "killmail_time" => "2023-01-01T12:00:00Z",
         "solar_system_id" => 30_000_142,
         "victim" => %{
           "character_id" => 93_345_033,
           "corporation_id" => 98_553_333,
           "ship_type_id" => 602
         }
       }}
    end)
    |> stub(:get_character_info, fn _id, _opts ->
      {:ok,
       %{
         "name" => "Test Character",
         "corporation_id" => 98_553_333
       }}
    end)
    |> stub(:get_corporation_info, fn _id, _opts ->
      {:ok,
       %{
         "name" => "Test Corp",
         "ticker" => "TEST"
       }}
    end)
    |> stub(:get_universe_type, fn _id, _opts ->
      {:ok,
       %{
         "name" => "Test Ship",
         "group_id" => 123,
         "description" => "A test ship"
       }}
    end)
    |> stub(:get_type_info, fn _id, _opts ->
      {:ok,
       %{
         "name" => "Test Ship",
         "group_id" => 123,
         "description" => "A test ship"
       }}
    end)
    |> stub(:get_system, fn _id, _opts ->
      {:ok,
       %{
         "name" => "Test System",
         "security_status" => 0.5
       }}
    end)

    :ok
  end

  describe "process_killmail/2" do
    test "processes killmail with tracked system" do
      killmail = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{
          "hash" => "test_hash"
        }
      }

      # Set system tracking to return true for this test
      MockSystem
      |> expect(:is_tracked?, fn _id -> {:ok, true} end)

      # Set character tracking expectation
      MockCharacter
      |> expect(:is_tracked?, fn _id -> {:ok, false} end)

      MockDispatcher
      |> expect(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, 12_345} = Processor.process_killmail(killmail, source: :test)
    end

    test "processes killmail with tracked character" do
      killmail = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{
          "hash" => "test_hash"
        }
      }

      # Override default system tracking (true) to return false for this test
      MockSystem
      |> expect(:is_tracked?, fn _id -> {:ok, false} end)

      # Override default character tracking (false) to return true for this test  
      MockCharacter
      |> expect(:is_tracked?, fn _id -> {:ok, true} end)

      MockDispatcher
      |> expect(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, 12_345} = Processor.process_killmail(killmail, source: :test)
    end

    test "skips killmail with no tracked entities" do
      killmail = %{
        "killmail_id" => 12_345,
        "solar_system_id" => 30_000_142,
        "victim" => %{
          "character_id" => 93_345_033,
          "corporation_id" => 98_553_333,
          "ship_type_id" => 602
        },
        "zkb" => %{
          "hash" => "test_hash"
        }
      }

      # Override default system tracking to return false for this test
      MockSystem
      |> expect(:is_tracked?, fn _id -> {:ok, false} end)

      # Character tracking expectation 
      MockCharacter
      |> expect(:is_tracked?, fn _id -> {:ok, false} end)

      MockDispatcher
      |> stub(:send_message, fn _message -> {:ok, :sent} end)

      # MockDeduplication.check/2 is now called first in the pipeline
      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, :skipped} = Processor.process_killmail(killmail, source: :test)
    end

    test "handles redisq state in context" do
      killmail = %{
        "killmail_id" => "123",
        "killmail" => %{
          "solar_system_id" => 30_000_142,
          "victim" => %{
            "character_id" => 123_456,
            "corporation_id" => 789_012,
            "alliance_id" => 345_678
          },
          "attackers" => [
            %{
              "character_id" => 987_654,
              "corporation_id" => 567_890,
              "alliance_id" => 234_567
            }
          ]
        },
        "zkb" => %{
          "totalValue" => 1_000_000.0,
          "points" => 1
        }
      }

      state = %{
        redisq: %{
          connected: true,
          last_message: TimeUtils.now()
        }
      }

      # Set mocks to global for this async test since it spawns Tasks
      set_mox_global()

      # Override default system tracking (true) to return false for this test
      MockSystem
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      # Set character tracking to return false for this test
      MockCharacter
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockDeduplication
      |> stub(:check, fn :kill, _id -> {:ok, :new} end)

      Processor.process_killmail(killmail, source: :zkill_redisq, state: state)
    end
  end
end
