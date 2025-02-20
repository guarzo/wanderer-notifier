defmodule ChainKills.Service.Maintenance do
  @moduledoc """
  Periodic maintenance tasks:
    - logging status messages
    - updating systems
    - updating tracked characters
    - checking backup kills
  """
  require Logger
  alias ChainKills.Map.Client, as: MapClient

  @systems_update_interval_s 300
  @backup_check_interval_s 300
  @uptime_required_for_backup_s 3600

  def do_periodic_checks(state) do
    now = :os.system_time(:second)
    Logger.info("[Maintenance] Starting periodic checks at time #{now}")

    state
    |> maybe_send_status(now)
    |> maybe_update_systems(now)
    |> maybe_update_tracked_chars(now)
    |> maybe_check_backup_kills(now)
  end

  defp maybe_send_status(state, now) do
    if now - (state.last_status_time || 0) > 60 do
      count = map_size(state.processed_kill_ids)
      Logger.info("[Maintenance] Status update: Processed kills: #{count}")
      %{state | last_status_time: now}
    else
      state
    end
  end

  defp maybe_update_systems(state, now) do
    if now - (state.last_systems_update || 0) > @systems_update_interval_s do
      Logger.info("[Maintenance] Triggering update_systems")
      case MapClient.update_systems() do
        {:ok, new_systems} ->
          Logger.info("[Maintenance] update_systems successful: found #{length(new_systems)} wormhole systems")
        {:error, err} ->
          Logger.error("[Maintenance] update_systems failed: #{inspect(err)}")
      end
      %{state | last_systems_update: now}
    else
      state
    end
  end

  defp maybe_update_tracked_chars(state, now) do
    if now - (state.last_characters_update || 0) > 300 do
      Logger.info("[Maintenance] Triggering update_tracked_characters")
      case MapClient.update_tracked_characters() do
        {:ok, chars} ->
          Logger.info("[Maintenance] update_tracked_characters successful: found #{length(chars)} characters")
        {:error, err} ->
          Logger.error("[Maintenance] update_tracked_characters failed: #{inspect(err)}")
      end
      %{state | last_characters_update: now}
    else
      state
    end
  end

  defp maybe_check_backup_kills(state, now) do
    uptime = now - state.service_start_time
    if uptime >= @uptime_required_for_backup_s and (now - (state.last_backup_check || 0) > @backup_check_interval_s) do
      Logger.info("[Maintenance] Triggering check_backup_kills")
      case MapClient.check_backup_kills() do
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
