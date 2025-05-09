defmodule WandererNotifier.Killmail.EnrichmentTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Killmail.Killmail

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure the application to use our mocks
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.Api.ESI.ServiceMock)
    Application.put_env(:wanderer_notifier, :esi_client, WandererNotifier.Api.ESI.ClientMock)

    Application.put_env(
      :wanderer_notifier,
      :zkill_client,
      WandererNotifier.Killmail.ZKillClientMock
    )

    :ok
  end

  describe "enrich_killmail_data/1" do
    test "successfully enriches killmail data" do
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

      expect(WandererNotifier.Api.ESI.ClientMock, :get_character_info, fn 100, _opts ->
        {:ok, %{"name" => "Victim"}}
      end)

      expect(WandererNotifier.Api.ESI.ClientMock, :get_corporation_info, fn 200, _opts ->
        {:ok, %{"name" => "Corp", "ticker" => "CORP"}}
      end)

      expect(WandererNotifier.Api.ESI.ClientMock, :get_universe_type, fn 300, _opts ->
        {:ok, %{"name" => "Ship"}}
      end)

      expect(WandererNotifier.Api.ESI.ClientMock, :get_system, fn 400, _opts ->
        {:ok, %{"name" => "System"}}
      end)

      assert {:ok, enriched_killmail} = Enrichment.enrich_killmail_data(killmail)
      assert enriched_killmail.victim_name == "Victim"
      assert enriched_killmail.victim_corporation == "Corp"
      assert enriched_killmail.victim_corp_ticker == "CORP"
      assert enriched_killmail.ship_name == "Ship"
      assert enriched_killmail.system_name == "System"
    end

    test "returns {:error, :esi_data_missing} if ESI service returns error for non-existent killmail" do
      killmail = %Killmail{
        killmail_id: 123,
        zkb: %{"hash" => "abc123"}
      }

      expect(WandererNotifier.Api.ESI.ClientMock, :get_killmail, fn 123, "abc123", _opts ->
        {:error, :not_found}
      end)

      assert {:error, :esi_data_missing} = Enrichment.enrich_killmail_data(killmail)
    end

    test "returns {:error, :service_unavailable} if victim info fails" do
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

      # Set up the mock to return :service_unavailable for character info
      expect(WandererNotifier.Api.ESI.ClientMock, :get_character_info, fn 100, _opts ->
        {:error, :service_unavailable}
      end)

      # We won't get to these functions, but we need to stub them to avoid errors
      stub(WandererNotifier.Api.ESI.ClientMock, :get_corporation_info, fn _, _ ->
        {:ok, %{"name" => "Corp", "ticker" => "TEST"}}
      end)

      stub(WandererNotifier.Api.ESI.ClientMock, :get_universe_type, fn _, _ ->
        {:ok, %{"name" => "Ship"}}
      end)

      stub(WandererNotifier.Api.ESI.ClientMock, :get_system, fn _, _ ->
        {:ok, %{"name" => "System"}}
      end)

      assert {:error, :service_unavailable} = Enrichment.enrich_killmail_data(killmail)
    end
  end

  describe "recent_kills_for_system/2" do
    test "returns formatted kills for a system" do
      system_id = 30_000_142
      limit = 3

      expect(WandererNotifier.Killmail.ZKillClientMock, :get_system_kills, fn ^system_id,
                                                                              ^limit ->
        {:ok,
         [
           %{
             "killmail_id" => 1,
             "zkb" => %{"hash" => "abc123", "totalValue" => 1_000_000_000},
             "esi_data" => %{
               "victim" => %{"ship_type_id" => 300}
             }
           }
         ]}
      end)

      # Mock the killmail fetch used in enrich_killmail_for_system
      expect(WandererNotifier.Api.ESI.ClientMock, :get_killmail, fn 1, "abc123", _opts ->
        {:ok, %{"victim" => %{"ship_type_id" => 300}}}
      end)

      # Mock any other killmails that might be fetched
      stub(WandererNotifier.Api.ESI.ClientMock, :get_killmail, fn kill_id, hash, _opts ->
        {:ok, %{"victim" => %{"ship_type_id" => 300}}}
      end)

      expect(WandererNotifier.Api.ESI.ClientMock, :get_universe_type, fn 300, _opts ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      # Add stubs for other ESI calls that might be made
      stub(WandererNotifier.Api.ESI.ClientMock, :get_character_info, fn _, _ ->
        {:ok, %{"name" => "Test Character"}}
      end)

      stub(WandererNotifier.Api.ESI.ClientMock, :get_corporation_info, fn _, _ ->
        {:ok, %{"name" => "Test Corp", "ticker" => "TEST"}}
      end)

      stub(WandererNotifier.Api.ESI.ClientMock, :get_system, fn _, _ ->
        {:ok, %{"name" => "Test System"}}
      end)

      result = Enrichment.recent_kills_for_system(system_id, limit)
      assert length(result) == 1
      assert hd(result) =~ "Test Ship"
      assert hd(result) =~ "1.0B ISK"
    end

    test "returns empty list when ZKillClient returns error" do
      system_id = 30_000_142
      limit = 3

      expect(WandererNotifier.Killmail.ZKillClientMock, :get_system_kills, fn ^system_id,
                                                                              ^limit ->
        {:error, :service_unavailable}
      end)

      # When ZKillClient returns an error, no further API calls should be made
      # The function returns an empty list immediately. But we stub them just in case.
      stub(WandererNotifier.Api.ESI.ClientMock, :get_killmail, fn _, _, _ ->
        {:ok, %{}}
      end)

      assert Enrichment.recent_kills_for_system(system_id, limit) == []
    end
  end
end
