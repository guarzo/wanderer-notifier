defmodule WandererNotifier.Config.Timings do
  @moduledoc """
  Centralized configuration for all timing-related settings in the application.
  This includes cache TTLs, maintenance intervals, and other time-based configurations.
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
  Interval for status updates (5 minutes)
  """
  def status_update_interval, do: 30

  @doc """
  Interval for systems updates (5 minutes)
  """
  def systems_update_interval, do: 30

  @doc """
  Interval for character updates (5 minutes)
  """
  def character_update_interval, do: 30

  @doc """
  Interval for backup kills checks (30 minutes)
  """
  def backup_kills_interval, do: 1800

  @doc """
  Required uptime before starting backup kills checks (1 hour)
  """
  def uptime_required_for_backup, do: 3600

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
end
