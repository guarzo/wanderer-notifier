defmodule WandererNotifier.Killmail.EnrichmentTest do
  use ExUnit.Case
  import Mox

  alias WandererNotifier.Killmail.Enrichment
  alias WandererNotifier.Killmail.Killmail
  alias WandererNotifier.HttpClient.HttpoisonMock

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Configure the application to use our mocks
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)
    Application.put_env(:wanderer_notifier, :http_client, HttpoisonMock)

    # Need ZKillClient to use real implementation but with mocked HTTP client
    Application.put_env(
      :wanderer_notifier,
      :zkill_client,
      WandererNotifier.Killmail.ZKillClient
    )

    # Set up stubs for all possible ESI calls
    stub(WandererNotifier.ESI.ServiceMock, :get_killmail, fn _id, _hash ->
      {:error, :not_found}
    end)

    stub(WandererNotifier.ESI.ServiceMock, :get_character_info, fn _id, _opts ->
      {:error, :not_found}
    end)

    stub(WandererNotifier.ESI.ServiceMock, :get_corporation_info, fn _id, _opts ->
      {:error, :not_found}
    end)

    stub(WandererNotifier.ESI.ServiceMock, :get_type_info, fn _id, _opts ->
      {:error, :not_found}
    end)

    stub(WandererNotifier.ESI.ServiceMock, :get_system, fn _id, _opts ->
      {:error, :not_found}
    end)

    stub(WandererNotifier.ESI.ServiceMock, :get_alliance_info, fn _id, _opts ->
      {:error, :not_found}
    end)

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

      expect(WandererNotifier.ESI.ServiceMock, :get_character_info, fn 100, _opts ->
        {:ok, %{"name" => "Victim"}}
      end)

      expect(WandererNotifier.ESI.ServiceMock, :get_corporation_info, fn 200, _opts ->
        {:ok, %{"name" => "Corp", "ticker" => "CORP"}}
      end)

      expect(WandererNotifier.ESI.ServiceMock, :get_type_info, fn 300, _opts ->
        {:ok, %{"name" => "Ship"}}
      end)

      expect(WandererNotifier.ESI.ServiceMock, :get_system, fn 400, _opts ->
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

      expect(WandererNotifier.ESI.ServiceMock, :get_killmail, fn 123, "abc123" ->
        {:error, :not_found}
      end)

      assert {:error, :esi_data_missing} = Enrichment.enrich_killmail_data(killmail)
    end

    test "returns {:error, :service_unavailable} if victim info fails" do
      killmail = %Killmail{
        killmail_id: 999,
        zkb: %{"hash" => "special-hash"},
        esi_data: %{
          "victim" => %{
            "character_id" => 998,
            "corporation_id" => 997,
            "ship_type_id" => 996
          },
          "solar_system_id" => 995,
          "attackers" => []
        }
      }

      # Set the mock to return a service_unavailable error for this specific character ID
      expect(WandererNotifier.ESI.ServiceMock, :get_character_info, fn 998, _opts ->
        {:error, :service_unavailable}
      end)

      # Test should now correctly handle the service_unavailable error
      result = Enrichment.enrich_killmail_data(killmail)
      assert result == {:error, :service_unavailable}
    end
  end

  # Test recent_kills_for_system with HTTP mock
  describe "recent_kills_for_system/2" do
    test "formats system kills correctly" do
      system_id = 30_000_142
      url = "https://zkillboard.com/api/kills/systemID/#{system_id}/"

      headers = [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"},
        {"Cache-Control", "no-cache"}
      ]

      # Mock HTTP response with test data
      response_data = [
        %{
          "killmail_id" => 111,
          "zkb" => %{"hash" => "test-hash", "totalValue" => 1_000_000_000}
        }
      ]

      encoded_json = Jason.encode!(response_data)

      # Expect the HTTP client to be called
      expect(HttpoisonMock, :get, fn ^url, ^headers, _opts ->
        {:ok, %{status_code: 200, body: encoded_json}}
      end)

      # Set up ESI service expectations for the killmail lookup
      expect(WandererNotifier.ESI.ServiceMock, :get_killmail, fn 111, "test-hash" ->
        {:ok, %{"victim" => %{"ship_type_id" => 222}}}
      end)

      expect(WandererNotifier.ESI.ServiceMock, :get_type_info, fn 222, _opts ->
        {:ok, %{"name" => "Test Ship"}}
      end)

      # Test success case
      success_result = Enrichment.recent_kills_for_system(system_id, 3)
      assert length(success_result) > 0

      assert Enum.any?(success_result, fn string ->
               string =~ "Test Ship" && string =~ "ISK"
             end)
    end

    test "handles error from ZKillClient correctly" do
      system_id = 30_000_143
      url = "https://zkillboard.com/api/kills/systemID/#{system_id}/"

      headers = [
        {"Accept", "application/json"},
        {"User-Agent", "WandererNotifier/1.0"},
        {"Cache-Control", "no-cache"}
      ]

      # Use stub instead of expect to allow multiple calls
      stub(HttpoisonMock, :get, fn ^url, ^headers, _opts ->
        {:error, :service_unavailable}
      end)

      # Test error case
      error_result = Enrichment.recent_kills_for_system(system_id, 3)
      # Only check if the list is empty, without comparing exact values
      assert is_list(error_result)
      assert Enum.empty?(error_result)
    end
  end
end
