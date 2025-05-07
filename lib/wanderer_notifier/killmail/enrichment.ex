defmodule WandererNotifier.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data with additional information from ESI.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger
  alias WandererNotifier.Killmail.Killmail

  @doc """
  Enriches killmail data with additional information from ESI.

  ## Parameters
    - killmail: The killmail data to enrich

  ## Returns
    - {:ok, enriched_killmail} on success
    - {:error, reason} on failure
  """
  def enrich_killmail_data(%Killmail{killmail_id: killmail_id, zkb: %{"hash" => hash}} = killmail) do
    with {:ok, esi_data} <- get_killmail_data(killmail_id, hash),
         {:ok, system_name} <- get_system_name(esi_data["solar_system_id"]),
         {:ok, victim_info} <- get_victim_info(esi_data["victim"]),
         {:ok, ship_info} <- get_ship_info(esi_data["victim"]["ship_type_id"]),
         {:ok, attackers} <- enrich_attackers(esi_data["attackers"], killmail_id) do
      enriched_killmail =
        build_enriched_killmail(
          killmail,
          esi_data,
          system_name,
          victim_info,
          ship_info,
          attackers
        )

      {:ok, enriched_killmail}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_killmail_data(killmail_id, hash) do
    case WandererNotifier.ESI.Service.get_killmail(killmail_id, hash) do
      {:ok, esi_data} ->
        {:ok, esi_data}

      {:error, reason} ->
        AppLogger.kill_warn("Failed to fetch ESI data for killmail", %{
          killmail_id: killmail_id,
          reason: inspect(reason)
        })

        {:error, :esi_data_missing}
    end
  end

  defp get_system_name(system_id) do
    case WandererNotifier.ESI.Service.get_system(system_id) do
      {:ok, %{"name" => name}} ->
        {:ok, name}

      {:error, reason} ->
        AppLogger.api_error("Failed to get system info", %{
          system_id: system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp get_victim_info(victim) do
    with {:ok, character_info} <- get_character_info(victim["character_id"]),
         {:ok, corp_ticker} <- get_corp_ticker(character_info["corporation_id"]) do
      {:ok, Map.put(character_info, "corp_ticker", corp_ticker)}
    end
  end

  defp get_corp_ticker(nil), do: {:ok, nil}

  defp get_corp_ticker(corp_id) do
    case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
      {:ok, %{"ticker" => ticker}} -> {:ok, ticker}
      _ -> {:ok, nil}
    end
  end

  defp enrich_attackers(attackers, killmail_id) do
    enriched = Enum.map(attackers, &enrich_attacker(&1, killmail_id))
    {:ok, enriched}
  end

  defp enrich_attacker(attacker, _killmail_id) do
    with {:ok, character_info} <- get_character_info(attacker["character_id"]),
         {:ok, corp_info} <- get_corp_info(attacker["corporation_id"]),
         {:ok, alliance_info} <- get_alliance_info(attacker["alliance_id"]),
         {:ok, ship_info} <- get_ship_info(attacker["ship_type_id"]),
         {:ok, weapon_info} <- get_weapon_info(attacker["weapon_type_id"]) do
      build_attacker_info(
        attacker,
        character_info,
        corp_info,
        alliance_info,
        ship_info,
        weapon_info
      )
    end
  end

  defp build_attacker_info(
         attacker,
         character_info,
         corp_info,
         alliance_info,
         ship_info,
         weapon_info
       ) do
    %{
      character_id: attacker["character_id"],
      character_name: character_info["name"],
      corporation_id: attacker["corporation_id"],
      corporation_name: corp_info["name"],
      corporation_ticker: corp_info["ticker"],
      alliance_id: attacker["alliance_id"],
      alliance_name: alliance_info["name"],
      alliance_ticker: alliance_info["ticker"],
      ship_type_id: attacker["ship_type_id"],
      ship_type_name: ship_info["name"],
      weapon_type_id: attacker["weapon_type_id"],
      weapon_type_name: weapon_info["name"],
      damage_done: attacker["damage_done"],
      final_blow: attacker["final_blow"],
      security_status: attacker["security_status"],
      faction_id: attacker["faction_id"]
    }
  end

  defp build_enriched_killmail(killmail, esi_data, system_name, victim_info, ship_info, attackers) do
    %Killmail{
      killmail
      | victim_name: victim_info["name"],
        victim_corporation: victim_info["corporation_id"],
        victim_corp_ticker: victim_info["corp_ticker"],
        victim_alliance: victim_info["alliance_id"],
        ship_name: ship_info["name"],
        system_id: esi_data["solar_system_id"],
        system_name: system_name,
        attackers: attackers
    }
  end

  @doc """
  Fetches and formats recent kills for a system, suitable for system notifications.

  ## Parameters
    - system_id: The solar system ID
    - limit: Number of kills to fetch

  ## Returns
    - List of formatted strings for each kill
  """
  def recent_kills_for_system(system_id, limit \\ 3) do
    case WandererNotifier.Killmail.ZKillClient.get_system_kills(system_id, limit) do
      {:ok, kills} when is_list(kills) ->
        kills
        |> Enum.map(&enrich_killmail_for_system/1)
        |> Enum.map(&format_kill_for_system/1)
        |> Enum.filter(&is_binary/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp enrich_killmail_for_system(kill) do
    kill_id = Map.get(kill, "killmail_id")
    hash = get_in(kill, ["zkb", "hash"])

    case WandererNotifier.ESI.Service.get_killmail(kill_id, hash) do
      {:ok, esi_data} -> Map.put(kill, "esi_data", esi_data)
      _ -> kill
    end
  end

  defp format_kill_for_system(kill) do
    kill_id = Map.get(kill, "killmail_id")
    esi_data = Map.get(kill, "esi_data", %{})
    victim = Map.get(esi_data, "victim", %{})
    ship_type_id = Map.get(victim, "ship_type_id")
    character_id = Map.get(victim, "character_id")
    kill_time = Map.get(esi_data, "killmail_time")
    value = get_in(kill, ["zkb", "totalValue"]) || 0

    # Get ship name from ESI
    ship_name =
      case WandererNotifier.ESI.Service.get_ship_type_name(ship_type_id) do
        {:ok, %{"name" => name}} -> name
        _ -> "Unknown Ship"
      end

    # Get victim name from ESI
    victim_name =
      case WandererNotifier.ESI.Service.get_character_info(character_id) do
        {:ok, %{"name" => name}} -> name
        _ -> "Unknown"
      end

    # Format time since kill
    time_ago = format_time_ago(kill_time)
    formatted_value = format_isk_value(value)

    if kill_id && ship_name && victim_name do
      "[#{ship_name}](https://zkillboard.com/kill/#{kill_id}/) - #{formatted_value} ISK, #{time_ago} ago"
    else
      ""
    end
  end

  defp format_time_ago(nil), do: "?"

  defp format_time_ago(kill_time) do
    case DateTime.from_iso8601(kill_time) do
      {:ok, dt, _} ->
        now = DateTime.utc_now()
        diff = DateTime.diff(now, dt, :second)

        cond do
          diff < 3600 -> "<1h"
          diff < 86_400 -> "#{div(diff, 3600)}h"
          true -> "#{div(diff, 86_400)}d"
        end

      _ ->
        "?"
    end
  end

  defp format_isk_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> "#{Float.round(value / 1_000_000_000, 1)}B"
      value >= 1_000_000 -> "#{Float.round(value / 1_000_000, 1)}M"
      value >= 1_000 -> "#{Float.round(value / 1_000, 1)}K"
      true -> "#{Float.round(value, 0)}"
    end
  end

  # Private helper functions

  defp get_character_info(nil),
    do: {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}

  defp get_character_info(character_id) do
    case WandererNotifier.ESI.Service.get_character_info(character_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:character_info_error, reason}}
    end
  end

  defp get_ship_info(ship_type_id) do
    case WandererNotifier.ESI.Service.get_type_info(ship_type_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:ship_info_error, reason}}
    end
  end

  defp get_corp_info(corporation_id) do
    case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:corp_info_error, reason}}
    end
  end

  defp get_alliance_info(alliance_id) do
    case WandererNotifier.ESI.Service.get_alliance_info(alliance_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:alliance_info_error, reason}}
    end
  end

  defp get_weapon_info(weapon_type_id) do
    case WandererNotifier.ESI.Service.get_type_info(weapon_type_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:weapon_info_error, reason}}
    end
  end
end
