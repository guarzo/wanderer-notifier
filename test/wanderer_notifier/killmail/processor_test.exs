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

  setup :verify_on_exit!

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
        notifications: %{
          enabled: true,
          kill: %{
            enabled: true,
            system: %{enabled: true},
            character: %{enabled: true}
          }
        }
      }
    end)

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

      MockSystem
      |> stub(:is_tracked?, fn _id -> {:ok, true} end)

      MockCharacter
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockDispatcher
      |> stub(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, :skipped} = Processor.process_killmail(killmail, source: :test)
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

      MockSystem
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockCharacter
      |> stub(:is_tracked?, fn _id -> {:ok, true} end)

      MockDispatcher
      |> stub(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, :skipped} = Processor.process_killmail(killmail, source: :test)
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

      MockSystem
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockCharacter
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockDispatcher
      |> stub(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, :skipped} = Processor.process_killmail(killmail, source: :test)
    end

    test "handles websocket state in context" do
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

      state = %{some: :state}

      MockSystem
      |> stub(:is_tracked?, fn _id -> {:ok, true} end)

      MockCharacter
      |> stub(:is_tracked?, fn _id -> {:ok, false} end)

      MockDispatcher
      |> stub(:send_message, fn _message -> {:ok, :sent} end)

      MockDeduplication
      |> expect(:check, fn :kill, 12_345 -> {:ok, :new} end)

      assert {:ok, :skipped} =
               Processor.process_killmail(killmail, source: :zkill_websocket, state: state)
    end
  end
end
