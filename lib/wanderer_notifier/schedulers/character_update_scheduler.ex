defmodule WandererNotifier.Schedulers.CharacterUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic character updates from the map.
  """

  @behaviour WandererNotifier.Schedulers.Scheduler

  @impl true
  def config,
    do: %{type: :interval, spec: WandererNotifier.Config.character_update_scheduler_interval()}

  @impl true
  def run do
    # Core job logic from previous implementation
    if WandererNotifier.Config.character_notifications_enabled?() do
      update_tracked_characters()
      :ok
    else
      :ok
    end
  end

  defp update_tracked_characters do
    alias WandererNotifier.Map.Clients.Client
    alias WandererNotifier.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    alias WandererNotifier.Logger.Logger, as: AppLogger

    primed? = CacheRepo.get(:character_list_primed) == {:ok, true}
    cached_characters = CacheRepo.get(CacheKeys.character_list())
    cached_characters_safe = ensure_list(cached_characters)

    task = create_update_task(cached_characters_safe, primed?)
    handle_task_result(task, primed?, cached_characters_safe)
  end

  defp create_update_task(cached_characters_safe, primed?) do
    alias WandererNotifier.Map.Clients.Client
    alias WandererNotifier.Logger.Logger, as: AppLogger

    Task.async(fn ->
      try do
        AppLogger.maintenance_debug(
          "Calling update_tracked_characters with #{length(cached_characters_safe)} cached characters"
        )

        Client.update_tracked_characters(cached_characters_safe,
          suppress_notifications: !primed?
        )
      rescue
        e ->
          AppLogger.maintenance_error("⚠️ Exception in character update task",
            error: Exception.message(e),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          )

          {:error, :exception}
      end
    end)
  end

  defp handle_task_result(task, primed?, cached_characters_safe) do
    alias WandererNotifier.Logger.Logger, as: AppLogger

    case Task.yield(task, 10_000) do
      {:ok, {:ok, characters}} ->
        handle_successful_update(characters, primed?, cached_characters_safe)

      {:ok, {:error, :feature_disabled}} ->
        :ok

      {:ok, {:error, reason}} ->
        AppLogger.maintenance_error("⚠️ Character update failed", error: inspect(reason))

      nil ->
        Task.shutdown(task, :brutal_kill)
        AppLogger.maintenance_error("⚠️ Character update timed out after 10 seconds")

      {:exit, reason} ->
        AppLogger.maintenance_error("⚠️ Character update crashed", reason: inspect(reason))
    end
  end

  defp handle_successful_update(characters, primed?, cached_characters_safe) do
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    alias WandererNotifier.Logger.Logger, as: AppLogger

    characters_list = ensure_list(characters)

    AppLogger.maintenance_info(
      "👥 Characters updated: #{length(characters_list)} characters from API (cached before: #{length(cached_characters_safe)})"
    )

    if primed? do
      handle_successful_character_update(characters)
    else
      CacheRepo.put(:character_list_primed, true)
      AppLogger.maintenance_info("Character cache primed for first time")
    end
  end

  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list({:error, _}), do: []
  defp ensure_list(_), do: []

  defp handle_successful_character_update(characters) do
    alias WandererNotifier.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    alias WandererNotifier.Logger.Logger, as: AppLogger
    characters_list = ensure_list(characters)
    verify_and_update_characters_cache(characters_list)
    # Update Stats with new characters count
    WandererNotifier.Core.Stats.set_tracked_count(:characters, length(characters_list))
    :ok
  end

  defp verify_and_update_characters_cache(characters) do
    alias WandererNotifier.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    alias WandererNotifier.Logger.Logger, as: AppLogger

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

    case Task.yield(task, 5_000) do
      {:ok, _} ->
        :ok

      nil ->
        Task.shutdown(task, :brutal_kill)
        AppLogger.maintenance_error("⚠️ Character cache verification timed out after 5 seconds")
    end
  end

  defp _perform_character_cache_verification(characters) do
    alias WandererNotifier.Cache.Keys, as: CacheKeys
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    alias WandererNotifier.Logger.Logger, as: AppLogger

    characters_list = ensure_list(characters)

    # Always update the cache with the latest characters from the API
    # This ensures characters that are no longer present get removed
    cache_ttl = WandererNotifier.Config.static_info_ttl()
    CacheRepo.set(CacheKeys.character_list(), characters_list, cache_ttl)

    AppLogger.maintenance_debug(
      "Character cache updated with #{length(characters_list)} characters"
    )
  end
end
