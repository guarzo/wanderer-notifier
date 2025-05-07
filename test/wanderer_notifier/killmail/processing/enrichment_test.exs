defmodule WandererNotifier.Killmail.EnrichmentTest do
  use ExUnit.Case, async: true
  import Mox

  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Killmail.Killmail

  setup :verify_on_exit!

  setup do
    # Set up Mox for ESI.Service, ESI.Client, ZKillClient, and cache repository
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)
    Application.put_env(:wanderer_notifier, :esi_client, WandererNotifier.Api.ESI.ServiceMock)
    Application.put_env(:wanderer_notifier, :zkill_client, WandererNotifier.Api.ZKill.ServiceMock)

    Application.put_env(
      :wanderer_notifier,
      :cache_repository,
      WandererNotifier.Test.Support.Mocks
    )

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_character_info, fn id, _opts ->
      case id do
        100 -> {:ok, %{"name" => "Victim", "corporation_id" => 300, "alliance_id" => 400}}
        101 -> {:ok, %{"name" => "Attacker", "corporation_id" => 301, "alliance_id" => 401}}
        _ -> {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}
      end
    end)

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_corporation_info, fn id, _opts ->
      case id do
        300 -> {:ok, %{"name" => "Victim Corp", "ticker" => "VC"}}
        301 -> {:ok, %{"name" => "Attacker Corp", "ticker" => "AC"}}
        _ -> {:ok, %{"name" => "Unknown Corp", "ticker" => "UC"}}
      end
    end)

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_alliance_info, fn id, _opts ->
      case id do
        400 -> {:ok, %{"name" => "Victim Alliance", "ticker" => "VA"}}
        401 -> {:ok, %{"name" => "Attacker Alliance", "ticker" => "AA"}}
        _ -> {:ok, %{"name" => "Unknown Alliance", "ticker" => "UA"}}
      end
    end)

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_type_info, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_universe_type, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)

    Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_ship_type_name, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
      end
    end)

    :ok
  end

  describe "enrich_killmail_data/1" do
    test "returns {:ok, enriched_killmail} on success" do
      killmail = %Killmail{killmail_id: 1, zkb: %{"hash" => "abc"}}

      esi_data = %{
        "victim" => %{
          "character_id" => 100,
          "ship_type_id" => 200,
          "corporation_id" => 300,
          "alliance_id" => 400
        },
        "solar_system_id" => 500,
        "attackers" => [
          %{
            "character_id" => 101,
            "corporation_id" => 301,
            "alliance_id" => 401,
            "ship_type_id" => 201,
            "weapon_type_id" => 301,
            "damage_done" => 123,
            "final_blow" => true,
            "security_status" => 5.0,
            "faction_id" => 1
          }
        ]
      }

      expect(WandererNotifier.Api.ESI.ServiceMock, :get_killmail, fn 1, "abc", _opts ->
        {:ok, esi_data}
      end)

      expect(WandererNotifier.Api.ESI.ServiceMock, :get_system, fn _id, _opts ->
        {:ok, %{"name" => "Jita"}}
      end)

      {:ok, enriched} = Enrichment.enrich_killmail_data(killmail)
      assert enriched.victim_name == "Victim"
      assert enriched.victim_corp_ticker == "VC"
      assert enriched.ship_name == "Victim Ship"
      assert enriched.system_name == "Jita"
      assert is_list(enriched.attackers)
      [attacker] = enriched.attackers
      assert attacker.character_name == "Attacker"
      assert attacker.corporation_ticker == "AC"
      assert attacker.alliance_ticker == "AA"
      assert attacker.ship_type_name == "Attacker Ship"
      assert attacker.weapon_type_name == "Weapon"
    end

    test "returns {:error, :esi_data_missing} if ESI returns error" do
      killmail = %Killmail{killmail_id: 2, zkb: %{"hash" => "def"}}

      expect(WandererNotifier.Api.ESI.ServiceMock, :get_killmail, fn 2, "def", _opts ->
        {:error, :not_found}
      end)

      assert {:error, :esi_data_missing} = Enrichment.enrich_killmail_data(killmail)
    end

    test "returns {:error, reason} if victim info fails" do
      killmail = %Killmail{
        killmail_id: 1,
        zkb: %{"hash" => "abc"}
      }

      esi_data = %{
        "victim" => %{
          "character_id" => 100,
          "ship_type_id" => 200,
          "corporation_id" => 300,
          "alliance_id" => 400
        },
        "solar_system_id" => 500,
        "attackers" => []
      }

      expect(WandererNotifier.Api.ESI.ServiceMock, :get_killmail, fn 1, "abc", _opts ->
        {:ok, esi_data}
      end)

      expect(WandererNotifier.Api.ESI.ServiceMock, :get_system, fn _id, _opts ->
        {:error, :system_not_found}
      end)

      assert {:error, :system_not_found} = Enrichment.enrich_killmail_data(killmail)
    end
  end

  describe "recent_kills_for_system/2" do
    test "returns formatted strings for kills" do
      system_id = 30_001_227

      killmail = %{
        "killmail_id" => 1,
        "zkb" => %{
          "hash" => "abc",
          "totalValue" => 1_000_000
        },
        "esi_data" => %{
          "victim" => %{
            "character_id" => 100,
            "ship_type_id" => 200
          },
          "killmail_time" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      Mox.stub(WandererNotifier.Api.ZKill.ServiceMock, :get_system_kills, fn ^system_id, _opts ->
        {:ok, [killmail]}
      end)

      Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_killmail, fn _id, _hash, _opts ->
        {:ok, killmail["esi_data"]}
      end)

      Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_system, fn _id, _opts ->
        {:ok, %{"name" => "Jita"}}
      end)

      Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_character_info, fn _id, _opts ->
        {:ok, %{"name" => "Victim"}}
      end)

      Mox.stub(WandererNotifier.Api.ESI.ServiceMock, :get_type_info, fn _id, _opts ->
        {:ok, %{"name" => "Victim Ship"}}
      end)

      result = Enrichment.recent_kills_for_system(system_id)
      assert Enum.any?(result, &String.contains?(&1, "Victim Ship"))
    end

    test "returns [] if zkill returns error" do
      Mox.stub(WandererNotifier.Api.ZKill.ServiceMock, :get_system_kills, fn 500, 2 ->
        {:error, :fail}
      end)

      assert Enrichment.recent_kills_for_system(500, 2) == []
    end
  end
end
