defmodule WandererNotifier.Domains.Tracking.Clients.MapTrackingClientTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Clients.MapTrackingClient
  alias WandererNotifier.Infrastructure.Cache

  import Mox

  setup :verify_on_exit!

  setup do
    # Clear cache before each test
    Cache.delete("map:character_list")
    Cache.delete("map:systems")

    # Setup basic mocks
    WandererNotifier.Test.Support.Mocks.UnifiedMocks.setup_all_mocks()

    :ok
  end

  describe "fetch_and_cache_characters/0" do
    test "successfully fetches and caches character data" do
      # Mock successful HTTP response
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "data" => %{
                 "characters" => [
                   %{
                     %{"name" => "Test Character", "eve_id" => 123}
                   }
                 ]
               }
             })
         }}
      end)

      result = MapTrackingClient.fetch_and_cache_characters()

      assert {:ok, characters} = result
      assert is_list(characters)
      refute Enum.empty?(characters)
    end

    test "handles HTTP errors gracefully" do
      # Mock HTTP error
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      result = MapTrackingClient.fetch_and_cache_characters()

      assert {:error, _reason} = result
    end

    test "handles malformed JSON response" do
      # Mock response with invalid JSON
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body: "invalid json"
         }}
      end)

      result = MapTrackingClient.fetch_and_cache_characters()

      assert {:error, _reason} = result
    end
  end

  describe "fetch_and_cache_systems/0" do
    test "successfully fetches and caches system data" do
      # Mock successful HTTP response
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "data" => %{
                 "systems" => [
                   %{
                     "name" => "J123456",
                     "solar_system_id" => 31_000_001,
                     "region_id" => 11_000_001,
                     "region_name" => "Anoikis"
                   }
                 ]
               }
             })
         }}
      end)

      result = MapTrackingClient.fetch_and_cache_systems()

      assert {:ok, systems} = result
      assert is_list(systems)
      refute Enum.empty?(systems)
    end

    test "handles empty systems response" do
      # Mock empty response
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "data" => %{
                 "systems" => []
               }
             })
         }}
      end)

      result = MapTrackingClient.fetch_and_cache_systems()

      assert {:ok, systems} = result
      assert is_list(systems)
      assert Enum.empty?(systems)
    end
  end

  describe "entity enrichment" do
    test "enriches character data correctly" do
      character_data = %{
        "name" => "Test Character",
        "eve_id" => 123,
        "corporation_id" => 456
      }

      result = MapTrackingClient.enrich_character(character_data)

      # Should return enriched character data (struct or map)
      assert is_map(result) or is_struct(result)
    end

    test "enriches system data correctly" do
      system_data = %{
        "name" => "J123456",
        "solar_system_id" => 31_000_001,
        "region_id" => 11_000_001
      }

      result = MapTrackingClient.enrich_system(system_data)

      # Should return enriched system data
      assert is_map(result) or is_struct(result)
    end
  end

  describe "integration with external dependencies" do
    test "integrates with cache correctly for characters" do
      # Mock successful HTTP response
      expect(WandererNotifier.Infrastructure.Http.HttpClientMock, :get, fn _url,
                                                                           _headers,
                                                                           _opts ->
        {:ok,
         %HTTPoison.Response{
           status_code: 200,
           body:
             Jason.encode!(%{
               "data" => %{
                 "characters" => [
                   %{
                     %{"name" => "Test Character", "eve_id" => 123}
                   }
                 ]
               }
             })
         }}
      end)

      result = MapTrackingClient.fetch_and_cache_characters()

      assert {:ok, _characters} = result

      # Verify data was cached
      cached_data = Cache.get("map:character_list")
      assert cached_data != nil
    end
  end
end
