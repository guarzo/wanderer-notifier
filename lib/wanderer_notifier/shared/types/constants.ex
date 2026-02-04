defmodule WandererNotifier.Shared.Types.Constants do
  @moduledoc """
  Application-wide constants for WandererNotifier.

  Contains retry policies, timeouts, and scheduler intervals used across multiple modules.
  """

  # ── Retry Policies ──────────────────────────────────────────────────────────

  @doc "Maximum number of retries for HTTP requests"
  def max_retries, do: 3

  @doc "Base backoff delay in milliseconds"
  def base_backoff, do: 1_000

  @doc "Maximum backoff delay in milliseconds"
  def max_backoff, do: 30_000

  # ── Scheduler Intervals ─────────────────────────────────────────────────────

  @doc "Default application service interval in milliseconds"
  def default_service_interval, do: 30_000

  @doc "Feature flag check interval in milliseconds"
  def feature_check_interval, do: 30_000

  @doc "Service status report interval in milliseconds"
  def service_status_interval, do: 3_600_000

  # ── Application Settings ────────────────────────────────────────────────────

  @doc "User agent string for HTTP requests"
  def user_agent, do: "WandererNotifier/1.0"
end
