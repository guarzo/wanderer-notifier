defmodule WandererNotifier.Services.Maintenance.Scheduler do
  @moduledoc """
  Schedules and executes maintenance tasks.
  Handles periodic updates for systems and characters.
  """
  require Logger
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
    Logger.debug("Running maintenance tick at #{DateTime.from_unix!(now)}")

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
    if now - state.last_status_time > 86400 do
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
    if Features.tracked_systems_notifications_enabled?() do
      Logger.info("Updating systems (force=#{force})...")

      cached_systems = if force, do: nil, else: CacheHelpers.get_tracked_systems()

      case MapClient.update_systems_with_cache(cached_systems) do
        {:ok, systems} ->
          Logger.info("Systems updated: #{length(systems)} systems found")
          %{state | last_systems_update: now, systems_count: length(systems)}

        {:error, reason} ->
          Logger.error("Failed to update systems: #{inspect(reason)}")
          # Return original state with updated timestamp to prevent rapid retries
          %{state | last_systems_update: now}
      end
    else
      Logger.debug("System tracking is disabled, skipping update")
      %{state | last_systems_update: now}
    end
  end

  # Update characters from the map
  defp update_characters(state, now, force \\ false) do
    if Features.tracked_characters_notifications_enabled?() do
      Logger.info("Updating characters (force=#{force})...")

      cached_characters = if force, do: nil, else: CacheRepo.get("map:characters")
      Logger.debug("Retrieved cached characters before update: #{inspect(cached_characters)}")

      case MapClient.update_tracked_characters(cached_characters) do
        {:ok, characters} ->
          Logger.info("Characters updated: #{length(characters)} characters found")
          # Verify the characters were actually stored in cache
          updated_cache = CacheRepo.get("map:characters")

          Logger.debug(
            "Post-update cache verification - map:characters contains: #{inspect(updated_cache)}"
          )

          if updated_cache == nil || updated_cache == [] do
            Logger.warning(
              "Characters were updated but cache appears empty. Forcing manual cache update."
            )

            CacheRepo.set(
              "map:characters",
              characters,
              WandererNotifier.Config.Timings.characters_cache_ttl()
            )

            # Double-check the cache again
            final_cache = CacheRepo.get("map:characters")

            Logger.debug(
              "After manual cache update - map:characters contains: #{inspect(final_cache)}"
            )
          end

          %{state | last_characters_update: now, characters_count: length(characters)}

        {:error, reason} ->
          Logger.error("Failed to update characters: #{inspect(reason)}")
          # Return original state with updated timestamp to prevent rapid retries
          %{state | last_characters_update: now}
      end
    else
      Logger.debug("Character tracking is disabled, skipping update")
      %{state | last_characters_update: now}
    end
  end

  # Log service status
  defp log_service_status(uptime_seconds) do
    days = div(uptime_seconds, 86400)
    hours = div(rem(uptime_seconds, 86400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    uptime_str = "#{days}d #{hours}h #{minutes}m #{seconds}s"

    # Create a deduplication key based on a time window (e.g., hourly)
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case WandererNotifier.Helpers.DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :duplicate} ->
        Logger.info("Status report for current day already sent, skipping duplicate")
        :ok

      {:ok, :new} ->
        # Get current stats
        stats = WandererNotifier.Core.Stats.get_stats()

        # Get license information
        license_status = WandererNotifier.Core.License.status()

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
        Logger.info("Service status report - Uptime: #{uptime_str}")

        # Send the rich notification
        NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
    end
  end

  def send_status_report do
    # Calculate uptime
    uptime_seconds = :os.system_time(:second) - Process.get(:service_start_time, 0)

    days = div(uptime_seconds, 86400)
    hours = div(rem(uptime_seconds, 86400), 3600)
    minutes = div(rem(uptime_seconds, 3600), 60)
    seconds = rem(uptime_seconds, 60)

    uptime_str = "#{days}d #{hours}h #{minutes}m #{seconds}s"

    # Create a deduplication key based on a time window
    # We'll use the current day as part of the key to deduplicate within the same day
    current_day = div(:os.system_time(:second), 86400)
    dedup_key = "status_report:#{current_day}"

    # Check if we've already sent a status report in this time window
    case WandererNotifier.Helpers.DeduplicationHelper.check_and_mark(dedup_key) do
      {:ok, :duplicate} ->
        Logger.info("Status report for current day already sent, skipping duplicate")
        :ok

      {:ok, :new} ->
        # Get current stats
        stats = WandererNotifier.Core.Stats.get_stats()

        # Get license information
        license_status = WandererNotifier.Core.License.status()

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
        Logger.info("Service status report - Uptime: #{uptime_str}")

        # Send the rich notification
        NotifierFactory.notify(:send_discord_embed, [discord_embed, :general])
    end
  end
end
