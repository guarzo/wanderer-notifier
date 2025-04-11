defmodule WandererNotifier.Resources.KillmailPersistence do
  @moduledoc """
  Handles persistence of killmails to database for historical analysis and reporting.

  ## DEPRECATION NOTICE

  This module is deprecated and will be removed in a future release.
  Please use WandererNotifier.Processing.Killmail.Persistence instead.

  The new module provides:
  - Cleaner persistence logic with direct field access
  - Better transaction handling
  - Improved error reporting
  - Better separation of concerns
  """

  @behaviour WandererNotifier.Resources.KillmailPersistenceBehaviour

  require Ash.Query
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Core.Stats
  alias WandererNotifier.Data.Cache.Helpers, as: CacheHelpers
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Data.Repo
  alias WandererNotifier.KillmailProcessing.Transformer
  alias WandererNotifier.KillmailProcessing.Validator
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Resources.Api
  alias WandererNotifier.Resources.Killmail
  alias WandererNotifier.Resources.KillmailCharacterInvolvement
  alias WandererNotifier.Utils.ListUtils
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.KillmailProcessing.DataAccess
  alias WandererNotifier.Processing.Killmail.Persistence, as: NewPersistence
  import Ecto.Query, only: [from: 2]

  # Cache TTL for processed kill IDs - 24 hours
  @processed_kills_ttl_seconds 86_400
  # TTL for zkillboard data - 1 hour
  @zkillboard_cache_ttl_seconds 3600

  @doc """
  Persists a killmail to the database.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead.
  """
  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead"
  @impl true
  def persist_killmail(%KillmailData{} = killmail_data) do
    AppLogger.persistence_info(
      "Using deprecated KillmailPersistence module. Please migrate to Processing.Killmail.Persistence"
    )

    # Delegate to the new persistence module
    case NewPersistence.persist_killmail(killmail_data, nil) do
      {:ok, _, true} -> :ok
      {:ok, _, false} -> :already_exists
      {:error, _} -> :error
    end
  end

  @doc """
  Persists a killmail with character ID to the database.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead.
  """
  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead"
  @impl true
  def persist_killmail(killmail, character_id)
      when is_map(killmail) and not is_struct(killmail, KillmailData) do
    # Convert to KillmailData for consistent processing
    killmail_data = Transformer.to_killmail_data(killmail)
    persist_killmail(killmail_data, character_id)
  end

  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead"
  @impl true
  def persist_killmail(%KillmailData{} = killmail_data, character_id)
      when not is_nil(character_id) do
    AppLogger.persistence_info(
      "Using deprecated KillmailPersistence module. Please migrate to Processing.Killmail.Persistence"
    )

    # Delegate to the new persistence module
    case NewPersistence.persist_killmail(killmail_data, character_id) do
      {:ok, _, true} -> :ok
      {:ok, _, false} -> :already_exists
      {:error, _} -> :ignored
    end
  end

  @doc """
  Tries to persist a killmail if it doesn't already exist.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead.
  """
  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead"
  @impl true
  def maybe_persist_killmail(killmail, character_id \\ nil)

  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence.persist_killmail/2 instead"
  @impl true
  def maybe_persist_killmail(killmail, character_id) do
    AppLogger.persistence_info(
      "Using deprecated KillmailPersistence.maybe_persist_killmail. Please migrate to Processing.Killmail.Persistence"
    )

    # Convert to KillmailData if needed
    killmail_data =
      case killmail do
        %KillmailData{} -> killmail
        _ -> Transformer.to_killmail_data(killmail)
      end

    # Delegate to the new persistence module
    case NewPersistence.persist_killmail(killmail_data, character_id) do
      {:ok, persisted_killmail, _} -> {:ok, persisted_killmail}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets statistics about tracked characters and their killmails.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Processing.Killmail.Persistence stats functions instead.
  """
  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence stats functions instead"
  def get_tracked_kills_stats do
    # Keep original implementation for backward compatibility
    # This is usually a read-only operation so less critical to migrate
    tracked_characters = get_tracked_characters()
    character_count = length(tracked_characters)
    total_kills = count_total_killmails()

    %{
      tracked_characters: character_count,
      total_kills: total_kills
    }
  rescue
    e ->
      AppLogger.persistence_error("Error getting stats", error: Exception.message(e))
      %{tracked_characters: 0, total_kills: 0}
  end

  @doc """
  Counts total killmails in the database.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Processing.Killmail.Persistence counting functions instead.
  """
  @deprecated "Use WandererNotifier.Processing.Killmail.Persistence counting functions instead"
  def count_total_killmails do
    # Keep original implementation for backward compatibility
    case Killmail
         |> Ash.Query.new()
         |> Ash.Query.aggregate(:count, :id, :total)
         |> Api.read() do
      {:ok, [%{total: count}]} -> count
      _ -> 0
    end
  end

  @doc """
  Checks if kill charts feature is enabled.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Config.Features directly instead.
  """
  @deprecated "Use WandererNotifier.Config.Features directly instead"
  def kill_charts_enabled? do
    enabled = Features.kill_charts_enabled?()

    # Only log feature status if we haven't logged it before
    if !Process.get(:kill_charts_status_logged) do
      status_text = if enabled, do: "enabled", else: "disabled"

      AppLogger.persistence_info("Kill charts feature status: #{status_text}", %{enabled: enabled})

      Process.put(:kill_charts_status_logged, true)
    end

    enabled
  end

  @doc """
  Explicitly logs the current kill charts feature status.

  ## DEPRECATION NOTICE

  This function is deprecated. Use WandererNotifier.Config.Features directly instead.
  """
  @deprecated "Use WandererNotifier.Config.Features directly instead"
  def log_kill_charts_status do
    enabled = Features.kill_charts_enabled?()
    status_text = if enabled, do: "enabled", else: "disabled"
    AppLogger.persistence_info("Kill charts feature status: #{status_text}", %{enabled: enabled})
    enabled
  end

  # Helper function to get tracked characters from cache
  defp get_tracked_characters do
    CacheRepo.get(CacheKeys.character_list()) || []
  end
end
