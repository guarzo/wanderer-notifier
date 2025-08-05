defmodule WandererNotifier.Infrastructure.RateLimiter do
  @moduledoc """
  Rate limiter using Hammer library.

  This module wraps Hammer v7 to provide rate limiting functionality
  for the HTTP middleware and other parts of the application.
  """

  use Hammer, backend: :ets
end
