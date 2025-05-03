defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic system updates from the map.
  """
  @behaviour WandererNotifier.Schedulers.Scheduler

  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__,
    initialize_error_handling: true

  # Interval is now configured via the Timings module

  alias WandererNotifier.Map.Clients.SystemsClient
  alias WandererNotifier.Config
  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo

  @impl true
  def execute(state) do
    # Only update systems if system tracking feature is enabled
    if Config.should_load_tracking_data?() do
      primed? = CacheRepo.get(:map_systems_primed) == {:ok, true}

      task =
        Task.async(fn ->
          try do
            SystemsClient.update_systems(nil, suppress_notifications: !primed?)
          rescue
            e ->
              AppLogger.api_error("⚠️ System update failed", error: Exception.message(e))
              {:error, :exception}
          end
        end)

      case Task.yield(task, 30_000) do
        {:ok, {:ok, _new_systems, all_systems}} ->
          AppLogger.api_info("🌍 Systems updated: #{length(all_systems)} systems synchronized",
            category: :api
          )

          if primed? do
            {:ok, all_systems, Map.put(state, :systems_count, length(all_systems))}
          else
            # First run: just cache, do not notify
            CacheRepo.put(:map_systems_primed, true)
            # Optionally log that this was the initial sync
            {:ok, all_systems, Map.put(state, :systems_count, length(all_systems))}
          end

        {:ok, {:error, reason}} ->
          AppLogger.api_error("⚠️ System update failed", error: inspect(reason))
          {:error, reason, state}

        nil ->
          Task.shutdown(task, :brutal_kill)
          AppLogger.api_error("⚠️ System update timed out after 30 seconds")
          {:error, :timeout, state}

        {:exit, reason} ->
          AppLogger.api_error("⚠️ System update crashed", error: inspect(reason))
          {:error, reason, state}
      end
    else
      {:ok, :disabled, state}
    end
  end

  @impl true
  def enabled? do
    Config.should_load_tracking_data?()
  end

  @impl true
  def get_config do
    %{
      interval_ms: Config.system_update_scheduler_interval(),
      enabled: enabled?(),
      feature_flags: %{
        system_notifications: Config.tracked_systems_notifications_enabled?(),
        should_load_tracking: Config.should_load_tracking_data?()
      }
    }
  end
end
