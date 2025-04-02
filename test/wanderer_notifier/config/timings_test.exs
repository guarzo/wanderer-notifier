defmodule WandererNotifier.Config.TimingsTest do
  use ExUnit.Case, async: false
  alias WandererNotifier.Config.Timings

  # Save the original environment before running tests
  setup do
    # Store original timing configuration
    original_config = Application.get_env(:wanderer_notifier, :systems_cache_ttl)

    # Ensure we clean up after tests run
    on_exit(fn ->
      if original_config do
        Application.put_env(:wanderer_notifier, :systems_cache_ttl, original_config)
      else
        Application.delete_env(:wanderer_notifier, :systems_cache_ttl)
      end
    end)

    :ok
  end

  describe "config/0" do
    test "returns a complete configuration map" do
      config = Timings.config()

      assert is_map(config)
      assert is_map(config.cache)
      assert is_map(config.intervals)
      assert is_map(config.schedulers)

      # Check a sample value from each section
      assert config.cache.systems.ttl == Timings.systems_cache_ttl()
      assert config.intervals.system_update == Timings.system_update_scheduler_interval()
      assert config.schedulers.activity_chart.interval == Timings.activity_chart_interval()
    end
  end

  describe "cache TTL functions" do
    test "systems_cache_ttl/0 returns the configured value or default" do
      # Test with configured value
      Application.put_env(:wanderer_notifier, :systems_cache_ttl, 9000)
      assert Timings.systems_cache_ttl() == 9000

      # Test with default value
      Application.delete_env(:wanderer_notifier, :systems_cache_ttl)
      assert Timings.systems_cache_ttl() == 86_400
    end

    test "cache_ttls/0 returns a map with all TTL configurations" do
      ttls = Timings.cache_ttls()

      assert is_map(ttls)
      assert ttls.systems.ttl == Timings.systems_cache_ttl()
      assert ttls.characters.ttl == Timings.characters_cache_ttl()
      assert ttls.static_info.ttl == Timings.static_info_cache_ttl()
      assert is_binary(ttls.systems.description)
    end
  end

  describe "interval functions" do
    test "system_update_scheduler_interval/0 returns the configured value or default" do
      # Test with configured value
      Application.put_env(:wanderer_notifier, :system_update_scheduler_interval, 60_000)
      assert Timings.system_update_scheduler_interval() == 60_000

      # Test with default value
      Application.delete_env(:wanderer_notifier, :system_update_scheduler_interval)
      assert Timings.system_update_scheduler_interval() == 30_000
    end

    test "reconnect_delay/0 returns the configured value or default" do
      # Test with configured value
      Application.put_env(:wanderer_notifier, :reconnect_delay, 10_000)
      assert Timings.reconnect_delay() == 10_000

      # Test with default value
      Application.delete_env(:wanderer_notifier, :reconnect_delay)
      assert Timings.reconnect_delay() == 5_000
    end
  end

  describe "scheduler functions" do
    test "chart_hour/0 returns the configured value or default" do
      # Test with configured value
      Application.put_env(:wanderer_notifier, :chart_service_hour, 15)
      assert Timings.chart_hour() == 15

      # Test with default value
      Application.delete_env(:wanderer_notifier, :chart_service_hour)
      assert Timings.chart_hour() == 12
    end

    test "scheduler_configs/0 returns a map with all scheduler configurations" do
      configs = Timings.scheduler_configs()

      assert is_map(configs)
      assert configs.activity_chart.type == :interval
      assert configs.kill_chart.type == :time
      assert configs.kill_chart.hour == Timings.chart_hour()
      assert configs.character_update.interval == Timings.character_update_scheduler_interval()
    end
  end

  describe "validation" do
    test "validate/0 returns :ok for valid configuration" do
      # Set valid test values
      Application.put_env(:wanderer_notifier, :system_update_scheduler_interval, 60_000)
      Application.put_env(:wanderer_notifier, :systems_cache_ttl, 86_400)
      Application.put_env(:wanderer_notifier, :chart_service_hour, 12)

      assert Timings.validate() == :ok
    end

    test "validate/0 returns error for invalid interval" do
      # Set invalid value
      Application.put_env(:wanderer_notifier, :system_update_scheduler_interval, -1)

      assert {:error, errors} = Timings.validate()
      assert Enum.any?(errors, &String.contains?(&1, "system_update_scheduler_interval"))
    end

    test "validate/0 returns error for invalid TTL" do
      # Set invalid value
      Application.put_env(:wanderer_notifier, :systems_cache_ttl, 0)

      assert {:error, errors} = Timings.validate()
      assert Enum.any?(errors, &String.contains?(&1, "systems_cache_ttl"))
    end

    test "validate/0 returns error for invalid hour" do
      # Set invalid value
      Application.put_env(:wanderer_notifier, :chart_service_hour, 25)

      assert {:error, errors} = Timings.validate()
      assert Enum.any?(errors, &String.contains?(&1, "hour must be between"))
    end
  end
end
