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
    WandererNotifier.Test.Support.Mocks.TestMocks.setup_all_mocks()

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

      # Should return a Character struct with normalized fields
      assert %WandererNotifier.Domains.Tracking.Entities.Character{} = result
      assert result.name == "Test Character"
      assert result.eve_id == 123
      assert result.character_id == "123"
      assert result.corporation_id == 456
      assert result.tracked == false
    end

    test "enriches system data correctly" do
      # Mock the StaticInfo.enrich_system call
      expect(WandererNotifier.Domains.Tracking.StaticInfoMock, :enrich_system, fn system ->
        # Return enriched system with static wormhole information
        enriched =
          Map.merge(system, %{
            :statics => ["C247", "P060"],
            :class_title => "C4",
            :system_class => 4,
            :security_status => -1.0,
            :effect_name => nil,
            :is_shattered => false,
            :static_details => [
              %{
                "name" => "C247",
                "destination" => %{"name" => "Class 3", "short_name" => "C3"},
                "properties" => %{"lifetime" => "16", "max_jump_mass" => 300_000_000}
              }
            ]
          })

        {:ok, enriched}
      end)

      system_data = %{
        "name" => "J123456",
        "solar_system_id" => 31_000_001,
        "region_id" => 11_000_001
      }

      result = MapTrackingClient.enrich_system(system_data)

      # Should return enriched system data with static wormhole information
      assert is_map(result)
      assert result[:statics] == ["C247", "P060"]
      assert result[:class_title] == "C4"
      assert result[:system_class] == 4
      assert result[:security_status] == -1.0
      assert result[:static_details] != nil
      assert length(result[:static_details]) > 0
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

      # Verify exact data structure was cached
      cached_data = Cache.get("map:character_list")
      assert is_list(cached_data)
      assert length(cached_data) == 1

      # Verify the cached character has been enriched to a Character struct
      cached_character = List.first(cached_data)
      assert %WandererNotifier.Domains.Tracking.Entities.Character{} = cached_character
      assert cached_character.name == "Test Character"
      assert cached_character.eve_id == 123
      assert cached_character.character_id == "123"
    end
  end
end
