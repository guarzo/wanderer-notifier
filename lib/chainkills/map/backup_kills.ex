defmodule ChainKills.Map.BackupKills do
  @moduledoc """
  Logic for the backup kills endpoint from the map API.
  """
  require Logger
  alias ChainKills.Http.Client, as: HttpClient
  alias ChainKills.Cache.Repository, as: CacheRepo

  def check_backup_kills do
    with {:ok, backup_url} <- build_backup_url(),
         {:ok, body}       <- HttpClient.request("GET", backup_url),
         {:ok, data_body}  <- extract_body(body),
         {:ok, backup_json} <- decode_json(data_body)
    do
      process_backup_kills(backup_json)
    else
      {:error, msg} = err ->
        Logger.error("[check_backup_kills] error: #{inspect(msg)}")
        err
    end
  end

  # private

  defp build_backup_url do
    case validate_map_env() do
      {:ok, map_url, map_name} ->
        {:ok, "#{map_url}/api/map/systems-kills?slug=#{map_name}&hours_ago=1"}
      {:error, _} = err ->
        err
    end
  end

  defp extract_body(%{status_code: 200, body: body}), do: {:ok, body}
  defp extract_body(%{status_code: status}), do: {:error, "Unexpected status: #{status}"}
  defp extract_body(other), do: other

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, data} -> {:ok, data}
      error -> {:error, error}
    end
  end

  defp process_backup_kills(%{"Data" => data}) when is_list(data) do
    Logger.info("Backup feed returned #{length(data)} system entries")
    systems = CacheRepo.get("map:systems") || []
    system_ids = Enum.map(systems, & &1.system_id)

    Enum.each(data, fn sys_entry ->
      system_id = sys_entry["SolarSystemID"]
      process_backup_sys_entry(system_id, sys_entry["Kills"], system_ids)
    end)

    {:ok, "Backup kills processed"}
  end

  defp process_backup_kills(_other) do
    Logger.warning("Backup feed missing 'Data' or is not a list")
    {:ok, "No kills processed"}
  end

  defp process_backup_sys_entry(system_id, kills, system_ids) do
    if system_id in system_ids do
      Enum.each(kills || [], &process_backup_kill(system_id, &1))
    else
      Logger.info("Skipping backup feed for untracked system #{system_id}")
    end
  end

  defp process_backup_kill(system_id, kill) do
    kill_id = kill["KillmailID"]
    Logger.info("Found new kill in backup feed from system #{system_id}: killID=#{kill_id}")

    ChainKills.Discord.Notifier.send_message(
      "Found kill in backup feed from system #{system_id}: killID=#{kill_id}"
    )

    case ChainKills.ZKill.Service.get_enriched_killmail(kill_id) do
      {:ok, _enriched} ->
        Logger.info("Processed backup kill #{kill_id}")

      {:error, err} ->
        Logger.error("Error processing backup kill #{kill_id}: #{inspect(err)}")
    end
  end

  defp validate_map_env do
    map_url  = Application.get_env(:chainkills, :map_url)
    map_name = Application.get_env(:chainkills, :map_name)

    cond do
      map_url in [nil, ""] or map_name in [nil, ""] ->
        {:error, "map_url or map_name not configured"}
      true ->
        {:ok, map_url, map_name}
    end
  end
end
