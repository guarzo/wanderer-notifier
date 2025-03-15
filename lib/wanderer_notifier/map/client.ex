defmodule WandererNotifier.Map.Client do
  @moduledoc """
  High-level map API client.
  """
  require Logger
  alias WandererNotifier.Map.Systems
  alias WandererNotifier.Map.Characters
  alias WandererNotifier.Map.BackupKills
  alias WandererNotifier.Features
  alias WandererNotifier.Cache.Repository, as: CacheRepo

  # A single function for each major operation:
  def update_systems(cached_systems \\ nil) do
    if Features.enabled?(:tracked_systems_notifications) do
      # Use provided cached_systems if available, otherwise get from cache
      current_systems = cached_systems || CacheRepo.get("map:systems") || []

      if Features.limit_reached?(:tracked_systems, length(current_systems)) do
        Logger.warning("System tracking limit reached (#{length(current_systems)}). Upgrade license for more.")
        {:error, :limit_reached}
      else
        Systems.update_systems(current_systems)
      end
    else
      Logger.debug("System tracking disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  end

  def check_backup_kills do
    if Features.enabled?(:backup_kills_processing) do
      BackupKills.check_backup_kills()
    else
      Logger.debug("Backup kills processing disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  end

  def update_tracked_characters(cached_characters \\ nil) do
    if Features.enabled?(:tracked_characters_notifications) do
      Logger.debug("[Map.Client] Character tracking is enabled, checking for tracked characters")

      # Use provided cached_characters if available, otherwise get from cache
      current_characters = cached_characters || CacheRepo.get("map:characters") || []

      if Features.limit_reached?(:tracked_characters, length(current_characters)) do
        Logger.warning("[Map.Client] Character tracking limit reached (#{length(current_characters)}). Upgrade license for more.")
        {:error, :limit_reached}
      else
        # First check if the characters endpoint is available
        case Characters.check_characters_endpoint_availability() do
          {:ok, _} ->
            # Endpoint is available, proceed with update
            Logger.debug("[Map.Client] Characters endpoint is available, proceeding with update")
            Characters.update_tracked_characters(current_characters)

          {:error, reason} ->
            # Endpoint is not available, log detailed error
            Logger.error("[Map.Client] Characters endpoint is not available: #{inspect(reason)}")
            Logger.error("[Map.Client] This map API may not support character tracking")
            Logger.error("[Map.Client] To disable character tracking, set ENABLE_CHARACTER_TRACKING=false")

            # Return a more descriptive error
            {:error, {:characters_endpoint_unavailable, reason}}
        end
      end
    else
      Logger.debug("[Map.Client] Character tracking disabled due to license restrictions or configuration")
      {:error, :feature_disabled}
    end
  end
end
