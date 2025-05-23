defmodule WandererNotifier.Killmail.CacheTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Cache
  alias WandererNotifier.ESI.ServiceMock
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Cache.Keys, as: CacheKeys

  # Default TTL for tests
  @test_ttl 3600

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set up mocks
    Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.ServiceMock)

    # Ensure Cachex is started for tests
    Application.put_env(:wanderer_notifier, :cache_name, :test_cache)

    # Try to start Cachex - if it's already started, that's fine
    case Cachex.start_link(name: :test_cache) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> raise "Failed to start Cachex: #{inspect(error)}"
    end

    # Set up ESI Service mock for system name lookups
    ServiceMock
    |> stub(:get_system, fn system_id, _opts ->
      if system_id == 30_000_142 do
        {:ok, %{"name" => "Jita"}}
      else
        {:error, :not_found}
      end
    end)

    # Reset the cache
    Cache.init()

    # Ensure cache is clean
    CacheRepo.set(CacheKeys.zkill_recent_kills(), [], @test_ttl)

    # Add sample killmail data to the test context
    sample_killmail = %{
      "killmail_id" => 12_345,
      "killmail_time" => "2023-01-01T12:00:00Z",
      "solar_system_id" => 30_000_142,
      "victim" => %{
        "character_id" => 93_345_033,
        "corporation_id" => 98_553_333,
        "ship_type_id" => 602
      },
      "zkb" => %{
        "hash" => "hash12345"
      }
    }

    %{sample_killmail: sample_killmail}
  end

  describe "init/0" do
    test "initializes the cache system" do
      # Clear any existing data
      Process.delete(:system_names_cache)

      assert :ok = Cache.init()
      # Verify that the system_names_cache was initialized in process dictionary
      assert Process.get(:system_names_cache) == %{}
    end
  end

  describe "cache_kill/2" do
    test "successfully caches a killmail", %{sample_killmail: killmail} do
      kill_id = killmail["killmail_id"]

      # Cache the killmail
      assert :ok = Cache.cache_kill(kill_id, killmail)

      # Verify it was stored in the recent_kills list
      {:ok, kill_ids} = CacheRepo.get(CacheKeys.zkill_recent_kills())
      assert is_list(kill_ids)
      assert to_string(kill_id) in kill_ids

      # Verify it was stored in the cache
      key = "#{CacheKeys.zkill_recent_kills()}:#{kill_id}"
      assert {:ok, _} = CacheRepo.get(key)
    end

    test "handles empty kill list when updating" do
      # Ensure the recent_kills list is empty
      CacheRepo.set(CacheKeys.zkill_recent_kills(), [], @test_ttl)

      # Cache a killmail
      kill_id = 54_321
      killmail = %{"killmail_id" => kill_id, "some" => "data"}

      assert :ok = Cache.cache_kill(kill_id, killmail)

      # Verify the recent_kills list was updated
      {:ok, kill_ids} = CacheRepo.get(CacheKeys.zkill_recent_kills())
      assert is_list(kill_ids)
      assert to_string(kill_id) in kill_ids
    end
  end

  describe "get_kill/1" do
    test "retrieves a cached kill by ID", %{sample_killmail: killmail} do
      kill_id = killmail["killmail_id"]

      # First cache the killmail
      :ok = Cache.cache_kill(kill_id, killmail)

      # Now try to retrieve it
      assert {:ok, retrieved_killmail} = Cache.get_kill(kill_id)
      assert retrieved_killmail == killmail
    end

    test "returns error for non-existent kill ID" do
      # Try to get a kill ID that doesn't exist
      assert {:error, :not_cached} = Cache.get_kill(99_999)
    end

    test "returns error when kill exists in list but data is missing" do
      # Add a kill ID to the recent_kills list but without data
      kill_id = 88_888
      CacheRepo.set(CacheKeys.zkill_recent_kills(), [to_string(kill_id)], @test_ttl)

      # Try to retrieve it
      assert {:error, :not_found} = Cache.get_kill(kill_id)
    end
  end

  describe "get_recent_kills/0" do
    test "retrieves all recent cached kills", %{sample_killmail: killmail} do
      kill_id = killmail["killmail_id"]
      :ok = Cache.cache_kill(kill_id, killmail)
      {:ok, kills} = Cache.get_recent_kills()
      assert Map.has_key?(kills, to_string(kill_id))
    end

    test "filters out null kills", %{sample_killmail: killmail} do
      kill_id = killmail["killmail_id"]
      invalid_id = 99_999
      :ok = Cache.cache_kill(kill_id, killmail)
      kill_ids = [to_string(invalid_id), to_string(kill_id)]
      CacheRepo.set(CacheKeys.zkill_recent_kills(), kill_ids, @test_ttl)
      {:ok, kills} = Cache.get_recent_kills()
      assert map_size(kills) == 1
      assert Map.has_key?(kills, to_string(kill_id))
      refute Map.has_key?(kills, to_string(invalid_id))
      CacheRepo.delete(CacheKeys.zkill_recent_kills())
    end

    test "handles empty kill list" do
      # Ensure recent_kills is empty
      CacheRepo.set(CacheKeys.zkill_recent_kills(), [], @test_ttl)

      # Try to get recent kills
      {:ok, kills} = Cache.get_recent_kills()

      # Should be an empty map
      assert kills == %{}
    end
  end

  describe "get_latest_killmails/0" do
    test "retrieves formatted list of latest killmails", %{sample_killmail: killmail} do
      kill_id = killmail["killmail_id"]

      # Cache the killmail
      :ok = Cache.cache_kill(kill_id, killmail)

      # Get latest kills in the formatted output
      latest_kills = Cache.get_latest_killmails()

      # Verify the structure of the response
      assert is_list(latest_kills)
      assert length(latest_kills) > 0
      first_kill = List.first(latest_kills)
      assert is_map(first_kill)
      assert Map.has_key?(first_kill, "id")
      assert first_kill["killmail_id"] == kill_id
    end

    test "handles missing kill data" do
      # Ensure the cache is empty
      CacheRepo.set(CacheKeys.zkill_recent_kills(), [], @test_ttl)

      # Get latest killmails
      latest_kills = Cache.get_latest_killmails()

      # Should be an empty list
      assert latest_kills == []
    end
  end
end
