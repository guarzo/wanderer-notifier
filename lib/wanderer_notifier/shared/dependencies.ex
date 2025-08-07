defmodule WandererNotifier.Shared.Dependencies do
  @moduledoc """
  Simplified dependency resolution using application configuration.
  Replaces the complex DependencyRegistry GenServer.

  This module provides a clean interface for dependency injection
  without the overhead of a GenServer or complex state management.
  Dependencies can be overridden via application configuration for testing.
  """

  @doc """
  Get a service implementation with fallback to default.

  ## Examples

      iex> Dependencies.get(:cache_module, WandererNotifier.Infrastructure.Cache)
      WandererNotifier.Infrastructure.Cache
      
      iex> Application.put_env(:wanderer_notifier, :cache_module, MockCache)
      iex> Dependencies.get(:cache_module, WandererNotifier.Infrastructure.Cache)
      MockCache
  """
  @spec get(atom(), module()) :: module()
  def get(service_key, default_module) do
    Application.get_env(:wanderer_notifier, service_key, default_module)
  end

  # Pre-configured service getters for common dependencies

  @doc "Get the cache module implementation"
  @spec cache() :: module()
  def cache, do: get(:cache_module, WandererNotifier.Infrastructure.Cache)

  @doc "Get the HTTP client implementation"
  @spec http() :: module()
  def http, do: get(:http_client, WandererNotifier.Infrastructure.Http)

  @doc "Get the Discord client implementation"
  @spec discord() :: module()
  def discord, do: get(:discord_client, WandererNotifier.DiscordNotifier)

  @doc "Get the ESI service implementation"
  @spec esi() :: module()
  def esi, do: get(:esi_service, WandererNotifier.Infrastructure.Adapters.ESI.Service)

  @doc "Get the ESI client implementation"
  @spec esi_client() :: module()
  def esi_client, do: get(:esi_client, WandererNotifier.Infrastructure.Adapters.ESI.Client)

  @doc "Get the deduplication service implementation"
  @spec deduplication() :: module()
  def deduplication,
    do: get(:deduplication_module, WandererNotifier.Domains.Notifications.CacheImpl)

  @doc "Get the license service implementation"
  @spec license() :: module()
  def license, do: get(:license_service, WandererNotifier.Domains.License.LicenseService)

  @doc "Get the logger module implementation"
  @spec logger() :: module()
  def logger, do: get(:logger_module, Logger)

  @doc "Get the persistent values implementation"
  @spec persistent_values() :: module()
  def persistent_values, do: get(:persistent_values_module, WandererNotifier.PersistentValues)

  @doc "Get the killmail pipeline implementation"
  @spec killmail_pipeline() :: module()
  def killmail_pipeline, do: get(:killmail_pipeline, WandererNotifier.Domains.Killmail.Pipeline)

  @doc "Get the cache name (atom, not module)"
  @spec cache_name() :: atom()
  def cache_name, do: Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
end
