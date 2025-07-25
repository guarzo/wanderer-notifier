defmodule WandererNotifier.Domains.Tracking.Clients.UnifiedClientTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Tracking.Clients.UnifiedClient
  alias WandererNotifier.Infrastructure.Cache

  import Mox

  setup :verify_on_exit!

  describe "fetch_and_cache_characters/0" do
    test "successfully fetches and caches character data" do
      mock_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Test Character",
          "corporation_id" => 2001,
          "corporation_ticker" => "TEST"
        }
      ]

      # Mock the cache operations
      expect(WandererNotifier.MockCache, :get, fn "map:character_list" ->
        {:error, :not_found}
      end)

      expect(WandererNotifier.MockCache, :put, fn "map:character_list", data, _ttl ->
        assert data == mock_characters
        {:ok, data}
      end)

      # Mock the HTTP request
      expect(WandererNotifier.MockHttp, :request, fn :get, _url, nil, _headers, opts ->
        assert Keyword.get(opts, :service) == :map
        {:ok, %{status_code: 200, body: %{"data" => mock_characters}}}
      end)

      result = UnifiedClient.fetch_and_cache_characters()

      assert {:ok, characters} = result
      assert length(characters) == 1
      assert List.first(characters)["name"] == "Test Character"
    end

    test "returns cached data when available" do
      cached_characters = [
        %{
          "eve_id" => "123456",
          "name" => "Cached Character",
          "corporation_ticker" => "CACHE"
        }
      ]

      expect(WandererNotifier.MockCache, :get, fn "map:character_list" ->
        {:ok, cached_characters}
      end)

      # Should not make HTTP request when cache hit
      expect(WandererNotifier.MockHttp, :request, 0, fn _, _, _, _, _ ->
        {:ok, %{status_code: 200, body: %{}}}
      end)

      result = UnifiedClient.fetch_and_cache_characters()

      assert {:ok, characters} = result
      assert characters == cached_characters
    end

    test "handles HTTP errors gracefully" do
      expect(WandererNotifier.MockCache, :get, fn "map:character_list" ->
        {:error, :not_found}
      end)

      expect(WandererNotifier.MockHttp, :request, fn :get, _url, nil, _headers, _opts ->
        {:error, :timeout}
      end)

      result = UnifiedClient.fetch_and_cache_characters()

      assert {:error, :timeout} = result
    end
  end

  describe "fetch_and_cache_systems/0" do
    test "successfully fetches and caches system data" do
      mock_systems = [
        %{
          "id" => "30000142",
          "name" => "Jita",
          "solar_system_id" => 30_000_142,
          "region_name" => "The Forge"
        }
      ]

      expect(WandererNotifier.MockCache, :get, fn "map:systems" ->
        {:error, :not_found}
      end)

      expect(WandererNotifier.MockCache, :put, fn "map:systems", data, _ttl ->
        assert data == mock_systems
        {:ok, data}
      end)

      expect(WandererNotifier.MockHttp, :request, fn :get, _url, nil, _headers, opts ->
        assert Keyword.get(opts, :service) == :map
        {:ok, %{status_code: 200, body: %{"data" => mock_systems}}}
      end)

      result = UnifiedClient.fetch_and_cache_systems()

      assert {:ok, systems} = result
      assert length(systems) == 1
      assert List.first(systems)["name"] == "Jita"
    end

    test "validates system data structure" do
      invalid_systems = [
        %{
          "id" => "invalid",
          # Missing required fields
          "name" => nil
        }
      ]

      expect(WandererNotifier.MockCache, :get, fn "map:systems" ->
        {:error, :not_found}
      end)

      expect(WandererNotifier.MockHttp, :request, fn :get, _url, nil, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{"data" => invalid_systems}}}
      end)

      result = UnifiedClient.fetch_and_cache_systems()

      # Should handle validation errors gracefully
      assert {:error, _reason} = result
    end
  end

  describe "batch_processing" do
    test "processes characters in batches when needed" do
      # Create a list larger than the batch size
      large_character_list =
        Enum.map(1..30, fn i ->
          %{
            "eve_id" => "#{i}",
            "name" => "Character #{i}",
            "corporation_id" => 2000 + i,
            "corporation_ticker" => "T#{i}"
          }
        end)

      expect(WandererNotifier.MockCache, :get, fn "map:character_list" ->
        {:error, :not_found}
      end)

      expect(WandererNotifier.MockCache, :put, fn "map:character_list", data, _ttl ->
        assert length(data) == 30
        {:ok, data}
      end)

      expect(WandererNotifier.MockHttp, :request, fn :get, _url, nil, _headers, _opts ->
        {:ok, %{status_code: 200, body: %{"data" => large_character_list}}}
      end)

      result = UnifiedClient.fetch_and_cache_characters()

      assert {:ok, characters} = result
      assert length(characters) == 30
    end
  end
end
