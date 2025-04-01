defmodule WandererNotifier.Config.CacheConfig do
  @moduledoc """
  Configuration for cache-related settings.
  """

  @doc """
  Gets the TTL for systems cache in seconds.
  Defaults to 1 hour if not configured.
  """
  def systems_cache_ttl do
    Application.get_env(:wanderer_notifier, :systems_cache_ttl, 3600)
  end
end
