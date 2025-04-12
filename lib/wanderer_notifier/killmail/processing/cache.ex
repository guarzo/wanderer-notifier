defmodule WandererNotifier.Killmail.Processing.Cache do
  @moduledoc """
  Cache for killmail data.

  This module provides functions to cache killmail data in memory,
  making it quickly accessible for repeated access and to prevent
  duplicate processing.
  """

  alias WandererNotifier.Config.Features
  alias WandererNotifier.Killmail.Core.Data, as: KillmailData
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Integration with existing cache
  alias WandererNotifier.Cache.Killmail, as: KillmailCache

  @doc """
  Checks if a killmail is already in the cache.

  ## Parameters
    - killmail_id: The killmail ID to check

  ## Returns
    - true if the killmail is in the cache
    - false otherwise
  """
  @spec in_cache?(integer()) :: boolean()
  def in_cache?(killmail_id) when is_integer(killmail_id) do
    # Check if caching is enabled in the first place
    Features.cache_enabled?() && KillmailCache.exists?(killmail_id)
  end

  def in_cache?(killmail_id) when is_binary(killmail_id) do
    case Integer.parse(killmail_id) do
      {id, _} -> in_cache?(id)
      :error -> false
    end
  end

  def in_cache?(_), do: false

  @doc """
  Caches a killmail data struct.

  ## Parameters
    - killmail: The KillmailData struct to cache

  ## Returns
    - {:ok, cached_killmail} on success
    - {:error, reason} on failure
  """
  @spec cache(KillmailData.t()) :: {:ok, KillmailData.t()} | {:error, any()}
  def cache(%KillmailData{} = killmail) do
    if Features.cache_enabled?() do
      do_cache(killmail)
    else
      AppLogger.kill_debug(
        "Killmail caching disabled, skipping cache for ##{killmail.killmail_id}"
      )

      {:ok, killmail}
    end
  end

  # Actually cache the killmail - private implementation
  defp do_cache(killmail) do
    case KillmailCache.put(killmail) do
      {:ok, _} ->
        AppLogger.kill_debug("Cached killmail ##{killmail.killmail_id}")
        {:ok, killmail}

      error ->
        AppLogger.kill_error(
          "Failed to cache killmail ##{killmail.killmail_id}: #{inspect(error)}"
        )

        # Still return success but log the error
        # This allows processing to continue even if caching fails
        {:ok, killmail}
    end
  end
end
