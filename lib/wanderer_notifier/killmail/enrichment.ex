defmodule WandererNotifier.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data with additional information from ESI.
  """

  alias WandererNotifier.ESI.Client, as: ESIClient
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
        AppLogger.kill_info("Enriching killmail struct", %{killmail: inspect(killmail, pretty: true)})

        # Extract victim info
        victim_id = get_in(esi_data, ["victim", "character_id"])
        ship_type_id = get_in(esi_data, ["victim", "ship_type_id"])
        system_id = Map.get(esi_data, "solar_system_id")
        system_name =
          case WandererNotifier.ESI.Service.get_system(system_id) do
            {:ok, %{"name" => name}} -> name
            _ -> nil
          end

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
              case WandererNotifier.ESI.Service.get_corporation_info(corporation_id) do
                {:ok, %{"name" => name}} -> name
                _ -> nil
              end
            alliance_name =
              case WandererNotifier.ESI.Service.get_alliance_info(alliance_id) do
                {:ok, %{"name" => name}} -> name
                _ -> nil
              end
            ship_type_name =
              case WandererNotifier.ESI.Service.get_type_info(ship_type_id) do
                {:ok, %{"name" => name}} -> name
                _ -> nil
              end
            weapon_type_name =
              case WandererNotifier.ESI.Service.get_type_info(weapon_type_id) do
                {:ok, %{"name" => name}} -> name
                _ -> nil
              end

            %{
              character_id: character_id,
              character_name: character_name,
              corporation_id: corporation_id,
              corporation_name: corporation_name,
              alliance_id: alliance_id,
              alliance_name: alliance_name,
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
          enriched_killmail = %Killmail{
            killmail
            | victim_name: victim_info["name"],
              victim_corporation: victim_info["corporation_id"],
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
        AppLogger.kill_warn("Failed to fetch ESI data for killmail", %{killmail_id: killmail_id, reason: inspect(reason)})
        {:error, :esi_data_missing}
    end
  end

  # Private helper functions

  defp get_character_info(nil),
    do: {:ok, %{"name" => "Unknown", "corporation_id" => nil, "alliance_id" => nil}}

  defp get_character_info(character_id) do
    case ESIClient.get_character_info(character_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:character_info_error, reason}}
    end
  end

  defp get_ship_info(ship_type_id) do
    case ESIClient.get_universe_type(ship_type_id) do
      {:ok, info} -> {:ok, info}
      {:error, reason} -> {:error, {:ship_info_error, reason}}
    end
  end
end
