defmodule WandererNotifier.Killmail.PipelineTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.{Pipeline, Context}
  alias WandererNotifier.ESI.ServiceMock
  alias WandererNotifier.Notifications.DiscordNotifierMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up Mox for ESI.Service
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)

    # Set up default stubs
    ServiceMock
    |> stub(:get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Victim", "corporation_id" => 300, "alliance_id" => 400}}
        101 -> {:ok, %{"name" => "Attacker", "corporation_id" => 301, "alliance_id" => 401}}
        _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
      end
    end)
    |> stub(:get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Victim Corp", "ticker" => "VC"}}
        301 -> {:ok, %{"name" => "Attacker Corp", "ticker" => "AC"}}
        _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
      end
    end)
    |> stub(:get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Victim Alliance", "ticker" => "VA"}}
        401 -> {:ok, %{"name" => "Attacker Alliance", "ticker" => "AA"}}
        _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
      end
    end)
    |> stub(:get_type_info, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)
    |> stub(:get_system, fn id, _opts ->
      case id do
        30_000_142 -> {:ok, %{"name" => "Test System"}}
        _ -> {:error, :not_found}
      end
    end)

    :ok
  end

  describe "process_killmail/2" do
    test "process_killmail/2 successfully processes a valid killmail" do
      esi_data = %{
        "killmail_id" => 12_345,
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 300,
          "ship_type_id" => 200
        },
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142
      }

      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142,
        "esi_data" => esi_data
      }

      context = %Context{
        mode: %{mode: :test},
        character_id: 100,
        character_name: "Test Character",
        source: :test,
        options: %{
          "systems" => [30_000_142],
          "corporations" => [300],
          "alliances" => []
        }
      }

      ServiceMock
      |> expect(:get_killmail, fn 12_345, "test_hash" ->
        {:ok, esi_data}
      end)
      |> expect(:get_character_info, fn 100, _opts ->
        {:ok, %{"name" => "Test Character"}}
      end)
      |> expect(:get_corporation_info, fn 300, _opts ->
        {:ok, %{"name" => "Test Corp", "ticker" => "TEST"}}
      end)
      |> expect(:get_type_info, fn 200, _opts ->
        {:ok, %{"name" => "Test Ship"}}
      end)
      |> expect(:get_system, fn 30_000_142, _opts ->
        {:ok, %{"name" => "Test System"}}
      end)

      DiscordNotifierMock
      |> expect(:send_kill_notification, fn _killmail, _type, _opts ->
        :ok
      end)

      assert {:ok, _enriched_killmail} = Pipeline.process_killmail(zkb_data, context)
    end

    test "process_killmail/2 skips processing when notification is not needed" do
      esi_data = %{
        "killmail_id" => 12_345,
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 300,
          "ship_type_id" => 200
        },
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142
      }

      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142,
        "esi_data" => esi_data
      }

      context = %Context{
        mode: %{mode: :test},
        character_id: 999,
        character_name: "Other Character",
        source: :test,
        options: %{
          "systems" => [999],
          "corporations" => [999],
          "alliances" => []
        }
      }

      ServiceMock
      |> expect(:get_killmail, fn 12_345, "test_hash" ->
        {:ok, esi_data}
      end)
      |> expect(:get_character_info, fn 100, _opts ->
        {:ok, %{"name" => "Test Character"}}
      end)
      |> expect(:get_corporation_info, fn 300, _opts ->
        {:ok, %{"name" => "Test Corp", "ticker" => "TEST"}}
      end)
      |> expect(:get_type_info, fn 200, _opts ->
        {:ok, %{"name" => "Test Ship"}}
      end)
      |> expect(:get_system, fn 30_000_142, _opts ->
        {:ok, %{"name" => "Test System"}}
      end)

      assert {:ok, :skipped} = Pipeline.process_killmail(zkb_data, context)
    end

    test "process_killmail/2 handles enrichment errors" do
      esi_data = %{
        "killmail_id" => 12_345,
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 300,
          "ship_type_id" => 200
        },
        "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "solar_system_id" => 30_000_142
      }

      zkb_data = %{
        "killmail_id" => 12_345,
        "zkb" => %{"hash" => "test_hash"},
        "solar_system_id" => 30_000_142,
        "esi_data" => esi_data
      }

      context = %Context{
        mode: %{mode: :test},
        character_id: 100,
        character_name: "Test Character",
        source: :test,
        options: %{
          "systems" => [30_000_142],
          "corporations" => [300],
          "alliances" => []
        }
      }

      ServiceMock
      |> expect(:get_killmail, fn 12_345, "test_hash" ->
        {:ok, esi_data}
      end)
      |> expect(:get_character_info, fn 100, _opts ->
        {:error, :service_unavailable}
      end)

      assert {:error, :enrichment_failed} = Pipeline.process_killmail(zkb_data, context)
    end
  end
end
