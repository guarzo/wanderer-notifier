defmodule WandererNotifier.Services.Maintenance.Scheduler do
  @moduledoc """
  Schedules and executes maintenance tasks.
  Handles periodic updates for systems and characters.
  """
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.Api.Map.SystemsClient
  alias WandererNotifier.Config
  alias WandererNotifier.Config.Application
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.DeduplicationHelper
  alias WandererNotifier.Logger, as: AppLogger

  @doc """
  Performs periodic maintenance tasks.
  - Updates tracked systems
  - Updates tracked characters
  - Performs health checks
  """
  def tick(state) do
    now = :os.system_time(:second)
    AppLogger.maintenance_debug("Running maintenance tick", timestamp: DateTime.from_unix!(now))

    # Update systems if needed (every 5 minutes)
    new_state =
      if now - state.last_systems_update > 300 do
        update_systems(state, now)
      else
        state
      end

    # Update characters if needed (every 10 minutes)
    new_state =
      if now - new_state.last_characters_update > 600 do
        update_characters(new_state, now)
      else
        new_state
      end

    # Log status every 24 hours (86400 seconds)
    if now - state.last_status_time > 86_400 do
      log_service_status(now - state.service_start_time)
      %{new_state | last_status_time: now}
    else
      new_state
    end
  end

  @doc """
  Performs initial checks when the service starts.
  Forces a full update of all systems and characters.
  """
  def do_initial_checks(state) do
    # Perform full update of all systems and characters
    now = :os.system_time(:second)

    # Log all feature flag configs related to character tracking
    _features_config = Application.get_env(:wanderer_notifier, :features, %{})

    # Check character tracking specifically
    _character_tracking = Features.character_tracking_enabled?()
    _characters_notifications = Features.tracked_characters_notifications_enabled?()
    _kill_notifications = Features.should_load_tracking_data?()

    state = update_characters(state, now, true)
    state = update_systems(state, now, true)

    state
  end

  # Update systems from the map
  defp update_systems(state, now, _force \\ false) do
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
          %{state | last_systems_update: now, systems_count: length(systems)}

        {:ok, {:error, reason}} ->
          AppLogger.api_error("Failed to update systems", error: inspect(reason))
          # Return original state with updated timestamp to prevent rapid retries
          %{state | last_systems_update: now}

        nil ->
          # Task took too long, kill it and return
          Task.shutdown(task, :brutal_kill)
          AppLogger.api_error("Systems update timed out after 30 seconds")
          %{state | last_systems_update: now}

        {:exit, reason} ->
          AppLogger.api_error("Systems update crashed: #{inspect(reason)}")
          %{state | last_systems_update: now}
      end
    else
      AppLogger.api_info("System tracking is disabled, skipping update")
      %{state | last_systems_update: now}
    end
  end

  # Update characters from the map
  defp update_characters(state, now, force \\ false) do
    # Check if character tracking is enabled or tracking data is needed for kill notifications
    AppLogger.maintenance_info("Checking if character tracking is enabled")

    # First check if character tracking is enabled directly
    character_tracking = Features.character_tracking_enabled?()
    characters_notifications = Features.tracked_characters_notifications_enabled?()
    kill_notifications = Features.should_load_tracking_data?()

    AppLogger.maintenance_info("Character tracking status check",
      character_tracking: character_tracking,
      characters_notifications: characters_notifications,
      kill_notifications: kill_notifications
    )

    if character_tracking || characters_notifications || kill_notifications do
      AppLogger.maintenance_info("Updating characters", force: force)
      update_tracked_characters(state, now, force)
    else
      AppLogger.maintenance_debug("Character tracking is disabled, skipping update")
      return_state_with_updated_timestamp(state, now)
    end
  end

  # Process tracked characters update
  defp update_tracked_characters(state, now, force) do
    AppLogger.maintenance_info("Starting character tracking update", force: force)

    # Get cached characters and ensure they're in the right format
    cached_characters = if force, do: nil, else: CacheRepo.get("map:characters")
    cached_characters_safe = normalize_cached_characters(cached_characters)

    AppLogger.maintenance_debug("Retrieved cached characters before update",
      count: length(cached_characters_safe)
    )

    # Use Task with timeout to prevent hanging
    task =
      Task.async(fn ->
        try do
          # Update characters through the MapClient with exception handling
          MapClient.update_tracked_characters(cached_characters_safe)
        rescue
          e ->
            AppLogger.maintenance_error("Exception in character update task",
              error: Exception.message(e),
              stacktrace: inspect(Process.info(self(), :current_stacktrace))
            )

            {:error, :exception}
        end
      end)

    # Wait for the task with a timeout (10 seconds should be plenty)
    case Task.yield(task, 10_000) do
      {:ok, {:ok, characters}} ->
        AppLogger.maintenance_info("Character update successful",
          count: length(ensure_list(characters))
        )

        handle_successful_character_update(state, now, characters)

      {:ok, {:error, :feature_disabled}} ->
        # Handle feature_disabled case differently - log as info instead of error
        AppLogger.maintenance_info("Character tracking feature is disabled, skipping update")
        return_state_with_updated_timestamp(state, now)

      {:ok, {:error, reason}} ->
        AppLogger.maintenance_error("Failed to update characters",
          error: inspect(reason)
        )

        return_state_with_updated_timestamp(state, now)

      nil ->
        # Task took too long, kill it
        Task.shutdown(task, :brutal_kill)
        AppLogger.maintenance_error("Character update timed out after 10 seconds")
        return_state_with_updated_timestamp(state, now)

      {:exit, reason} ->
        AppLogger.maintenance_error("Character update task crashed",
          reason: inspect(reason)
        )

        return_state_with_updated_timestamp(state, now)
    end
  rescue
    e ->
      # Catch any exception outside the task, log it, and return the state with updated timestamp
      AppLogger.maintenance_error("Exception while setting up character update",
        error: Exception.message(e),
        stacktrace: inspect(Process.info(self(), :current_stacktrace))
      )

      # Return original state with updated timestamp to prevent rapid retries
      return_state_with_updated_timestamp(state, now)
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
  defp handle_successful_character_update(state, now, characters) do
    # Ensure characters is a list
    characters_list = ensure_list(characters)

    AppLogger.maintenance_info("Characters updated", count: length(characters_list))

    # Verify the characters were actually stored in cache
    verify_and_update_characters_cache(characters_list)

    # Return updated state
    %{state | last_characters_update: now, characters_count: length(characters_list)}
  end

  # Helper to return state with updated timestamp
  defp return_state_with_updated_timestamp(state, now) do
    %{state | last_characters_update: now}
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
            AppLogger.maintenance_error("Exception in character cache verification",
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
        AppLogger.maintenance_error("Character cache verification TIMED OUT after 5 seconds")
    end
  end

  # Internal function to perform the actual verification
  defp _perform_character_cache_verification(characters) do
    # Ensure we're working with a list
    characters_list = ensure_list(characters)

    updated_cache = CacheRepo.get("map:characters")
    # Ensure the cache result is a list
    cache_list = ensure_list(updated_cache)

    AppLogger.maintenance_debug(
      "Post-update cache verification",
      cache_key: "map:characters",
      character_count: length(cache_list)
    )

    if cache_list == [] do
      AppLogger.maintenance_warn(
        "Characters were updated but cache appears empty",
        action: "forcing_manual_cache_update"
      )

      CacheRepo.set(
        "map:characters",
        characters_list,
        Config.Timings.characters_cache_ttl()
      )

      # Double-check the cache again
      final_cache = CacheRepo.get("map:characters")
      final_cache_list = ensure_list(final_cache)

      AppLogger.maintenance_debug(
        "After manual cache update",
        cache_key: "map:characters",
        character_count: length(final_cache_list)
      )
    end
  end

  # Log service status
  defp log_service_status(uptime_seconds) do
    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    # Create a deduplication key based on a time window (e.g., hourly)
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86_400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :new} ->
        AppLogger.maintenance_info("Service status notification allowed",
          action: "skipping_duplicate",
          uptime: "#{days}d #{hours}h #{minutes}m #{seconds}s"
        )

        {:ok, :new}

      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Service status notification skipped (duplicate)",
          action: "skipping_duplicate"
        )

        {:ok, :duplicate}
    end
  end

  def send_status_report do
    dedup_key = "service_status:report"

    case DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :new} ->
        AppLogger.maintenance_info("Service status report notification allowed")
        {:ok, :new}

      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Service status report notification skipped (duplicate)")
        {:ok, :duplicate}
    end
  end
end
