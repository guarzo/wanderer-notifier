defmodule WandererNotifier.Maintenance.Scheduler do
  @moduledoc """
  Schedules and coordinates periodic maintenance tasks.
  """
  require Logger

  # Time intervals in seconds
  @status_interval 60
  @systems_update_interval 300
  @characters_update_interval 300
  @backup_check_interval 300
  @uptime_required_for_backup 3600

  @type state :: %{
          last_status_time: integer() | nil,
          last_systems_update: integer() | nil,
          last_characters_update: integer() | nil,
          last_backup_check: integer() | nil,
          service_start_time: integer(),
          processed_kill_ids: map()
        }

  @spec do_periodic_checks(state()) :: state()
  def do_periodic_checks(state) do
    now = :os.system_time(:second)
    Logger.info("[Maintenance] Starting periodic checks at time #{now}")

    state
    |> maybe_send_status(now)
    |> maybe_update_systems(now)
    |> maybe_update_tracked_chars(now)
    |> maybe_check_backup_kills(now)
  end

  @spec maybe_send_status(state(), integer()) :: state()
  defp maybe_send_status(state, now) do
    if now - (state.last_status_time || 0) > @status_interval do
      count = map_size(state.processed_kill_ids)
      Logger.info("[Maintenance] Status update: Processed kills: #{count}")
      %{state | last_status_time: now}
    else
      state
    end
  end

  @spec maybe_update_systems(state(), integer()) :: state()
  defp maybe_update_systems(state, now) do
    if now - (state.last_systems_update || 0) > @systems_update_interval do
      Logger.info("[Maintenance] Triggering update_systems")

      case WandererNotifier.Map.Client.update_systems() do
        {:ok, new_systems} ->
          Logger.info(
            "[Maintenance] update_systems successful: found #{length(new_systems)} wormhole systems"
          )

        {:error, err} ->
          Logger.error("[Maintenance] update_systems failed: #{inspect(err)}")
      end

      %{state | last_systems_update: now}
    else
      state
    end
  end

  @spec maybe_update_tracked_chars(state(), integer()) :: state()
  defp maybe_update_tracked_chars(state, now) do
    if now - (state.last_characters_update || 0) > @characters_update_interval do
      Logger.info("[Maintenance] Triggering update_tracked_characters")

      case WandererNotifier.Map.Client.update_tracked_characters() do
        {:ok, chars} ->
          Logger.info(
            "[Maintenance] update_tracked_characters successful: found #{length(chars)} characters"
          )

        {:error, err} ->
          Logger.error("[Maintenance] update_tracked_characters failed: #{inspect(err)}")
      end

      %{state | last_characters_update: now}
    else
      state
    end
  end

  @spec maybe_check_backup_kills(state(), integer()) :: state()
  defp maybe_check_backup_kills(state, now) do
    uptime = now - state.service_start_time

    if uptime >= @uptime_required_for_backup and
         now - (state.last_backup_check || 0) > @backup_check_interval do
      Logger.info("[Maintenance] Triggering check_backup_kills")

      case WandererNotifier.Map.Client.check_backup_kills() do
        {:ok, _msg} ->
          Logger.info("[Maintenance] check_backup_kills successful")

        {:error, err} ->
          Logger.error("[Maintenance] check_backup_kills failed: #{inspect(err)}")
      end

      %{state | last_backup_check: now}
    else
      state
    end
  end
end
