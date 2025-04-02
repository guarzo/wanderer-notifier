defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic character updates from the map.
  """
  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  # Interval is now configured via the Timings module

  alias WandererNotifier.Api.Map.Client
  alias WandererNotifier.Config.Cache, as: CacheConfig
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Data.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def execute(state) do
    # Check if character tracking is enabled or tracking data is needed for kill notifications
    if Features.character_tracking_enabled?() ||
         Features.tracked_characters_notifications_enabled?() ||
         Features.should_load_tracking_data?() do
      update_tracked_characters(state)
    else
      {:ok, :disabled, state}
    end
  end

  @impl true
  def enabled? do
    Features.character_tracking_enabled?() ||
      Features.tracked_characters_notifications_enabled?() ||
      Features.should_load_tracking_data?()
  end

  @impl true
  def get_config do
    %{
      interval_ms: Timings.character_update_scheduler_interval(),
      enabled: enabled?(),
      feature_flags: %{
        character_tracking: Features.character_tracking_enabled?(),
        characters_notifications: Features.tracked_characters_notifications_enabled?(),
        kill_notifications: Features.should_load_tracking_data?()
      }
    }
  end

  # Process tracked characters update
  defp update_tracked_characters(state) do
    # Get cached characters and ensure they're in the right format
    cached_characters = CacheRepo.get(CacheKeys.character_list())
    cached_characters_safe = normalize_cached_characters(cached_characters)

    # Use Task with timeout to prevent hanging
    task =
      Task.async(fn ->
        try do
          # Update characters through the MapClient with exception handling
          Client.update_tracked_characters(cached_characters_safe)
        rescue
          e ->
            AppLogger.maintenance_error("⚠️ Exception in character update task",
              error: Exception.message(e),
              stacktrace: inspect(Process.info(self(), :current_stacktrace))
            )

            {:error, :exception}
        end
      end)

    # Wait for the task with a timeout (10 seconds should be plenty)
    case Task.yield(task, 10_000) do
      {:ok, {:ok, characters}} ->
        AppLogger.maintenance_info(
          "👥 Characters updated: #{length(ensure_list(characters))} characters synchronized"
        )

        handle_successful_character_update(state, characters)

      {:ok, {:error, :feature_disabled}} ->
        {:ok, :disabled, state}

      {:ok, {:error, reason}} ->
        AppLogger.maintenance_error("⚠️ Character update failed",
          error: inspect(reason)
        )

        {:error, reason, state}

      nil ->
        # Task took too long, kill it
        Task.shutdown(task, :brutal_kill)
        AppLogger.maintenance_error("⚠️ Character update timed out after 10 seconds")
        {:error, :timeout, state}

      {:exit, reason} ->
        AppLogger.maintenance_error("⚠️ Character update crashed",
          reason: inspect(reason)
        )

        {:error, reason, state}
    end
  rescue
    e ->
      # Catch any exception outside the task, log it, and return the state with updated timestamp
      AppLogger.maintenance_error("⚠️ Exception in character update",
        error: Exception.message(e),
        stacktrace: inspect(Process.info(self(), :current_stacktrace))
      )

      # Return original state with error
      {:error, e, state}
  end

  # Normalize cached characters to ensure it's a list or nil
  defp normalize_cached_characters(cached_characters) do
    ensure_list(cached_characters)
  end

  # Helper function to ensure we're working with a list
  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list({:error, _}), do: []
  defp ensure_list(_), do: []

  # Handle successful character update
  defp handle_successful_character_update(state, characters) do
    # Ensure characters is a list
    characters_list = ensure_list(characters)

    # Verify the characters were actually stored in cache
    verify_and_update_characters_cache(characters_list)

    # Return updated state
    {:ok, characters_list, Map.put(state, :characters_count, length(characters_list))}
  end

  # Verify characters are stored in cache and force update if needed
  defp verify_and_update_characters_cache(characters) do
    # Use a task with timeout to prevent hanging
    task =
      Task.async(fn ->
        try do
          _perform_character_cache_verification(characters)
        rescue
          e ->
            AppLogger.maintenance_error("⚠️ Character cache verification failed",
              error: Exception.message(e)
            )
        end
      end)

    # Wait max 5 seconds for verification
    case Task.yield(task, 5_000) do
      {:ok, _} ->
        :ok

      nil ->
        # Verification took too long, kill it
        Task.shutdown(task, :brutal_kill)
        AppLogger.maintenance_error("⚠️ Character cache verification timed out after 5 seconds")
    end
  end

  # Internal function to perform the actual verification
  defp _perform_character_cache_verification(characters) do
    # Ensure we're working with a list
    characters_list = ensure_list(characters)
    updated_cache = CacheRepo.get(CacheKeys.character_list())
    cache_list = ensure_list(updated_cache)

    if cache_list == [] do
      # Get cache TTL from the proper module
      cache_ttl = CacheConfig.characters_cache_ttl()

      CacheRepo.set(
        CacheKeys.character_list(),
        characters_list,
        cache_ttl
      )
    end
  end
end
