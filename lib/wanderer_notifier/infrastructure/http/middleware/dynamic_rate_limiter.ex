defmodule WandererNotifier.Infrastructure.Http.Middleware.DynamicRateLimiter do
  @behaviour WandererNotifier.Infrastructure.Http.Middleware.MiddlewareBehaviour
  require Logger

  @moduledoc """
  Dynamic rate limiter middleware that adjusts request pacing based on response headers.

  This module implements provider-specific rate limiting strategies:

  ## ESI Rate Limiting
  - Uses X-ESI-Error-Limit-Remain and X-ESI-Error-Limit-Reset headers
  - Adjusts request timing to avoid hitting limits
  - Implements backoff based on remaining requests

  ## Discord Rate Limiting  
  - Uses X-RateLimit-* headers for bucket-based rate limiting
  - Enforces 5 requests per 2 seconds per webhook URL
  - Respects global 50 requests per second limit
  - Handles per-route buckets as indicated by headers

  ## Usage
  The middleware is automatically applied when service-specific configurations
  are used and will override static rate limiting with header-driven pacing.
  """

  alias WandererNotifier.Infrastructure.Http.Utils.HttpUtils
  alias WandererNotifier.Infrastructure.Cache

  @type rate_limit_info :: %{
          remaining: non_neg_integer(),
          reset_at: non_neg_integer(),
          bucket: String.t() | nil,
          global_limit: boolean()
        }

  # ESI constants
  @esi_error_limit_remain "X-ESI-Error-Limit-Remain"
  @esi_error_limit_reset "X-ESI-Error-Limit-Reset"
  @esi_default_limit 100

  # Discord constants
  @discord_ratelimit_remaining "X-RateLimit-Remaining"
  @discord_ratelimit_reset "X-RateLimit-Reset"
  @discord_ratelimit_reset_after "X-RateLimit-Reset-After"
  @discord_ratelimit_bucket "X-RateLimit-Bucket"
  @discord_ratelimit_global "X-RateLimit-Global"
  @discord_webhook_limit 5
  @discord_webhook_window 2000

  @doc """
  Middleware entry point that applies dynamic rate limiting based on service type.
  """
  @impl true
  def call(request, next) do
    options = Map.get(request, :opts, [])
    service = Keyword.get(options, :service)

    case service do
      :esi ->
        handle_esi_request(request, next)

      :discord ->
        handle_discord_request(request, next)

      _ ->
        # For other services, pass through to next middleware
        next.(request)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # ESI Rate Limiting Implementation
  # ═══════════════════════════════════════════════════════════════════════════════

  defp handle_esi_request(request, next) do
    host = HttpUtils.extract_host(request.url)
    cache_key = "esi_rate_limit:#{host}"

    # Check if we need to wait based on previous responses
    case check_esi_rate_limit(cache_key) do
      :ok ->
        # Proceed with request and update rate limit info from response
        result = next.(request)
        update_esi_rate_limit(result, cache_key)
        result

      {:wait, delay_ms} ->
        Logger.info("ESI rate limit: waiting #{delay_ms}ms for #{host}")
        Process.sleep(delay_ms)
        # Retry after waiting
        result = next.(request)
        update_esi_rate_limit(result, cache_key)
        result
    end
  end

  defp check_esi_rate_limit(cache_key) do
    case Cache.get(cache_key) do
      {:error, :not_found} ->
        :ok

      {:ok, %{remaining: remaining, reset_at: reset_at}} ->
        current_time = System.system_time(:second)

        cond do
          # Reset time has passed, allow request
          current_time >= reset_at ->
            :ok

          # Very low remaining requests, implement backoff
          remaining <= 5 ->
            delay = calculate_esi_backoff(remaining, reset_at - current_time)
            {:wait, delay}

          # Sufficient requests remaining
          true ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp calculate_esi_backoff(remaining, seconds_until_reset) do
    cond do
      remaining <= 1 ->
        # Critical: wait until reset
        seconds_until_reset * 1000

      remaining <= 3 ->
        # Very low: wait 30% of remaining time
        round(seconds_until_reset * 1000 * 0.3)

      remaining <= 5 ->
        # Low: wait 10% of remaining time
        round(seconds_until_reset * 1000 * 0.1)

      true ->
        0
    end
  end

  defp update_esi_rate_limit({:ok, response}, cache_key) do
    case parse_esi_headers(response.headers) do
      {:ok, rate_limit_info} ->
        # Cache the rate limit info with TTL until reset
        ttl_seconds = max(rate_limit_info.reset_at - System.system_time(:second), 1)
        Cache.put(cache_key, rate_limit_info, :timer.seconds(ttl_seconds))

        Logger.debug("ESI rate limit updated: #{inspect(rate_limit_info)}")

      {:error, reason} ->
        Logger.debug("Could not parse ESI rate limit headers: #{reason}")
    end
  end

  defp update_esi_rate_limit(_result, _cache_key), do: :ok

  defp parse_esi_headers(headers) do
    remain_header = find_header(headers, @esi_error_limit_remain)
    reset_header = find_header(headers, @esi_error_limit_reset)

    case {remain_header, reset_header} do
      {nil, nil} ->
        {:error, "ESI rate limit headers not found"}

      {remain_str, reset_str} ->
        with {:ok, remaining} <- parse_integer(remain_str, @esi_default_limit),
             {:ok, reset_at} <- parse_integer(reset_str, System.system_time(:second) + 60) do
          {:ok,
           %{
             remaining: remaining,
             reset_at: reset_at,
             bucket: nil,
             global_limit: false
           }}
        else
          {:error, reason} -> {:error, "Failed to parse ESI headers: #{reason}"}
        end
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Discord Rate Limiting Implementation
  # ═══════════════════════════════════════════════════════════════════════════════

  defp handle_discord_request(request, next) do
    url = request.url

    # Extract webhook URL for per-webhook rate limiting
    webhook_id = extract_webhook_id(url)
    global_cache_key = "discord_rate_limit:global"
    webhook_cache_key = if webhook_id, do: "discord_rate_limit:webhook:#{webhook_id}", else: nil

    # Check both global and webhook-specific limits
    case check_discord_rate_limits(global_cache_key, webhook_cache_key) do
      :ok ->
        # Proceed with request and update rate limit info from response
        result = next.(request)
        update_discord_rate_limit(result, global_cache_key, webhook_cache_key, url)
        result

      {:wait, delay_ms, reason} ->
        Logger.info("Discord rate limit: waiting #{delay_ms}ms (#{reason})")
        Process.sleep(delay_ms)
        # Retry after waiting
        result = next.(request)
        update_discord_rate_limit(result, global_cache_key, webhook_cache_key, url)
        result
    end
  end

  defp check_discord_rate_limits(global_key, webhook_key) do
    global_check = check_discord_global_limit(global_key)
    webhook_check = if webhook_key, do: check_discord_webhook_limit(webhook_key), else: :ok

    case {global_check, webhook_check} do
      {:ok, :ok} ->
        :ok

      {{:wait, delay, reason}, :ok} ->
        {:wait, delay, reason}

      {:ok, {:wait, delay, reason}} ->
        {:wait, delay, reason}

      {{:wait, global_delay, _}, {:wait, webhook_delay, webhook_reason}} ->
        {:wait, max(global_delay, webhook_delay), webhook_reason}
    end
  end

  defp check_discord_global_limit(cache_key) do
    case Cache.get(cache_key) do
      {:error, :not_found} ->
        :ok

      {:ok, %{remaining: remaining, reset_at: reset_at}} ->
        current_time = System.system_time(:millisecond)

        cond do
          current_time >= reset_at -> :ok
          remaining <= 1 -> {:wait, reset_at - current_time, "global limit"}
          true -> :ok
        end

      _ ->
        :ok
    end
  end

  defp check_discord_webhook_limit(cache_key) do
    case Cache.get(cache_key) do
      {:error, :not_found} -> :ok
      {:ok, webhook_data} -> validate_webhook_window(webhook_data)
    end
  end

  defp validate_webhook_window(%{requests: requests, window_start: window_start}) do
    current_time = System.system_time(:millisecond)

    case current_time - window_start < @discord_webhook_window do
      true -> check_webhook_request_limit(requests, current_time, window_start)
      false -> :ok
    end
  end

  defp check_webhook_request_limit(requests, current_time, window_start) do
    if requests >= @discord_webhook_limit do
      # Wait for the window to reset
      wait_time = @discord_webhook_window - (current_time - window_start)
      {:wait, wait_time, "webhook limit (5/2s)"}
    else
      :ok
    end
  end

  defp update_discord_rate_limit({:ok, response}, global_key, webhook_key, url) do
    case parse_discord_headers(response.headers) do
      {:ok, rate_limit_info} ->
        update_discord_global_cache(global_key, rate_limit_info)
        if webhook_key, do: update_discord_webhook_cache(webhook_key, rate_limit_info)

        Logger.debug("Discord rate limit updated for #{url}: #{inspect(rate_limit_info)}")

      {:error, reason} ->
        Logger.debug("Could not parse Discord rate limit headers: #{reason}")
    end
  end

  defp update_discord_rate_limit(_result, _global_key, _webhook_key, _url), do: :ok

  defp update_discord_global_cache(cache_key, rate_limit_info) do
    if rate_limit_info.global_limit do
      ttl_ms = max(rate_limit_info.reset_at - System.system_time(:millisecond), 1000)
      Cache.put(cache_key, rate_limit_info, ttl_ms)
    end
  end

  defp update_discord_webhook_cache(cache_key, _rate_limit_info) do
    # Update webhook-specific tracking (5 requests per 2 seconds)
    # Use atomic update_windowed_counter for thread-safe rate limit tracking
    case Cache.update_windowed_counter(
           cache_key,
           @discord_webhook_window,
           @discord_webhook_window
         ) do
      {:ok, _updated_value} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to update Discord webhook rate limit cache",
          cache_key: cache_key,
          error: inspect(reason)
        )

        :ok
    end
  end

  defp parse_discord_headers(headers) do
    header_map = extract_discord_headers(headers)

    case validate_required_headers(header_map) do
      :ok -> build_discord_response(header_map)
      error -> error
    end
  end

  defp extract_discord_headers(headers) do
    %{
      remaining: find_header(headers, @discord_ratelimit_remaining),
      reset: find_header(headers, @discord_ratelimit_reset),
      reset_after: find_header(headers, @discord_ratelimit_reset_after),
      bucket: find_header(headers, @discord_ratelimit_bucket),
      global: find_header(headers, @discord_ratelimit_global)
    }
  end

  defp validate_required_headers(%{remaining: remaining, reset: reset, reset_after: reset_after}) do
    case remaining != nil and (reset != nil or reset_after != nil) do
      true -> :ok
      false -> {:error, "Discord rate limit headers not found"}
    end
  end

  defp build_discord_response(header_map) do
    with {:ok, remaining_val} <- parse_integer(header_map.remaining, 0),
         {:ok, reset_at} <- parse_discord_reset(header_map.reset, header_map.reset_after) do
      {:ok,
       %{
         remaining: remaining_val,
         reset_at: reset_at,
         bucket: header_map.bucket,
         global_limit: header_map.global == "true"
       }}
    else
      {:error, reason} -> {:error, "Failed to parse Discord headers: #{reason}"}
    end
  end

  defp parse_discord_reset(reset_header, reset_after_header) do
    if reset_header != nil do
      # X-RateLimit-Reset is Unix timestamp in seconds
      case parse_integer(reset_header, 0) do
        {:ok, reset_seconds} -> {:ok, reset_seconds * 1000}
      end
    else
      parse_reset_after_header(reset_after_header)
    end
  end

  defp parse_reset_after_header(nil), do: {:error, "No reset header found"}

  defp parse_reset_after_header(reset_after_header) do
    # X-RateLimit-Reset-After is seconds from now
    case parse_integer(reset_after_header, 0) do
      {:ok, reset_after_seconds} ->
        {:ok, System.system_time(:millisecond) + reset_after_seconds * 1000}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════════

  defp extract_webhook_id(url) do
    case Regex.run(~r/webhooks\/(\d+)\//, url) do
      [_, webhook_id] -> webhook_id
      _ -> nil
    end
  end

  defp find_header(headers, header_name) do
    case Enum.find(headers, fn {key, _} ->
           String.downcase(key) == String.downcase(header_name)
         end) do
      {_, value} -> value
      nil -> nil
    end
  end

  defp parse_integer(nil, default), do: {:ok, default}
  defp parse_integer(value, _default) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:ok, default}
    end
  end

  defp parse_integer(value, default) when is_list(value) and value != [] do
    case List.first(value) do
      val when is_binary(val) -> parse_integer(val, default)
      val when is_integer(val) -> {:ok, val}
      _ -> {:ok, default}
    end
  end

  defp parse_integer(_, default), do: {:ok, default}
end
