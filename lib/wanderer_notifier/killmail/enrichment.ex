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
    case WandererNotifier.ESI.Service.get_killmail(killmail_id, hash) do
      {:ok, esi_data} ->
        # Attach esi_data to the killmail
        killmail = %Killmail{killmail | esi_data: esi_data}

        # Extract victim info
        victim_id = get_in(esi_data, ["victim", "character_id"])
        ship_type_id = get_in(esi_data, ["victim", "ship_type_id"])
        system_id = Map.get(esi_data, "solar_system_id")

        # Get system name first and handle any errors
        case WandererNotifier.ESI.Service.get_system(system_id) do
          {:ok, %{"name" => system_name}} ->
            # Enrich attackers
            attackers =
              esi_data
              |> Map.get("attackers", [])
              |> Enum.map(fn attacker ->
                character_id = Map.get(attacker, "character_id")
                corporation_id = Map.get(attacker, "corporation_id")
                alliance_id = Map.get(attacker, "alliance_id")
                ship_type_id = Map.get(attacker, "ship_type_id")
                weapon_type_id = Map.get(attacker, "weapon_type_id")
                damage_done = Map.get(attacker, "damage_done")
                final_blow = Map.get(attacker, "final_blow", false)
                security_status = Map.get(attacker, "security_status")
                faction_id = Map.get(attacker, "faction_id")

                # Enrich names (optional, can be async/cached in future)
                character_name =
                  case get_character_info(character_id) do
                    {:ok, info} -> info["name"]
                    _ -> nil
                  end

                corporation_name =
                  if is_nil(corporation_id) do
                    AppLogger.kill_warn("Attacker missing corporation_id", %{
                      killmail_id: killmail_id,
                      attacker: attacker
                    })

                    nil
                  else
                    case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
                      {:ok, %{"name" => name}} -> name
                      _ -> nil
                    end
                  end

                alliance_name =
                  if is_nil(alliance_id) do
                    nil
                  else
                    case WandererNotifier.ESI.Service.get_alliance_info(alliance_id) do
                      {:ok, %{"name" => name}} -> name
                      _ -> nil
                    end
                  end

                corporation_ticker =
                  if is_nil(corporation_id) do
                    nil
                  else
                    case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
                      {:ok, %{"ticker" => ticker}} -> ticker
                      _ -> nil
                    end
                  end

                alliance_ticker =
                  if is_nil(alliance_id) do
                    nil
                  else
                    case WandererNotifier.ESI.Service.get_alliance_info(alliance_id) do
                      {:ok, %{"ticker" => ticker}} -> ticker
                      _ -> nil
                    end
                  end

                ship_type_name =
                  if is_nil(ship_type_id) do
                    AppLogger.kill_warn("Attacker missing ship_type_id", %{
                      killmail_id: killmail_id,
                      attacker: attacker
                    })

                    nil
                  else
                    case WandererNotifier.ESI.Service.get_type_info(ship_type_id) do
                      {:ok, %{"name" => name}} -> name
                      _ -> nil
                    end
                  end

                weapon_type_name =
                  if is_nil(weapon_type_id) do
                    AppLogger.kill_warn("Attacker missing weapon_type_id", %{
                      killmail_id: killmail_id,
                      attacker: attacker
                    })

                    nil
                  else
                    case WandererNotifier.ESI.Service.get_type_info(weapon_type_id) do
                      {:ok, %{"name" => name}} -> name
                      _ -> nil
                    end
                  end

                %{
                  character_id: character_id,
                  character_name: character_name,
                  corporation_id: corporation_id,
                  corporation_name: corporation_name,
                  corporation_ticker: corporation_ticker,
                  alliance_id: alliance_id,
                  alliance_name: alliance_name,
                  alliance_ticker: alliance_ticker,
                  ship_type_id: ship_type_id,
                  ship_type_name: ship_type_name,
                  weapon_type_id: weapon_type_id,
                  weapon_type_name: weapon_type_name,
                  damage_done: damage_done,
                  final_blow: final_blow,
                  security_status: security_status,
                  faction_id: faction_id
                }
              end)

            with {:ok, victim_info} <- get_character_info(victim_id),
                 {:ok, ship_info} <- get_ship_info(ship_type_id) do
              # Fetch victim corporation ticker if possible
              victim_corp_ticker =
                case victim_info["corporation_id"] do
                  nil ->
                    nil

                  corp_id ->
                    case WandererNotifier.ESI.Service.get_corporation_info(corp_id) do
                      {:ok, %{"ticker" => ticker}} -> ticker
                      _ -> nil
                    end
                end

              enriched_killmail = %Killmail{
                killmail
                | victim_name: victim_info["name"],
                  victim_corporation: victim_info["corporation_id"],
                  victim_corp_ticker: victim_corp_ticker,
                  victim_alliance: Map.get(victim_info, "alliance_id"),
                  ship_name: ship_info["name"],
                  system_id: system_id,
                  system_name: system_name,
                  attackers: attackers
              }

              {:ok, enriched_killmail}
            else
              {:error, reason} ->
                AppLogger.api_error("Failed to enrich killmail", %{
                  kill_id: killmail_id,
                  error: inspect(reason)
                })

                {:error, reason}
            end

          {:error, reason} ->
            AppLogger.api_error("Failed to get system info", %{
              kill_id: killmail_id,
              system_id: system_id,
              error: inspect(reason)
            })

            {:error, reason}
        end

      {:error, reason} ->
        AppLogger.kill_warn("Failed to fetch ESI data for killmail", %{
          killmail_id: killmail_id,
          reason: inspect(reason)
        })

        {:error, :esi_data_missing}
    end
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
end
