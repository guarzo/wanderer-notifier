defmodule WandererNotifier.Shared.Types.Constants do
  @moduledoc """
  Centralized constants for WandererNotifier.
  Consolidates magic numbers, retry policies, timeouts, colors, and other constants
  that are used across multiple modules.
  """

  # ── HTTP & Network Timeouts ─────────────────────────────────────────────────

  @doc "Default HTTP request timeout in milliseconds"
  def default_timeout, do: 15_000

  @doc "Default HTTP receive timeout in milliseconds"
  def default_recv_timeout, do: 15_000

  @doc "Default HTTP connection timeout in milliseconds"
  def default_connect_timeout, do: 5_000

  @doc "Default HTTP pool timeout in milliseconds"
  def default_pool_timeout, do: 5_000

  @doc "ESI service timeout in milliseconds"
  def esi_timeout, do: 30_000

  # ── Retry Policies ──────────────────────────────────────────────────────────

  @doc "Maximum number of retries for HTTP requests"
  def max_retries, do: 3

  @doc "Base backoff delay in milliseconds"
  def base_backoff, do: 1_000

  @doc "Maximum backoff delay in milliseconds"
  def max_backoff, do: 30_000

  @doc "RedisQ specific base backoff in milliseconds"
  def redisq_base_backoff, do: 1000

  @doc "ZKill retry backoff in milliseconds"
  def zkill_retry_backoff, do: 2_000

  @doc "WandererKills retry backoff in milliseconds"
  def wanderer_kills_retry_backoff, do: 1_500

  # ── Cache & TTL Values ──────────────────────────────────────────────────────
  # Note: Cache TTL values have been moved to WandererNotifier.Infrastructure.Cache module
  # for better centralization and consistency.

  # ── Scheduler Intervals ─────────────────────────────────────────────────────

  @doc "Default application service interval in milliseconds"
  def default_service_interval, do: 30_000

  @doc "Batch log interval in milliseconds"
  def batch_log_interval, do: 5_000

  @doc "Character update scheduler interval in milliseconds"
  def character_update_interval, do: 30_000

  @doc "System update scheduler interval in milliseconds"
  def system_update_interval, do: 30_000

  @doc "License validation refresh interval in milliseconds"
  def license_refresh_interval, do: 1_200_000

  @doc "Feature flag check interval in milliseconds"
  def feature_check_interval, do: 30_000

  @doc "Service status report interval in milliseconds"
  def service_status_interval, do: 3_600_000

  @doc "Web server heartbeat check interval in milliseconds"
  def web_server_heartbeat_interval, do: 30_000

  @doc "Signature check interval in milliseconds"
  def signature_check_interval, do: 300_000

  # ── Sleep & Delay Intervals ─────────────────────────────────────────────────

  @doc "RedisQ poll interval in milliseconds"
  def redisq_poll_interval, do: 1_000

  @doc "Sleep interval for rate limiting in milliseconds"
  def rate_limit_sleep, do: 1_000

  @doc "Startup notification delay in milliseconds"
  def startup_notification_delay, do: 2_000

  @doc "Test sleep interval in milliseconds (for tests)"
  def test_sleep_interval, do: 100

  # ── Discord Colors ──────────────────────────────────────────────────────────

  @doc "Default Discord embed color (blue)"
  def default_embed_color, do: 0x3498DB

  @doc "Success color (green)"
  def success_color, do: 0x2ECC71

  @doc "Warning color (orange)"
  def warning_color, do: 0xF39C12

  @doc "Error color (red)"
  def error_color, do: 0xE74C3C

  @doc "Info color (blue)"
  def info_color, do: 0x3498DB

  # ── EVE-specific Colors ─────────────────────────────────────────────────────

  @doc "Wormhole space color"
  def wormhole_color, do: 0x428BCA

  @doc "High security space color"
  def highsec_color, do: 0x5CB85C

  @doc "Low security space color"
  def lowsec_color, do: 0xE28A0D

  @doc "Null security space color"
  def nullsec_color, do: 0xD9534F

  # ── EVE Icon URLs ───────────────────────────────────────────────────────────

  @doc "Wormhole system icon URL"
  def wormhole_icon, do: "https://images.evetech.net/types/45041/icon"

  @doc "High security system icon URL"
  def highsec_icon, do: "https://images.evetech.net/types/3802/icon"

  @doc "Low security system icon URL"
  def lowsec_icon, do: "https://images.evetech.net/types/3796/icon"

  @doc "Null security system icon URL"
  def nullsec_icon, do: "https://images.evetech.net/types/3799/icon"

  @doc "Default system icon URL"
  def default_icon, do: "https://images.evetech.net/types/3802/icon"

  # ── HTTP Status Codes ───────────────────────────────────────────────────────

  @doc "HTTP success status code"
  def success_status, do: 200

  # ── Notification Limits ─────────────────────────────────────────────────────

  @doc "Maximum rich notifications for limited licenses"
  def max_rich_notifications, do: 5

  # ── Application Settings ────────────────────────────────────────────────────

  @doc "User agent string for HTTP requests"
  def user_agent, do: "WandererNotifier/1.0"

  @doc "Default port for the application"
  def default_port, do: 4_000

  @doc "Cache key separator"
  def cache_key_separator, do: ":"

  @doc "Minimum parts required for a valid cache key"
  def min_cache_key_parts, do: 2

  # ── Retry Threshold Settings ────────────────────────────────────────────────

  @doc "Timeout threshold for considering connection issues"
  def timeout_threshold, do: 5

  # ── Helper Functions ────────────────────────────────────────────────────────

  @doc """
  Calculates exponential backoff delay based on retry count.
  Uses the formula: base_backoff * 2^(retry_count - 1)
  """
  @spec calculate_backoff(non_neg_integer(), non_neg_integer() | nil) :: non_neg_integer()
  def calculate_backoff(retry_count, base_backoff_value \\ nil) do
    base = base_backoff_value || base_backoff()
    calculated = base * :math.pow(2, retry_count - 1)
    min(trunc(calculated), max_backoff())
  end

  @doc """
  Returns the appropriate color for a security status.
  """
  @spec security_color(float()) :: integer()
  def security_color(security) when security >= 0.5, do: highsec_color()
  def security_color(security) when security > 0.0, do: lowsec_color()
  def security_color(_), do: nullsec_color()

  @doc """
  Returns the appropriate icon URL for a security status.
  """
  @spec security_icon(float()) :: String.t()
  def security_icon(security) when security >= 0.5, do: highsec_icon()
  def security_icon(security) when security > 0.0, do: lowsec_icon()
  def security_icon(_), do: nullsec_icon()

  @doc """
  Returns the retry policy for RedisQ requests.
  """
  def redisq_retry_policy do
    %{
      # 1 second
      base_backoff: 1000,
      # 30 seconds
      max_backoff: 30_000,
      # 10% jitter
      jitter: 0.1
    }
  end
end
