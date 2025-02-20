defmodule ChainKills.Map.BackupKills do
  @moduledoc """
  Processes backup kills from the map API.
  """
  require Logger
  alias ChainKills.Http.Client, as: HttpClient
  alias ChainKills.Cache.Repository, as: CacheRepo

  def check_backup_kills do
    with {:ok, backup_url} <- build_backup_url() do
      map_token = Application.get_env(:chainkills, :map_token)
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
          Logger.error("[check_backup_kills] error: #{inspect(msg)}")
          {:error, msg}
      end
    else
      {:error, msg} = err ->
        Logger.error("[check_backup_kills] error: #{inspect(msg)}")
        err
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
      {:ok, data} -> {:ok, data}
      error ->
        Logger.error("[check_backup_kills] Error decoding JSON: #{inspect(error)}")
        {:error, error}
    end
  end

  defp process_backup_kills(%{"data" => data}) when is_list(data) do
    tracked_systems = CacheRepo.get("map:systems") || []
    tracked_ids = Enum.map(tracked_systems, fn s -> to_string(s.system_id) end)
    Logger.info("Tracked wormhole system IDs: #{inspect(tracked_ids)}")

    kill_feed_ids =
      data
      |> Enum.filter(fn sys -> (sys["kills"] || sys["Kills"]) != [] end)
      |> Enum.map(fn sys -> to_string(sys["solar_system_id"] || sys["SolarSystemID"]) end)
    Logger.info("Kill feed system IDs with kills: #{inspect(kill_feed_ids)}")

    Enum.each(data, fn sys_entry ->
      id = sys_entry["solar_system_id"] || sys_entry["SolarSystemID"]
      sys_id = to_string(id)
      kills = sys_entry["kills"] || sys_entry["Kills"]

      if kills != [] and sys_id in tracked_ids do
        Enum.each(kills, fn kill ->
          process_backup_kill(sys_id, kill)
        end)
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
        kill_url = "https://zkillboard.com/kill/#{kill_id}"
        Logger.info("Found kill in backup feed from system #{system_id_str}: killID=#{kill_id}")

        # Send plain text message for auto‑unfurling.
        ChainKills.Discord.Notifier.send_message(kill_url)

        # Try to enrich the killmail and send the enriched embed.
        case ChainKills.ZKill.Service.get_enriched_killmail(kill_id) do
          {:ok, enriched_kill} ->
            ChainKills.Discord.Notifier.send_enriched_kill_embed(enriched_kill, kill_id)
          {:error, err} ->
            Logger.error("Error enriching backup kill #{kill_id}: #{inspect(err)}")
        end

        # Mark this kill as processed in the cache.
        CacheRepo.put(kill_cache_key, :os.system_time(:second))

        case ChainKills.ZKill.Service.get_enriched_killmail(kill_id) do
          {:ok, _enriched} ->
            Logger.info("Processed backup kill #{kill_id}")
          {:error, err} ->
            Logger.error("Error processing backup kill #{kill_id}: #{inspect(err)}")
        end

      _ ->
        Logger.info("Kill #{kill_id} already processed, skipping.")
    end
  end

  defp validate_map_env do
    map_url  = Application.get_env(:chainkills, :map_url)
    map_name = Application.get_env(:chainkills, :map_name)
    if map_url in [nil, ""] or map_name in [nil, ""] do
      {:error, "map_url or map_name not configured"}
    else
      {:ok, map_url, map_name}
    end
  end
end
