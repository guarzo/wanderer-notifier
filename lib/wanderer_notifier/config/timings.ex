defmodule WandererNotifier.Config.Timings do
  @moduledoc """
  Centralized configuration for all timing-related settings in the application.
  This includes cache TTLs, maintenance intervals, scheduler timings, and other time-based configurations.

  This module serves as a central reference for all timing-related values in the application,
  making it easier to manage and adjust these values without having to search through the codebase.
  """

  # Cache TTLs (in seconds)

  @doc """
  TTL for systems cache (24 hours)
  """
  def systems_cache_ttl, do: 86_400

  @doc """
  TTL for characters cache (24 hours)
  """
  def characters_cache_ttl, do: 86_400

  @doc """
  TTL for static info cache (1 week)
  """
  def static_info_cache_ttl, do: 604_800

  # Maintenance intervals (in seconds)

  @doc """
  Interval for status updates (30 seconds)
  """
  def status_update_interval, do: 30

  @doc """
  Interval for systems updates (30 seconds)
  """
  def systems_update_interval, do: 30

  @doc """
  Interval for character updates (30 seconds)
  """
  def character_update_interval, do: 30

  # Cache check intervals (in milliseconds)

  @doc """
  Interval for cache availability checks (5 seconds)
  """
  def cache_check_interval, do: 5000

  @doc """
  Interval for cache disk sync (1 minute)
  """
  def cache_sync_interval, do: 60_000

  @doc """
  Interval for cache expired entry cleanup (1 minute)
  """
  def cache_cleanup_interval, do: 60_000

  # Retry configurations

  @doc """
  Maximum number of retries for cache operations
  """
  def max_retries, do: 3

  @doc """
  Delay between retries for cache operations (in milliseconds)
  """
  def retry_delay, do: 1000

  # Forced kill notification interval

  @doc """
  Interval between forced kill notifications (5 minutes)
  """
  def forced_kill_interval, do: 300

  # WebSocket intervals

  @doc """
  Interval for WebSocket heartbeat (10 seconds)
  """
  def websocket_heartbeat_interval, do: 10_000

  @doc """
  Interval for service maintenance (60 seconds)
  """
  def maintenance_interval, do: 60_000

  @doc """
  Delay before reconnecting to WebSocket (10 seconds)
  """
  def reconnect_delay, do: 10_000

  @doc """
  Interval for license refresh (1 hours)
  """
  def license_refresh_interval, do: :timer.hours(1)

  # Scheduler configurations (in milliseconds)

  @doc """
  Interval for activity chart generation and sending (24 hours)
  """
  def activity_chart_interval, do: 24 * 60 * 60 * 1000

  @doc """
  Hour for TPS chart generation and sending (UTC, 12:00)
  """
  def tps_chart_hour, do: 12

  @doc """
  Minute for TPS chart generation and sending (UTC, 00)
  """
  def tps_chart_minute, do: 0

  @doc """
  Interval for character data updates (30 minutes)
  """
  def character_update_scheduler_interval, do: 1 * 60 * 1000

  @doc """
  Interval for system data updates (60 minutes)
  """
  def system_update_scheduler_interval, do: 1 * 60 * 1000

  @doc """
  Returns a map of all scheduler configurations for easier reference
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
  Returns a map of all cache TTLs for easier reference
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
end
