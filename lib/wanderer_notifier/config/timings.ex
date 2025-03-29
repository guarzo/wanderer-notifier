defmodule WandererNotifier.Config.Timings do
  @moduledoc """
  Centralized configuration for all timing-related settings in the application.
  This includes cache TTLs, maintenance intervals, scheduler timings, and other time-based configurations.

  This module serves as a central reference for all timing-related values in the application,
  making it easier to manage and adjust these values without having to search through the codebase.
  """

  @doc """
  Get the cache TTL for systems.
  Default: 24 hours
  """
  def systems_cache_ttl do
    get_env(:systems_cache_ttl, 24 * 60 * 60)
  end

  @doc """
  Get the cache TTL for characters.
  Default: 24 hours
  """
  def characters_cache_ttl do
    get_env(:characters_cache_ttl, 300)
  end

  @doc """
  Get the cache TTL for static info.
  Default: 1 week
  """
  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 86_400)
  end

  @doc """
  Get the maintenance interval.
  Default: 1 hour
  """
  def maintenance_interval do
    get_env(:maintenance_interval, 300_000)
  end

  @doc """
  Get the reconnect delay.
  Default: 5 seconds
  """
  def reconnect_delay do
    get_env(:reconnect_delay, 5000)
  end

  @doc """
  Get the interval for status updates.
  Default: 30 seconds
  """
  def status_update_interval do
    get_env(:status_update_interval, 30)
  end

  @doc """
  Get the interval for systems updates.
  Default: 30 seconds
  """
  def systems_update_interval do
    get_env(:systems_update_interval, 30)
  end

  @doc """
  Get the interval for character updates.
  Default: 30 seconds
  """
  def character_update_interval do
    get_env(:character_update_interval, 30)
  end

  @doc """
  Get the interval for cache availability checks.
  Default: 5 seconds
  """
  def cache_check_interval do
    get_env(:cache_check_interval, 5000)
  end

  @doc """
  Get the interval for cache disk sync.
  Default: 1 minute
  """
  def cache_sync_interval do
    get_env(:cache_sync_interval, 60_000)
  end

  @doc """
  Get the interval for cache expired entry cleanup.
  Default: 1 minute
  """
  def cache_cleanup_interval do
    get_env(:cache_cleanup_interval, 60_000)
  end

  @doc """
  Get the maximum number of retries for cache operations.
  Default: 3
  """
  def max_retries do
    get_env(:max_retries, 3)
  end

  @doc """
  Get the delay between retries for cache operations.
  Default: 1 second
  """
  def retry_delay do
    get_env(:retry_delay, 1000)
  end

  @doc """
  Get the interval between forced kill notifications.
  Default: 5 minutes
  """
  def forced_kill_interval do
    get_env(:forced_kill_interval, 300)
  end

  @doc """
  Get the interval for WebSocket heartbeat.
  Default: 10 seconds
  """
  def websocket_heartbeat_interval do
    get_env(:websocket_heartbeat_interval, 10_000)
  end

  @doc """
  Get the interval for license refresh.
  Default: 1 hour
  """
  def license_refresh_interval do
    get_env(:license_refresh_interval, :timer.hours(1))
  end

  @doc """
  Get the interval for activity chart generation and sending.
  Default: 24 hours
  """
  def activity_chart_interval do
    get_env(:activity_chart_interval, 24 * 60 * 60 * 1000)
  end

  @doc """
  Get the hour for TPS chart generation and sending (UTC).
  Default: 12
  """
  def tps_chart_hour do
    get_env(:tps_chart_hour, 12)
  end

  @doc """
  Get the minute for TPS chart generation and sending (UTC).
  Default: 0
  """
  def tps_chart_minute do
    get_env(:tps_chart_minute, 0)
  end

  @doc """
  Get the interval for character data updates.
  Default: 1 minute
  """
  def character_update_scheduler_interval do
    get_env(:character_update_scheduler_interval, 1 * 60 * 1000)
  end

  @doc """
  Get the interval for system data updates.
  Default: 1 minute
  """
  def system_update_scheduler_interval do
    get_env(:system_update_scheduler_interval, 1 * 60 * 1000)
  end

  @doc """
  Returns a map of all scheduler configurations for easier reference.
  """
  def scheduler_configs do
    %{
      activity_chart: %{
        type: :interval,
        interval: activity_chart_interval(),
        description: "Character activity chart generation"
      },
      tps_chart: %{
        type: :time,
        hour: tps_chart_hour(),
        minute: tps_chart_minute(),
        description: "TPS chart generation"
      },
      character_update: %{
        type: :interval,
        interval: character_update_scheduler_interval(),
        description: "Character data updates"
      },
      system_update: %{
        type: :interval,
        interval: system_update_scheduler_interval(),
        description: "System data updates"
      }
    }
  end

  @doc """
  Returns a map of all cache TTLs for easier reference.
  """
  def cache_ttls do
    %{
      systems: %{
        ttl: systems_cache_ttl(),
        description: "Solar systems data"
      },
      characters: %{
        ttl: characters_cache_ttl(),
        description: "Character data"
      },
      static_info: %{
        ttl: static_info_cache_ttl(),
        description: "Static system information"
      }
    }
  end

  # Helper function to get environment variables
  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
