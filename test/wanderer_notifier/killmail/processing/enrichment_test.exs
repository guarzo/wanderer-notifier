defmodule WandererNotifier.Killmail.Processing.EnrichmentTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Api.ESI.ServiceMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up Mox for ESI.Service
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)

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
    |> stub(:get_universe_type, fn id, _opts ->
      case id do
        200 -> {:ok, %{"name" => "Victim Ship"}}
        201 -> {:ok, %{"name" => "Attacker Ship"}}
        301 -> {:ok, %{"name" => "Weapon"}}
        _ -> {:ok, %{"name" => "Unknown Ship"}}
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
          {:error, :not_found}
      end
    end)
    |> stub(:get_killmail, fn kill_id, killmail_hash, _opts ->
      case {kill_id, killmail_hash} do
        {123, "abc123"} ->
          {:ok,
           %{
             "killmail_id" => 123,
             "killmail_time" => "2024-01-01T00:00:00Z",
             "solar_system_id" => 30_000_142,
             "victim" => %{
               "character_id" => 100,
               "corporation_id" => 300,
               "alliance_id" => 400,
               "ship_type_id" => 200
             },
             "attackers" => []
           }}

        _ ->
          {:error, :killmail_not_found}
      end
    end)

    :ok
  end

  test "successfully enriches killmail data" do
    # Create a test killmail with ESI data already present
    killmail = %Killmail{
      killmail_id: 123,
      zkb: %{"hash" => "abc123"},
      esi_data: %{
        "victim" => %{
          "character_id" => 100,
          "corporation_id" => 300,
          "ship_type_id" => 200
        },
        "solar_system_id" => 30_000_142,
        "attackers" => []
      }
    }

    # Call the actual Enrichment module
    {:ok, enriched} = Enrichment.enrich_killmail_data(killmail)

    # Verify the results
    assert enriched.victim_name == "Victim"
    assert enriched.victim_corporation == "Victim Corp"
    assert enriched.victim_corp_ticker == "VC"
    assert enriched.ship_name == "Victim Ship"
    assert enriched.system_name == "Test System"
  end
end
