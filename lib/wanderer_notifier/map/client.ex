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
  def update_systems do
    if Features.enabled?(:tracked_systems_notifications) do
      # Check if we've reached the system tracking limit
      current_systems = CacheRepo.get("map:systems") || []
      
      if Features.limit_reached?(:tracked_systems, length(current_systems)) do
        Logger.warning("System tracking limit reached (#{length(current_systems)}). Upgrade license for more.")
        {:error, :limit_reached}
      else
        Systems.update_systems()
      end
    else
      Logger.info("System tracking disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  end

  def check_backup_kills do
    if Features.enabled?(:backup_kills_processing) do
      BackupKills.check_backup_kills()
    else
      Logger.info("Backup kills processing disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  end

  def update_tracked_characters do
    if Features.enabled?(:tracked_characters_notifications) do
      # Check if we've reached the character tracking limit
      current_characters = CacheRepo.get("map:characters") || []
      
      if Features.limit_reached?(:tracked_characters, length(current_characters)) do
        Logger.warning("Character tracking limit reached (#{length(current_characters)}). Upgrade license for more.")
        {:error, :limit_reached}
      else
        Characters.update_tracked_characters()
      end
    else
      Logger.info("Character tracking disabled due to license restrictions")
      {:error, :feature_disabled}
    end
  end
end
