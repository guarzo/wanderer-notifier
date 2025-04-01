defmodule WandererNotifier.Config.Timings do
  @moduledoc """
  Centralized configuration for all timing-related settings in the application.

  This module provides access to all time-based configuration including:
  - Cache TTLs
  - Update intervals
  - Maintenance schedules
  - Reconnection delays
  - Scheduler timings

  All functions follow a consistent naming pattern and provide proper typespecs.
  Default values are documented with each function.
  """

  @doc """
  Returns the complete timings configuration map.
  """
  @spec config() :: map()
  def config do
    %{
      cache: cache_ttls(),
      intervals: %{
        systems_update: systems_update_interval(),
        character_update: character_update_interval(),
        maintenance: maintenance_interval(),
        activity_chart: activity_chart_interval(),
        license_refresh: license_refresh_interval(),
        websocket_heartbeat: websocket_heartbeat_interval(),
        cache_check: cache_check_interval(),
        cache_sync: cache_sync_interval(),
        cache_cleanup: cache_cleanup_interval(),
        reconnect_delay: reconnect_delay(),
        forced_kill: forced_kill_interval()
      },
      schedulers: scheduler_configs()
    }
  end

  #
  # Cache TTL functions
  #

  @doc """
  Returns the systems cache TTL in seconds.
  Default: 24 hours (86400 seconds)
  """
  @spec systems_cache_ttl() :: integer()
  def systems_cache_ttl do
    # 24 hours in seconds
    get_env(:systems_cache_ttl, 86_400)
  end

  @doc """
  Returns the characters cache TTL in seconds.
  Default: 24 hours (86400 seconds)
  """
  @spec characters_cache_ttl() :: integer()
  def characters_cache_ttl do
    get_env(:characters_cache_ttl, 86_400)
  end

  @doc """
  Returns the static info cache TTL in seconds.
  Default: 24 hours (86400 seconds)
  """
  @spec static_info_cache_ttl() :: integer()
  def static_info_cache_ttl do
    get_env(:static_info_cache_ttl, 86_400)
  end

  @doc """
  Returns a map of all cache TTLs for easier reference.
  """
  @spec cache_ttls() :: map()
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

  #
  # Update interval functions
  #

  @doc """
  Returns the systems update interval in milliseconds.
  Default: 5 minutes (300,000 ms)
  """
  @spec systems_update_interval() :: integer()
  def systems_update_interval do
    get_env(:systems_update_interval, 300_000)
  end

  @doc """
  Returns the character update interval in seconds.
  Default: 10 minutes (600 seconds)
  """
  @spec character_update_interval() :: integer()
  def character_update_interval do
    get_env(:character_update_interval, 600)
  end

  @doc """
  Returns the maintenance interval in milliseconds.
  Default: 60 seconds (60,000 ms)
  """
  @spec maintenance_interval() :: integer()
  def maintenance_interval do
    get_env(:maintenance_interval, 60_000)
  end

  @doc """
  Returns the cache check interval in milliseconds.
  Default: 30 minutes (1,800,000 ms)
  """
  @spec cache_check_interval() :: integer()
  def cache_check_interval do
    get_env(:cache_check_interval, 30 * 60 * 1000)
  end

  @doc """
  Returns the cache sync interval in milliseconds.
  Default: 1 minute (60,000 ms)
  """
  @spec cache_sync_interval() :: integer()
  def cache_sync_interval do
    get_env(:cache_sync_interval, 60_000)
  end

  @doc """
  Returns the cache cleanup interval in milliseconds.
  Default: 1 minute (60,000 ms)
  """
  @spec cache_cleanup_interval() :: integer()
  def cache_cleanup_interval do
    get_env(:cache_cleanup_interval, 60_000)
  end

  @doc """
  Returns the interval between forced kill notifications in seconds.
  Default: 5 minutes (300 seconds)
  """
  @spec forced_kill_interval() :: integer()
  def forced_kill_interval do
    get_env(:forced_kill_interval, 300)
  end

  @doc """
  Returns the WebSocket heartbeat interval in milliseconds.
  Default: 10 seconds (10,000 ms)
  """
  @spec websocket_heartbeat_interval() :: integer()
  def websocket_heartbeat_interval do
    get_env(:websocket_heartbeat_interval, 10_000)
  end

  @doc """
  Returns the reconnect delay in milliseconds.
  Default: 5 seconds (5,000 ms)
  """
  @spec reconnect_delay() :: integer()
  def reconnect_delay do
    get_env(:reconnect_delay, 5_000)
  end

  @doc """
  Returns the license refresh interval in milliseconds.
  Default: 1 hour (3,600,000 ms)
  """
  @spec license_refresh_interval() :: integer()
  def license_refresh_interval do
    get_env(:license_refresh_interval, :timer.hours(1))
  end

  @doc """
  Returns the activity chart interval in milliseconds.
  Default: 24 hours (86,400,000 ms)
  """
  @spec activity_chart_interval() :: integer()
  def activity_chart_interval do
    get_env(:activity_chart_interval, 24 * 60 * 60 * 1000)
  end

  #
  # Scheduler functions
  #

  @doc """
  Returns the character update scheduler interval in milliseconds.
  Default: 30 minutes (1,800,000 ms)
  """
  @spec character_update_scheduler_interval() :: integer()
  def character_update_scheduler_interval do
    get_env(:character_update_scheduler_interval, 30 * 60 * 1000)
  end

  @doc """
  Returns the system update scheduler interval in milliseconds.
  Default: 60 minutes (3,600,000 ms)
  """
  @spec system_update_scheduler_interval() :: integer()
  def system_update_scheduler_interval do
    get_env(:system_update_scheduler_interval, 60 * 60 * 1000)
  end

  @doc """
  Returns the service status scheduler interval in milliseconds.
  Default: 24 hours (86,400,000 ms)
  """
  @spec service_status_interval() :: integer()
  def service_status_interval do
    get_env(:service_status_interval, 24 * 60 * 60 * 1000)
  end

  @doc """
  Returns the killmail retention scheduler interval in milliseconds.
  Default: 24 hours (86,400,000 ms)
  """
  @spec killmail_retention_interval() :: integer()
  def killmail_retention_interval do
    get_env(:killmail_retention_interval, 24 * 60 * 60 * 1000)
  end

  @doc """
  Returns the hour (UTC) for scheduled chart generation.
  Default: 12 (noon UTC)
  """
  @spec chart_hour() :: integer()
  def chart_hour do
    get_env(:chart_service_hour, 12)
  end

  @doc """
  Returns the minute for scheduled chart generation.
  Default: 0 (on the hour)
  """
  @spec chart_minute() :: integer()
  def chart_minute do
    get_env(:chart_service_minute, 0)
  end

  @doc """
  Returns the hour for killmail aggregation (in UTC).
  Default: 0 (midnight UTC)
  """
  @spec killmail_aggregation_hour() :: integer()
  def killmail_aggregation_hour do
    get_env(:killmail_aggregation_hour, 0)
  end

  @doc """
  Returns the minute for killmail aggregation.
  Default: 0 (on the hour)
  """
  @spec killmail_aggregation_minute() :: integer()
  def killmail_aggregation_minute do
    get_env(:killmail_aggregation_minute, 0)
  end

  @doc """
  Returns a map of all scheduler configurations for easier reference.
  """
  @spec scheduler_configs() :: map()
  def scheduler_configs do
    %{
      activity_chart: %{
        type: :interval,
        interval: activity_chart_interval(),
        description: "Character activity chart generation"
      },
      kill_chart: %{
        type: :time,
        hour: chart_hour(),
        minute: chart_minute(),
        description: "Kill chart generation"
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
  Returns the persistence configuration.
  """
  @spec persistence_config() :: Keyword.t()
  def persistence_config do
    get_env(:persistence, [])
  end

  @doc """
  Validates that all timing configuration values are valid.

  Returns :ok if the configuration is valid, or {:error, reasons} if not.
  """
  @spec validate() :: :ok | {:error, [String.t()]}
  def validate do
    errors =
      []
      |> validate_intervals()
      |> validate_ttls()
      |> validate_chart_time()

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  # Validates that all interval values are positive integers
  defp validate_intervals(errors) do
    intervals = [
      {:systems_update_interval, systems_update_interval()},
      {:character_update_interval, character_update_interval()},
      {:maintenance_interval, maintenance_interval()},
      {:cache_check_interval, cache_check_interval()},
      {:cache_sync_interval, cache_sync_interval()},
      {:cache_cleanup_interval, cache_cleanup_interval()},
      {:forced_kill_interval, forced_kill_interval()},
      {:websocket_heartbeat_interval, websocket_heartbeat_interval()},
      {:reconnect_delay, reconnect_delay()},
      {:activity_chart_interval, activity_chart_interval()},
      {:character_update_scheduler_interval, character_update_scheduler_interval()},
      {:system_update_scheduler_interval, system_update_scheduler_interval()}
    ]

    invalid_intervals =
      intervals
      |> Enum.filter(fn {_key, value} -> not (is_integer(value) and value > 0) end)
      |> Enum.map(fn {key, value} -> "Interval '#{key}' has invalid value: #{inspect(value)}" end)

    errors ++ invalid_intervals
  end

  # Validates that all TTL values are positive integers
  defp validate_ttls(errors) do
    ttls = [
      {:systems_cache_ttl, systems_cache_ttl()},
      {:characters_cache_ttl, characters_cache_ttl()},
      {:static_info_cache_ttl, static_info_cache_ttl()}
    ]

    invalid_ttls =
      ttls
      |> Enum.filter(fn {_key, value} -> not (is_integer(value) and value > 0) end)
      |> Enum.map(fn {key, value} -> "TTL '#{key}' has invalid value: #{inspect(value)}" end)

    errors ++ invalid_ttls
  end

  # Validates that chart hour and minute values are within valid ranges
  defp validate_chart_time(errors) do
    hour = chart_hour()
    minute = chart_minute()

    cond do
      not (is_integer(hour) and hour >= 0 and hour < 24) ->
        ["Chart hour must be between 0 and 23" | errors]

      not (is_integer(minute) and minute >= 0 and minute < 60) ->
        ["Chart minute must be between 0 and 59" | errors]

      true ->
        errors
    end
  end

  @doc """
  Returns the maximum number of retries for operations.
  Default: 3
  """
  @spec max_retries() :: integer()
  def max_retries do
    get_env(:max_retries, 3)
  end

  @doc """
  Returns the delay between retries in milliseconds.
  Default: 1 second (1,000 ms)
  """
  @spec retry_delay() :: integer()
  def retry_delay do
    get_env(:retry_delay, 1_000)
  end

  # Private helper to get environment variables
  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
