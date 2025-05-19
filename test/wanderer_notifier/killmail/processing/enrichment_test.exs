defmodule WandererNotifier.Killmail.Processing.EnrichmentTest do
  use ExUnit.Case
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.Killmail.Enrichment

  # Mock ESI service for testing
  defmodule MockESIService do
    def get_character_info(100, _), do: {:ok, %{"name" => "Victim"}}
    def get_character_info(_, _), do: {:error, :not_found}

    def get_corporation_info(200, _), do: {:ok, %{"name" => "Corp", "ticker" => "CORP"}}
    def get_corporation_info(_, _), do: {:error, :not_found}

    def get_type_info(300, _), do: {:ok, %{"name" => "Ship"}}
    def get_type_info(_, _), do: {:error, :not_found}

    def get_system(400, _), do: {:ok, %{"name" => "System"}}
    def get_system(_, _), do: {:error, :not_found}

    def get_killmail(_, _), do: {:error, :not_found}
  end

  setup do
    # Set up the mock ESI service
    Application.put_env(:wanderer_notifier, :esi_service, MockESIService)
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
          "corporation_id" => 200,
          "ship_type_id" => 300
        },
        "solar_system_id" => 400,
        "attackers" => []
      }
    }

    # Call the actual Enrichment module
    {:ok, enriched} = Enrichment.enrich_killmail_data(killmail)

    # Verify the results
    assert enriched.victim_name == "Victim"
    assert enriched.victim_corporation == "Corp"
    assert enriched.victim_corp_ticker == "CORP"
    assert enriched.ship_name == "Ship"
    assert enriched.system_name == "System"
  end
end
