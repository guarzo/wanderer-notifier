defmodule WandererNotifier.Config.Timing do
  @moduledoc """
  Configuration module for timing-related settings.
  Handles intervals, schedules, and TTLs.
  """

  require Logger

  @doc """
  Gets the systems cache TTL in seconds.
  """
  @spec get_systems_cache_ttl() :: integer()
  def get_systems_cache_ttl do
    get_env(:systems_cache_ttl, 300)
  end

  @doc """
  Gets the systems update interval in milliseconds.
  Defaults to 5 minutes.
  """
  @spec get_systems_update_interval() :: integer()
  def get_systems_update_interval do
    get_env(:systems_update_interval, 300_000)
  end

  @doc """
  Gets the chart service hour configuration.
  Defaults to 12 (UTC).
  """
  @spec get_chart_service_hour() :: integer()
  def get_chart_service_hour do
    get_env(:chart_service_hour, 12)
  end

  @doc """
  Gets the chart service minute configuration.
  Defaults to 0.
  """
  @spec get_chart_service_minute() :: integer()
  def get_chart_service_minute do
    get_env(:chart_service_minute, 0)
  end

  @doc """
  Gets the persistence configuration.
  """
  @spec get_persistence_config() :: Keyword.t()
  def get_persistence_config do
    get_env(:persistence, [])
  end

  @doc """
  Gets the maintenance interval in milliseconds.
  Defaults to 1 minute.
  """
  @spec get_maintenance_interval() :: integer()
  def get_maintenance_interval do
    get_env(:maintenance_interval, 60_000)
  end

  @doc """
  Gets the character update interval in milliseconds.
  Defaults to 30 seconds.
  """
  @spec get_character_update_interval() :: integer()
  def get_character_update_interval do
    get_env(:character_update_interval, 30_000)
  end

  @doc """
  Gets the cache check interval in milliseconds.
  Defaults to 5 seconds.
  """
  @spec get_cache_check_interval() :: integer()
  def get_cache_check_interval do
    get_env(:cache_check_interval, 5_000)
  end

  @doc """
  Gets the cache sync interval in milliseconds.
  Defaults to 1 minute.
  """
  @spec get_cache_sync_interval() :: integer()
  def get_cache_sync_interval do
    get_env(:cache_sync_interval, 60_000)
  end

  @doc """
  Gets the cache cleanup interval in milliseconds.
  Defaults to 1 minute.
  """
  @spec get_cache_cleanup_interval() :: integer()
  def get_cache_cleanup_interval do
    get_env(:cache_cleanup_interval, 60_000)
  end

  @doc """
  Gets the forced kill interval in seconds.
  Defaults to 5 minutes.
  """
  @spec get_forced_kill_interval() :: integer()
  def get_forced_kill_interval do
    get_env(:forced_kill_interval, 300)
  end

  @doc """
  Gets the WebSocket heartbeat interval in milliseconds.
  Defaults to 10 seconds.
  """
  @spec get_websocket_heartbeat_interval() :: integer()
  def get_websocket_heartbeat_interval do
    get_env(:websocket_heartbeat_interval, 10_000)
  end

  @doc """
  Gets the reconnect delay in milliseconds.
  Defaults to 10 seconds.
  """
  @spec get_reconnect_delay() :: integer()
  def get_reconnect_delay do
    get_env(:reconnect_delay, 10_000)
  end

  @doc """
  Gets the license refresh interval in milliseconds.
  Defaults to 1 hour.
  """
  @spec get_license_refresh_interval() :: integer()
  def get_license_refresh_interval do
    get_env(:license_refresh_interval, :timer.hours(1))
  end

  @doc """
  Gets the activity chart interval in milliseconds.
  Defaults to 24 hours.
  """
  @spec get_activity_chart_interval() :: integer()
  def get_activity_chart_interval do
    get_env(:activity_chart_interval, 24 * 60 * 60 * 1000)
  end

  @doc """
  Gets the character update scheduler interval in milliseconds.
  Defaults to 30 minutes.
  """
  @spec get_character_update_scheduler_interval() :: integer()
  def get_character_update_scheduler_interval do
    get_env(:character_update_scheduler_interval, 30 * 60 * 1000)
  end

  @doc """
  Gets the system update scheduler interval in milliseconds.
  Defaults to 60 minutes.
  """
  @spec get_system_update_scheduler_interval() :: integer()
  def get_system_update_scheduler_interval do
    get_env(:system_update_scheduler_interval, 60 * 60 * 1000)
  end

  @doc """
  Get the timing configuration.
  """
  @spec get_timing_config() :: {:ok, map()}
  def get_timing_config do
    {:ok, get_env(:timing, %{})}
  end

  defp get_env(key, default) do
    Application.get_env(:wanderer_notifier, key, default)
  end
end
