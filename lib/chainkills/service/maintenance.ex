defmodule ChainKills.Service.Maintenance do
  @moduledoc """
  Periodic maintenance tasks:
    - status messages
    - updating systems
    - updating tracked chars
    - checking backup kills
  """
  require Logger
  alias ChainKills.Discord.Notifier
  alias ChainKills.Map.Client, as: MapClient

  @systems_update_interval_s 300
  @backup_check_interval_s 600
  @uptime_required_for_backup_s 3600

  def do_periodic_checks(state) do
    now = :os.system_time(:second)

    state
    |> maybe_send_status(now)
    |> maybe_update_systems(now)
    |> maybe_update_tracked_chars(now)
    |> maybe_check_backup_kills(now)
  end

  # ------------------------------------------------------------------
  # private helpers
  # ------------------------------------------------------------------

  defp maybe_send_status(state, now) do
    if now - (state.last_status_time || 0) > 60 do
      count = map_size(state.processed_kill_ids)
      Notifier.send_message("ChainKillsService still alive. Processed kills: #{count}")
      %{state | last_status_time: now}
    else
      state
    end
  end

  defp maybe_update_systems(state, now) do
    if now - (state.last_systems_update || 0) > @systems_update_interval_s do
      case MapClient.update_systems() do
        {:ok, new_systems} ->
          Notifier.send_message("Updated systems, found #{length(new_systems)} wormhole systems")

        {:error, err} ->
          Notifier.send_message("update_systems error: #{inspect(err)}")
      end

      %{state | last_systems_update: now}
    else
      state
    end
  end

  defp maybe_update_tracked_chars(state, now) do
    if now - (state.last_characters_update || 0) > 300 do
      case MapClient.update_tracked_characters() do
        {:ok, chars} ->
          Notifier.send_message("Updated tracked chars, found #{length(chars)} characters")

        {:error, err} ->
          Notifier.send_message("update_tracked_characters error: #{inspect(err)}")
      end

      %{state | last_characters_update: now}
    else
      state
    end
  end

  defp maybe_check_backup_kills(state, now) do
    uptime = now - state.service_start_time
    if uptime >= @uptime_required_for_backup_s and (now - (state.last_backup_check || 0) > @backup_check_interval_s) do
      case MapClient.check_backup_kills() do
        {:ok, _msg} -> :ok
        {:error, err} ->
          Notifier.send_message("check_backup_kills error: #{inspect(err)}")
      end
      %{state | last_backup_check: now}
    else
      state
    end
  end
end
