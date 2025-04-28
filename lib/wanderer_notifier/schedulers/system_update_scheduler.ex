defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic system updates from the map.
  """
  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  # Interval is now configured via the Timings module

  alias WandererNotifier.Map.SystemsClient
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def execute(state) do
    # Only update systems if system tracking feature is enabled
    if Features.should_load_tracking_data?() do
      # Use Task with timeout to prevent hanging
      task =
        Task.async(fn ->
          try do
            # Simply call SystemsClient.update_systems which handles caching
            SystemsClient.update_systems()
          rescue
            e ->
              AppLogger.api_error("⚠️ System update failed", error: Exception.message(e))
              {:error, :exception}
          end
        end)

      # Wait for the task with a timeout (30 seconds)
      case Task.yield(task, 30_000) do
        {:ok, {:ok, systems}} ->
          AppLogger.api_info("🌍 Systems updated: #{length(systems)} systems synchronized")
          {:ok, systems, Map.put(state, :systems_count, length(systems))}

        {:ok, {:error, reason}} ->
          AppLogger.api_error("⚠️ System update failed", error: inspect(reason))
          {:error, reason, state}

        nil ->
          # Task took too long, kill it and return
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
    Features.should_load_tracking_data?()
  end

  @impl true
  def get_config do
    %{
      interval_ms: Timings.system_update_scheduler_interval(),
      enabled: enabled?(),
      feature_flags: %{
        system_notifications: Features.tracked_systems_notifications_enabled?(),
        should_load_tracking: Features.should_load_tracking_data?(),
        map_charts: Features.map_charts_enabled?()
      }
    }
  end
end
