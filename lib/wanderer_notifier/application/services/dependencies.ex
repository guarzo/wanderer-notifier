defmodule WandererNotifier.Application.Services.Dependencies do
  require Logger

  @moduledoc """
  Centralized dependency injection for WandererNotifier.

  This module provides a standardized approach to dependency injection across
  the entire application. It allows for easy testing by swapping out dependencies
  via application configuration.

  ## Usage

  Instead of calling Application.get_env directly in modules, use the functions
  provided by this module:

      # Instead of:
      Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.Infrastructure.Adapters.ESI.Service)

      # Use:
      Dependencies.esi_service()

  ## Testing

  In tests, dependencies can be swapped by setting application environment variables:

      Application.put_env(:wanderer_notifier, :esi_service, MockESIService)
  """

  # Core Services
  @doc "Returns the ESI service module"
  def esi_service do
    Application.get_env(
      :wanderer_notifier,
      :esi_service,
      WandererNotifier.Infrastructure.Adapters.ESI.Service
    )
  end

  @doc "Returns the ESI client module"
  def esi_client do
    Application.get_env(
      :wanderer_notifier,
      :esi_client,
      WandererNotifier.Infrastructure.Adapters.ESI.Client
    )
  end

  @doc "Returns the HTTP client module"
  def http_client do
    Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.Http)
  end

  # Configuration and Tracking Modules

  @doc "Returns the system tracking module"
  def system_module do
    WandererNotifier.Shared.Config.system_track_module()
  end

  @doc "Returns the character tracking module"
  def character_module do
    WandererNotifier.Shared.Config.character_track_module()
  end

  # Pipeline and Processing Modules
  @doc "Returns the killmail pipeline module"
  def killmail_pipeline do
    Application.get_env(
      :wanderer_notifier,
      :killmail_pipeline,
      WandererNotifier.Domains.Killmail.Pipeline
    )
  end

  @doc "Returns the deduplication module"
  def deduplication_module do
    Application.get_env(
      :wanderer_notifier,
      :deduplication_module,
      WandererNotifier.Shared.Config.deduplication_module()
    )
  end

  # Notification Modules
  @doc "Returns the killmail cache module"
  def killmail_cache_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_cache,
      WandererNotifier.Domains.Killmail.Cache
    )
  end

  @doc "Returns the killmail notification module"
  def killmail_notification_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification_module,
      WandererNotifier.Domains.Killmail.KillmailNotification
    )
  end

  @doc "Returns the logger module"
  def logger_module do
    Application.get_env(:wanderer_notifier, :logger_module, WandererNotifier.Shared.Logger.Logger)
  end

  # Cache
  @doc "Returns the cache name"
  def cache_name do
    Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
  end
end
