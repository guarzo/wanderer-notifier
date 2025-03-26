defmodule WandererNotifier.Services.Maintenance.Scheduler do
  @moduledoc """
  Schedules and executes maintenance tasks.
  Handles periodic updates for systems and characters.
  """
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Helpers.CacheHelpers
  alias WandererNotifier.Core.Features
  alias WandererNotifier.Notifiers.Factory, as: NotifierFactory

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
    state = update_systems(state, now, true)
    state = update_characters(state, now, true)
    state
  end

  # Update systems from the map
  defp update_systems(state, now, force \\ false) do
    if Features.tracked_systems_notifications_enabled?() || Features.should_load_tracking_data?() do
      AppLogger.maintenance_info("Updating systems", force: force)

      cached_systems = if force, do: nil, else: CacheHelpers.get_tracked_systems()

      case MapClient.update_systems_with_cache(cached_systems) do
        {:ok, systems} ->
          AppLogger.maintenance_info("Systems updated", count: length(systems))
          %{state | last_systems_update: now, systems_count: length(systems)}

        {:error, reason} ->
          AppLogger.maintenance_error("Failed to update systems", error: inspect(reason))
          # Return original state with updated timestamp to prevent rapid retries
          %{state | last_systems_update: now}
      end
    else
      AppLogger.maintenance_debug("System tracking is disabled, skipping update")
      %{state | last_systems_update: now}
    end
  end

  # Update characters from the map
  defp update_characters(state, now, force \\ false) do
    # Check if character tracking is enabled or tracking data is needed for kill notifications
    if Features.tracked_characters_notifications_enabled?() ||
         Features.should_load_tracking_data?() do
      update_tracked_characters(state, now, force)
    else
      AppLogger.maintenance_debug("Character tracking is disabled, skipping update")
      return_state_with_updated_timestamp(state, now)
    end
  end

  # Process tracked characters update
  defp update_tracked_characters(state, now, force) do
    AppLogger.maintenance_info("Updating characters", force: force)

    # Get cached characters and ensure they're in the right format
    cached_characters = if force, do: nil, else: CacheRepo.get("map:characters")
    cached_characters_safe = normalize_cached_characters(cached_characters)

    AppLogger.maintenance_debug("Retrieved cached characters before update",
      characters: inspect(cached_characters_safe)
    )

    # Update characters through the MapClient with exception handling
    try do
      case MapClient.update_tracked_characters(cached_characters_safe) do
        {:ok, characters} ->
          handle_successful_character_update(state, now, characters)

        {:error, reason} ->
          AppLogger.maintenance_error("Failed to update characters", error: inspect(reason))
          return_state_with_updated_timestamp(state, now)
      end
    rescue
      e ->
        # Catch any exception, log it, and return the state with updated timestamp
        AppLogger.maintenance_error("Exception while updating characters",
          error: Exception.message(e),
          stacktrace: inspect(Process.info(self(), :current_stacktrace))
        )

        # Return original state with updated timestamp to prevent rapid retries
        return_state_with_updated_timestamp(state, now)
    end
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
        WandererNotifier.Core.Config.Timings.characters_cache_ttl()
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

    uptime_str = "#{days}d #{hours}h #{minutes}m #{seconds}s"

    # Create a deduplication key based on a time window (e.g., hourly)
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86_400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case WandererNotifier.Helpers.DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Status report for current day already sent",
          action: "skipping_duplicate"
        )

        :ok

      {:ok, :new} ->
        # Get current stats
        stats = WandererNotifier.Core.Stats.get_stats()

        # Get license information safely
        license_status =
          try do
            WandererNotifier.Core.License.status()
          rescue
            e ->
              AppLogger.maintenance_error("Error getting license status", error: inspect(e))
              %{valid: false, error_message: "Error retrieving license status"}
          catch
            type, error ->
              AppLogger.maintenance_error("Error getting license status",
                error_type: inspect(type),
                error: inspect(error)
              )

              %{valid: false, error_message: "Error retrieving license status"}
          end

        # Get feature information
        features_status = WandererNotifier.Core.Features.get_feature_status()

        # Get tracked systems and characters counts
        systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
        characters = CacheRepo.get("map:characters") || []

        # Create a structured notification for the status message
        title = "Service Status Report"
        description = "Periodic status update for the notification service."

        # Create a structured notification using our formatter
        generic_notification =
          WandererNotifier.Notifiers.StructuredFormatter.format_system_status_message(
            title,
            description,
            stats,
            uptime_seconds,
            features_status,
            license_status,
            length(systems),
            length(characters)
          )

        # Convert to Discord format
        discord_embed =
          WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

        # Log simple status message
        AppLogger.maintenance_info("Service status report", uptime: uptime_str)

        # Send the rich notification
        NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
    end
  end

  def send_status_report do
    # Calculate uptime
    uptime_seconds = :os.system_time(:second) - Process.get(:service_start_time, 0)

    days = div(uptime_seconds, 86_400)
    hours = div(rem(uptime_seconds, 86_400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    uptime_str = "#{days}d #{hours}h #{minutes}m #{seconds}s"

    # Create a deduplication key based on a time window
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86_400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case WandererNotifier.Helpers.DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :duplicate} ->
        AppLogger.maintenance_info("Status report for current day already sent",
          action: "skipping_duplicate"
        )

        :ok

      {:ok, :new} ->
        # Get current stats
        stats = WandererNotifier.Core.Stats.get_stats()

        # Get license information safely
        license_status =
          try do
            WandererNotifier.Core.License.status()
          rescue
            e ->
              AppLogger.maintenance_error("Error getting license status", error: inspect(e))
              %{valid: false, error_message: "Error retrieving license status"}
          catch
            type, error ->
              AppLogger.maintenance_error("Error getting license status",
                error_type: inspect(type),
                error: inspect(error)
              )

              %{valid: false, error_message: "Error retrieving license status"}
          end

        # Get feature information
        features_status = WandererNotifier.Core.Features.get_feature_status()

        # Get tracked systems and characters counts
        systems = WandererNotifier.Helpers.CacheHelpers.get_tracked_systems()
        characters = CacheRepo.get("map:characters") || []

        # Create a structured notification for the status message
        title = "Service Status Report"
        description = "Periodic status update for the notification service."

        # Create a structured notification using our formatter
        generic_notification =
          WandererNotifier.Notifiers.StructuredFormatter.format_system_status_message(
            title,
            description,
            stats,
            uptime_seconds,
            features_status,
            license_status,
            length(systems),
            length(characters)
          )

        # Convert to Discord format
        discord_embed =
          WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(generic_notification)

        # Log simple status message
        AppLogger.maintenance_info("Service status report", uptime: uptime_str)

        # Send the rich notification
        NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
    end
  end
end
