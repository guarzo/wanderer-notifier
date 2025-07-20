defmodule CacheBench do
  use Benchfella
  alias WandererNotifier.Infrastructure.Cache

  @character_id 123456
  @test_character_data %{
    name: "Test Character",
    corporation_id: 98553333,
    alliance_id: 99000123
  }

  setup_all do
    # Start cache if not running
    case Cachex.start_link(:cache_bench, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      error -> error
    end

    # Warm cache with test data
    Cache.put_character(@character_id, @test_character_data)
    Cache.put_system(30000142, %{name: "Jita", security: 0.9})
    Cache.put("test:key", "test_value")
    
    {:ok, []}
  end

  bench "cache get character" do
    Cache.get_character(@character_id)
  end

  bench "cache put character" do
    Cache.put_character(@character_id, @test_character_data)
  end

  bench "cache key generation character" do
    WandererNotifier.Infrastructure.Cache.Keys.character(@character_id)
  end

  bench "cache key generation system" do
    WandererNotifier.Infrastructure.Cache.Keys.system(30000142)
  end

  bench "cache generic get" do
    Cache.get("test:key")
  end

  bench "cache generic put" do
    Cache.put("bench:key", "bench_value", :timer.minutes(5))
  end

  bench "cache get system" do
    Cache.get_system(30000142)
  end

  bench "cache put system" do
    Cache.put_system(30000142, %{name: "Jita", security: 0.9})
  end
end