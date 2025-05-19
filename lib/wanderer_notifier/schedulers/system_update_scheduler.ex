defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic system updates from the map.
  """
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Map.Clients.SystemsClient
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Cache.Keys

  @behaviour WandererNotifier.Schedulers.Scheduler

  @impl true
  def config do
    interval = WandererNotifier.Config.system_update_scheduler_interval()
    %{type: :interval, spec: interval}
  end

  @impl true
  def run do
    update_tracked_systems()
    :ok
  end

  defp update_tracked_systems do
    primed? = CacheRepo.get(:map_systems_primed) == {:ok, true}
    task = create_update_task(primed?)
    handle_task_result(task, primed?)
  end

  defp create_update_task(primed?) do
    Task.async(fn ->
      try do
        SystemsClient.update_systems(suppress_notifications: !primed?)
      rescue
        e ->
          AppLogger.api_error("⚠️ Exception in system update task",
            error: Exception.message(e),
            stacktrace: inspect(Process.info(self(), :current_stacktrace))
          )

          {:error, :exception}
      end
    end)
  end

  defp handle_task_result(task, primed?) do
    case Task.yield(task, 50_000) do
      {:ok, {:ok, _new_systems, all_systems}} ->
        handle_successful_update(all_systems, primed?)

      {:ok, {:error, reason}} ->
        AppLogger.api_error("⚠️ System update failed", error: inspect(reason))

      nil ->
        Task.shutdown(task, :brutal_kill)
        AppLogger.api_error("⚠️ System update timed out after 10 seconds")

      {:exit, reason} ->
        AppLogger.api_error("⚠️ System update crashed", reason: inspect(reason))
    end
  end

  defp handle_successful_update(all_systems, primed?) do
    systems_count = length(ensure_list(all_systems))
    AppLogger.api_info("🌍 Systems updated: #{systems_count} systems synchronized")

    # Log a summary of the systems cache
    log_system_cache_summary(all_systems)

    if primed? do
      handle_successful_system_update(all_systems)
    else
      CacheRepo.put(:map_systems_primed, true)
    end
  end

  # Log a summary of systems in the cache
  defp log_system_cache_summary(systems) do
    systems_list = ensure_list(systems)
    system_count = length(systems_list)

    if system_count > 0 do
      # Just log the count, not all system IDs
      AppLogger.api_info("📊 Tracked systems cache updated",
        count: system_count
      )
    else
      AppLogger.api_warn("📊 No tracked systems found in cache update")
    end
  end

  defp ensure_list(nil), do: []
  defp ensure_list(list) when is_list(list), do: list
  defp ensure_list({:ok, list}) when is_list(list), do: list
  defp ensure_list({:error, _}), do: []
  defp ensure_list(_), do: []

  defp handle_successful_system_update(systems) do
    systems_list = ensure_list(systems)
    verify_and_update_systems_cache(systems_list)
    WandererNotifier.Core.Stats.set_tracked_count(:systems, length(systems_list))
    :ok
  end

  defp verify_and_update_systems_cache(systems) do
    task =
      Task.async(fn ->
        try do
          _perform_system_cache_verification(systems)
        rescue
          e ->
            AppLogger.api_error("⚠️ System cache verification failed", error: Exception.message(e))
        end
      end)

    case Task.yield(task, 5_000) do
      {:ok, _} ->
        :ok

      nil ->
        Task.shutdown(task, :brutal_kill)
        AppLogger.api_error("⚠️ System cache verification timed out after 5 seconds")
    end
  end

  defp _perform_system_cache_verification(systems) do
    alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
    systems_list = ensure_list(systems)
    updated_cache = CacheRepo.get(Keys.system_list())
    cache_list = ensure_list(updated_cache)

    if cache_list == [] do
      cache_ttl = WandererNotifier.Config.static_info_ttl()
      CacheRepo.set(Keys.system_list(), systems_list, cache_ttl)
    end
  end
end
