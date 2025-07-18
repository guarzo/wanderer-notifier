defmodule WandererNotifier.RateLimiter do
  @moduledoc """
  Rate limiter module using Hammer library for HTTP requests.

  This module provides a centralized rate limiting service that can be used
  across the application to prevent API abuse and respect external service
  rate limits.
  """

  use Hammer, backend: :ets

  @doc """
  Checks if a request is allowed based on the rate limit configuration.

  Returns `{:allow, count}` if the request is allowed, or `{:deny, timeout}` if rate limited.
  """
  def check_rate(key, scale_ms, limit) do
    hit(key, scale_ms, limit)
  end
end
