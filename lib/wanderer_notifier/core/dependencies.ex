defmodule WandererNotifier.Core.Dependencies do
  @moduledoc """
  Centralized dependency injection for WandererNotifier.

  This module provides a standardized approach to dependency injection across
  the entire application. It allows for easy testing by swapping out dependencies
  via application configuration.

  ## Usage

  Instead of calling Application.get_env directly in modules, use the functions
  provided by this module:

      # Instead of:
      Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)
      
      # Use:
      Dependencies.esi_service()

  ## Testing

  In tests, dependencies can be swapped by setting application environment variables:

      Application.put_env(:wanderer_notifier, :esi_service, MockESIService)
  """

  # Core Services
  @doc "Returns the ESI service module"
  def esi_service do
    Application.get_env(:wanderer_notifier, :esi_service, WandererNotifier.ESI.Service)
  end

  @doc "Returns the ESI client module"
  def esi_client do
    Application.get_env(:wanderer_notifier, :esi_client, WandererNotifier.ESI.Client)
  end

  @doc "Returns the HTTP client module"
  def http_client do
    Application.get_env(:wanderer_notifier, :http_client, WandererNotifier.Http)
  end

  # Configuration and Tracking Modules
  @doc "Returns the configuration module"
  def config_module do
    Application.get_env(:wanderer_notifier, :config_module, WandererNotifier.Config)
  end

  @doc "Returns the system tracking module"
  def system_module do
    config_module().system_track_module()
  end

  @doc "Returns the character tracking module"
  def character_module do
    config_module().character_track_module()
  end

  # Pipeline and Processing Modules
  @doc "Returns the killmail pipeline module"
  def killmail_pipeline do
    Application.get_env(
      :wanderer_notifier,
      :killmail_pipeline,
      WandererNotifier.Killmail.Pipeline
    )
  end

  @doc "Returns the deduplication module"
  def deduplication_module do
    config_module().deduplication_module()
  end

  # Notification Modules
  @doc "Returns the killmail notification module"
  def killmail_notification_module do
    Application.get_env(
      :wanderer_notifier,
      :killmail_notification_module,
      WandererNotifier.Killmail.KillmailNotification
    )
  end

  @doc "Returns the notification dispatcher module"
  def dispatcher_module do
    Application.get_env(
      :wanderer_notifier,
      :dispatcher_module,
      WandererNotifier.Notifications.Factory
    )
  end

  @doc "Returns the logger module"
  def logger_module do
    Application.get_env(:wanderer_notifier, :logger_module, WandererNotifier.Logger.Logger)
  end

  # Cache
  @doc "Returns the cache name"
  def cache_name do
    Application.get_env(:wanderer_notifier, :cache_name, :wanderer_cache)
  end
end
