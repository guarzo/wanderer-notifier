defmodule WandererNotifier.Services.Maintenance.Scheduler do
  @moduledoc """
  Schedules and executes maintenance tasks.
  Handles periodic updates for systems and characters.
  """
  require Logger
  alias WandererNotifier.Api.Map.Client, as: MapClient
  alias WandererNotifier.Cache.Repository, as: CacheRepo
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

    # Log status
    if now - state.last_status_time > 3600 do
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

      case MapClient.update_tracked_characters(cached_characters) do
        {:ok, characters} ->
          Logger.info("Characters updated: #{length(characters)} characters found")
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

    # Get current stats
    stats = WandererNotifier.Core.Stats.get_stats()

    # Format status message
    status_message = """
    SERVICE STATUS REPORT
    Uptime: #{uptime_str}
    Notifications sent: #{stats.notifications.total}
    Kill notifications: #{stats.notifications.kills}
    System notifications: #{stats.notifications.systems}
    Character notifications: #{stats.notifications.characters}
    WebSocket connected: #{if stats.websocket.connected, do: "Yes", else: "No"}
    WebSocket reconnects: #{stats.websocket.reconnects}
    """

    # Log status and also send as a notification
    Logger.info(status_message)
    NotifierFactory.notify(:send_message, [status_message])
  end
end
