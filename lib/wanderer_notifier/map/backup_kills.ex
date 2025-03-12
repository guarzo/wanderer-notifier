defmodule WandererNotifier.Map.BackupKills do
  @moduledoc """
  Processes backup kills from the map API.
  """
  require Logger
  alias WandererNotifier.Http.Client, as: HttpClient
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Config

  def check_backup_kills do
    case build_backup_url() do
      {:ok, backup_url} ->
        map_token = Config.map_token()
        headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []

        case HttpClient.request("GET", backup_url, headers) do
          {:ok, response} ->
            with {:ok, data_body} <- extract_body(response),
                 {:ok, backup_json} <- decode_json(data_body) do
              process_backup_kills(backup_json)
            else
              {:error, msg} = err ->
                Logger.error("[check_backup_kills] error: #{inspect(msg)}")
                err
            end

          {:error, msg} ->
            Logger.error("[check_backup_kills] HTTP request error: #{inspect(msg)}")
            {:error, msg}
        end

      {:error, msg} ->
        Logger.error("[check_backup_kills] error building backup URL: #{inspect(msg)}")
        {:error, msg}
    end
  end

  defp build_backup_url do
    case validate_map_env() do
      {:ok, map_url, map_name} ->
        url = "#{map_url}/api/map/systems-kills?slug=#{map_name}&hours_ago=24"
        {:ok, url}

      {:error, _} = err ->
        err
    end
  end

  defp extract_body(%{status_code: 200, body: body}), do: {:ok, body}
  defp extract_body(%{status_code: status}), do: {:error, "Unexpected status: #{status}"}
  defp extract_body(other), do: other

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, data} ->
        {:ok, data}

      error ->
        Logger.error("[check_backup_kills] Error decoding JSON: #{inspect(error)}")
        {:error, error}
    end
  end

  defp process_backup_kills(%{"data" => data}) when is_list(data) do
    tracked_systems = CacheRepo.get("map:systems") || []
    tracked_ids = Enum.map(tracked_systems, fn s -> to_string(s.system_id) end)

    # Go through each system in the feed
    Enum.each(data, fn sys_entry ->
      id = sys_entry["solar_system_id"] || sys_entry["SolarSystemID"]
      sys_id = to_string(id)
      kills = sys_entry["kills"] || sys_entry["Kills"] || []

      # Only process kills if system is tracked
      if kills != [] and sys_id in tracked_ids do
        Enum.each(kills, &process_backup_kill(sys_id, &1))
      end
    end)

    {:ok, "Backup kills processed"}
  end

  defp process_backup_kills(_other) do
    Logger.warning("Backup feed missing 'data' or is not a list")
    {:ok, "No kills processed"}
  end

  defp process_backup_kill(system_id_str, kill) do
    kill_id = kill["killmail_id"] || kill["KillmailID"]
    kill_cache_key = "processed:kill:#{kill_id}"

    case CacheRepo.get(kill_cache_key) do
      nil ->
        Logger.info("Found kill in backup feed from system #{system_id_str}: killID=#{kill_id}")

        case WandererNotifier.ZKill.Service.get_enriched_killmail(kill_id) do
          {:ok, enriched_kill} ->
            WandererNotifier.Discord.Notifier.send_enriched_kill_embed(enriched_kill, kill_id)
            Logger.info("Processed backup kill #{kill_id}")

            WandererNotifier.Service.mark_as_processed(kill_id)

          {:error, err} ->
            Logger.error("Error enriching backup kill #{kill_id}: #{inspect(err)}")
        end

        # Mark in CacheRepo so we don't send duplicates
        CacheRepo.put(kill_cache_key, :os.system_time(:second))

      _ ->
        Logger.debug("Backup kill #{kill_id} already processed, skipping.")
    end
  end

  defp validate_map_env do
    map_url = Config.map_url()
    map_name = Config.map_name()

    if map_url in [nil, ""] or map_name in [nil, ""] do
      {:error, "map_url or map_name not configured"}
    else
      {:ok, map_url, map_name}
    end
  end
end
