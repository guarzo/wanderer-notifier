defmodule WandererNotifier.Infrastructure.CacheTest do
  use ExUnit.Case, async: false

  alias WandererNotifier.Infrastructure.Cache

  setup do
    # Ensure Cachex is started for testing
    cache_name = Application.get_env(:wanderer_notifier, :cache_name, :wanderer_test_cache)

    # Start Cachex if it's not already running
    case Process.whereis(cache_name) do
      nil ->
        # Ensure Cachex application is started
        Application.ensure_all_started(:cachex)

        case Cachex.start_link(name: cache_name, stats: true) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end

    # Clear cache before each test if it's running
    if Process.whereis(cache_name) do
      :ok = Cache.clear()
    end

    :ok
  end

  describe "basic cache operations" do
    test "put and get operations work correctly" do
      key = "test:key"
      value = %{"name" => "test", "id" => 123}

      # Put value
      :ok = Cache.put(key, value)

      # Get value
      assert {:ok, ^value} = Cache.get(key)
    end

    test "get returns error for non-existent key" do
      assert {:error, :not_found} = Cache.get("non:existent:key")
    end

    test "put with TTL accepts TTL parameter" do
      key = "test:ttl"
      value = "expires eventually"
      # 1 second
      ttl = 1000

      # Put with TTL should succeed
      :ok = Cache.put(key, value, ttl)

      # Should exist immediately
      assert {:ok, ^value} = Cache.get(key)

      # Note: We don't test actual expiration as it's timing-dependent
      # and the important thing is that the TTL parameter is accepted
    end

    test "delete removes cached value" do
      key = "test:delete"
      value = "to be deleted"

      # Put value
      :ok = Cache.put(key, value)
      assert {:ok, ^value} = Cache.get(key)

      # Delete value
      :ok = Cache.delete(key)
      assert {:error, :not_found} = Cache.get(key)
    end

    test "exists? checks key existence" do
      key = "test:exists"
      value = "test value"

      # Key doesn't exist initially
      refute Cache.exists?(key)

      # Put value
      :ok = Cache.put(key, value)

      # Key exists now
      assert Cache.exists?(key)

      # Delete and check again
      :ok = Cache.delete(key)
      refute Cache.exists?(key)
    end

    test "clear removes all cached values" do
      # Put multiple values
      :ok = Cache.put("test:1", "value1")
      :ok = Cache.put("test:2", "value2")
      :ok = Cache.put("test:3", "value3")

      # Verify they exist
      assert {:ok, "value1"} = Cache.get("test:1")
      assert {:ok, "value2"} = Cache.get("test:2")
      assert {:ok, "value3"} = Cache.get("test:3")

      # Clear cache
      :ok = Cache.clear()

      # Verify they're gone
      assert {:error, :not_found} = Cache.get("test:1")
      assert {:error, :not_found} = Cache.get("test:2")
      assert {:error, :not_found} = Cache.get("test:3")
    end
  end

  describe "domain-specific helpers" do
    test "get_character/1 retrieves character data" do
      character_id = 12_345
      character_data = %{name: "Test Character", corp_id: 67_890}

      # Put character data directly
      key = Cache.Keys.character(character_id)
      :ok = Cache.put(key, character_data)

      # Use helper to retrieve
      assert {:ok, ^character_data} = Cache.get_character(character_id)
    end

    test "put_character/2 stores character data with correct TTL" do
      character_id = 12_345
      character_data = %{name: "Test Character", corp_id: 67_890}

      # Use helper to store
      :ok = Cache.put_character(character_id, character_data)

      # Verify it's stored
      assert {:ok, ^character_data} = Cache.get_character(character_id)
    end

    test "get_corporation/1 retrieves corporation data" do
      corp_id = 67_890
      corp_data = %{name: "Test Corp", ticker: "TEST"}

      # Put corp data directly
      key = Cache.Keys.corporation(corp_id)
      :ok = Cache.put(key, corp_data)

      # Use helper to retrieve
      assert {:ok, ^corp_data} = Cache.get_corporation(corp_id)
    end

    test "put_corporation/2 stores corporation data" do
      corp_id = 67_890
      corp_data = %{name: "Test Corp", ticker: "TEST"}

      # Use helper to store
      :ok = Cache.put_corporation(corp_id, corp_data)

      # Verify it's stored
      assert {:ok, ^corp_data} = Cache.get_corporation(corp_id)
    end

    test "get_alliance/1 retrieves alliance data" do
      alliance_id = 111_222
      alliance_data = %{name: "Test Alliance", ticker: "TESTA"}

      # Put alliance data directly
      key = Cache.Keys.alliance(alliance_id)
      :ok = Cache.put(key, alliance_data)

      # Use helper to retrieve
      assert {:ok, ^alliance_data} = Cache.get_alliance(alliance_id)
    end

    test "put_alliance/2 stores alliance data" do
      alliance_id = 111_222
      alliance_data = %{name: "Test Alliance", ticker: "TESTA"}

      # Use helper to store
      :ok = Cache.put_alliance(alliance_id, alliance_data)

      # Verify it's stored
      assert {:ok, ^alliance_data} = Cache.get_alliance(alliance_id)
    end

    test "get_system/1 retrieves system data" do
      system_id = 30_000_142
      system_data = %{name: "Jita", security_status: 0.9}

      # Put system data directly
      key = Cache.Keys.system(system_id)
      :ok = Cache.put(key, system_data)

      # Use helper to retrieve
      assert {:ok, ^system_data} = Cache.get_system(system_id)
    end

    test "put_system/2 stores system data" do
      system_id = 30_000_142
      system_data = %{name: "Jita", security_status: 0.9}

      # Use helper to store
      :ok = Cache.put_system(system_id, system_data)

      # Verify it's stored
      assert {:ok, ^system_data} = Cache.get_system(system_id)
    end
  end

  describe "key generation" do
    test "Keys module generates correct keys" do
      assert Cache.Keys.character(123) == "esi:character:123"
      assert Cache.Keys.corporation(456) == "esi:corporation:456"
      assert Cache.Keys.alliance(789) == "esi:alliance:789"
      assert Cache.Keys.system(30_000_142) == "esi:system:30000142"
      assert Cache.Keys.killmail(987_654) == "killmail:987654"
      assert Cache.Keys.notification_dedup("test") == "notification:dedup:test"
      assert Cache.Keys.custom("prefix", "suffix") == "prefix:suffix"
    end
  end

  describe "deduplication using basic operations" do
    test "can implement killmail deduplication with basic cache ops" do
      killmail_id = 987_654
      key = Cache.Keys.killmail(killmail_id)

      # Initially not processed
      assert {:error, :not_found} = Cache.get(key)

      # Mark as processed
      :ok = Cache.put(key, true, Cache.killmail_ttl())

      # Should be marked as processed
      assert {:ok, true} = Cache.get(key)
    end

    test "can implement notification deduplication with basic cache ops" do
      notification_id = "test:notification:123"
      key = Cache.Keys.notification_dedup(notification_id)

      # Initially not sent
      assert {:error, :not_found} = Cache.get(key)

      # Mark as sent
      :ok = Cache.put(key, true, :timer.minutes(30))

      # Should be marked as sent
      assert {:ok, true} = Cache.get(key)
    end
  end

  describe "TTL configuration functions" do
    test "provides correct TTL values" do
      assert Cache.character_ttl() == :timer.hours(24)
      assert Cache.corporation_ttl() == :timer.hours(24)
      assert Cache.alliance_ttl() == :timer.hours(24)
      assert Cache.system_ttl() == :timer.hours(1)
      assert Cache.killmail_ttl() == :timer.minutes(30)
      assert Cache.map_ttl() == :timer.hours(1)
    end

    test "ttl_for/1 returns appropriate TTL" do
      assert Cache.ttl_for(:map_data) == :timer.hours(1)
      assert Cache.ttl_for(:anything_else) == :timer.hours(24)
    end
  end

  describe "error handling" do
    test "handles nil values" do
      key = "test:nil"

      # Should handle nil value storage
      assert :ok = Cache.put(key, nil)

      # Cachex treats nil as not found, which is expected behavior
      assert {:error, :not_found} = Cache.get(key)
    end

    test "stats returns cache statistics" do
      stats = Cache.stats()
      assert is_map(stats)
    end

    test "size returns cache size" do
      size = Cache.size()
      assert is_integer(size)
    end
  end
end
