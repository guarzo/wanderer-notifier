defmodule WandererNotifier.Application.Services.Dependencies do
  @moduledoc """
  Backward compatibility adapter for the Dependencies service.
  
  This module maintains the existing Dependencies API while delegating
  to the new ApplicationService's DependencyManager for actual functionality.
  """
  
  alias WandererNotifier.Application.Services.ApplicationService
  
  # ──────────────────────────────────────────────────────────────────────────────
  # Original Dependencies API - delegated to ApplicationService
  # ──────────────────────────────────────────────────────────────────────────────
  
  @doc "Returns the ESI service module"
  def esi_service do
    ApplicationService.get_dependency(:esi_service, WandererNotifier.Infrastructure.Adapters.ESI.Service)
  end
  
  @doc "Returns the ESI client module"
  def esi_client do
    ApplicationService.get_dependency(:esi_client, WandererNotifier.Infrastructure.Adapters.ESI.Client)
  end
  
  @doc "Returns the HTTP client module"
  def http_client do
    ApplicationService.get_dependency(:http_client, WandererNotifier.Infrastructure.Http)
  end
  
  @doc "Returns the system tracking module"
  def system_module do
    WandererNotifier.Shared.Config.system_track_module()
  end
  
  @doc "Returns the character tracking module"
  def character_module do
    WandererNotifier.Shared.Config.character_track_module()
  end
  
  @doc "Returns the killmail pipeline module"
  def killmail_pipeline do
    ApplicationService.get_dependency(:killmail_pipeline, WandererNotifier.Domains.Killmail.Pipeline)
  end
  
  @doc "Returns the deduplication module"
  def deduplication_module do
    WandererNotifier.Shared.Config.deduplication_module()
  end
  
  @doc "Returns the killmail cache module"
  def killmail_cache_module do
    ApplicationService.get_dependency(:killmail_cache, WandererNotifier.Domains.Killmail.Cache)
  end
  
  @doc "Returns the killmail notification module"
  def killmail_notification_module do
    ApplicationService.get_dependency(:killmail_notification_module, WandererNotifier.Domains.Killmail.KillmailNotification)
  end
  
  @doc "Returns the logger module"
  def logger_module do
    ApplicationService.get_dependency(:logger_module, WandererNotifier.Shared.Logger.Logger)
  end
  
  @doc "Returns the cache name"
  def cache_name do
    ApplicationService.get_dependency(:cache_name, :wanderer_cache)
  end
end