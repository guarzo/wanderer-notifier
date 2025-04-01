defmodule WandererNotifier.Schedulers.SystemUpdateScheduler do
  @moduledoc """
  Scheduler responsible for periodic system updates from the map.
  """
  use WandererNotifier.Schedulers.IntervalScheduler,
    name: __MODULE__

  # Interval is now configured via the Timings module

  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Config.Timings
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @impl true
  def execute(state) do
    # Log all feature flags related to system updates
    system_notifications = Features.tracked_systems_notifications_enabled?()
    should_load_tracking = Features.should_load_tracking_data?()
    map_charts = Features.map_charts_enabled?()

    AppLogger.api_info(
      "Updating systems with feature flags: " <>
        "tracked_systems_notifications=#{system_notifications}, " <>
        "should_load_tracking=#{should_load_tracking}, " <>
        "map_charts=#{map_charts}"
    )

    # Only update systems if system tracking feature is enabled
    if should_load_tracking do
      AppLogger.api_info("System tracking is enabled, proceeding with update")

      # Use Task with timeout to prevent hanging
      task =
        Task.async(fn ->
          try do
            # Simply call SystemsClient.update_systems which handles caching
            SystemsClient.update_systems()
          rescue
            e ->
              AppLogger.api_error("Exception in systems update: #{Exception.message(e)}")
              {:error, :exception}
          end
        end)

      # Wait for the task with a timeout (30 seconds)
      case Task.yield(task, 30_000) do
        {:ok, {:ok, systems}} ->
          AppLogger.api_info("Systems updated successfully", count: length(systems))
          {:ok, systems, Map.put(state, :systems_count, length(systems))}

        {:ok, {:error, reason}} ->
          AppLogger.api_error("Failed to update systems", error: inspect(reason))
          # Return error with state unchanged
          {:error, reason, state}

        nil ->
          # Task took too long, kill it and return
          Task.shutdown(task, :brutal_kill)
          AppLogger.api_error("Systems update timed out after 30 seconds")
          {:error, :timeout, state}

        {:exit, reason} ->
          AppLogger.api_error("Systems update crashed: #{inspect(reason)}")
          {:error, reason, state}
      end
    else
      AppLogger.api_info("System tracking is disabled, skipping update")
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
