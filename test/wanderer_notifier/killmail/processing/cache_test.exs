defmodule WandererNotifier.Killmail.Processing.CacheTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Processing.Cache
  alias WandererNotifier.Config.MockFeatures
  alias WandererNotifier.MockCache, as: MockKillmail

  # Test data
  @killmail_id 12345
  @test_killmail %Data{
    killmail_id: @killmail_id,
    solar_system_id: 30_000_142,
    solar_system_name: "Jita"
  }

  setup :verify_on_exit!

  setup do
    # Default behavior for mocks
    stub(MockFeatures, :cache_enabled?, fn -> true end)
    stub(MockKillmail, :exists?, fn _ -> false end)
    stub(MockKillmail, :put, fn _ -> {:ok, @killmail_id} end)

    # Configure KillmailCache module to use the mock
    Application.put_env(:wanderer_notifier, :killmail_cache, MockKillmail)

    :ok
  end

  describe "in_cache?/1" do
    test "returns true when killmail exists in cache" do
      expect(MockKillmail, :exists?, fn id ->
        assert id == @killmail_id
        true
      end)

      assert Cache.in_cache?(@killmail_id) == true
    end

    test "returns false when killmail doesn't exist in cache" do
      expect(MockKillmail, :exists?, fn id ->
        assert id == @killmail_id
        false
      end)

      assert Cache.in_cache?(@killmail_id) == false
    end

    test "handles string killmail IDs" do
      expect(MockKillmail, :exists?, fn id ->
        assert id == @killmail_id
        true
      end)

      assert Cache.in_cache?(Integer.to_string(@killmail_id)) == true
    end

    test "returns false for invalid input" do
      # Should not call the mock
      assert Cache.in_cache?(nil) == false
      assert Cache.in_cache?("not-a-number") == false
    end

    test "respects cache_enabled? setting" do
      # When cache is disabled, should return false without checking
      stub(MockFeatures, :cache_enabled?, fn -> false end)

      # MockKillmail.exists? should not be called
      assert Cache.in_cache?(@killmail_id) == false
    end
  end

  describe "cache/1" do
    test "successfully caches a killmail" do
      expect(MockKillmail, :put, fn killmail ->
        assert killmail.killmail_id == @killmail_id
        {:ok, @killmail_id}
      end)

      assert {:ok, cached_killmail} = Cache.cache(@test_killmail)
      assert cached_killmail.killmail_id == @killmail_id
    end

    test "respects cache_enabled? setting" do
      # When cache is disabled, should skip caching
      stub(MockFeatures, :cache_enabled?, fn -> false end)

      # MockKillmail.put should not be called
      assert {:ok, killmail} = Cache.cache(@test_killmail)
      assert killmail.killmail_id == @killmail_id
    end

    test "handles cache errors gracefully" do
      # Even when caching fails, the function should return success
      # to allow processing to continue
      expect(MockKillmail, :put, fn _ ->
        {:error, :cache_failure}
      end)

      assert {:ok, killmail} = Cache.cache(@test_killmail)
      assert killmail.killmail_id == @killmail_id
    end
  end
end
