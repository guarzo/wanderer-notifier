defmodule WandererNotifier.Killmail.Enrichment do
  @moduledoc """
  Handles enrichment of killmail data with additional information from ESI.
  """

  alias WandererNotifier.Killmail.Killmail
  require Logger

  @esi_service Application.compile_env(
                 :wanderer_notifier,
                 :esi_service,
                 WandererNotifier.ESI.Service
               )
  @zkill_client Application.compile_env(
                  :wanderer_notifier,
                  :zkill_client,
                  WandererNotifier.Killmail.ZKillClient
                )

  @doc """
  Enriches killmail data with additional information from ESI.

  ## Parameters
    - killmail: The killmail data to enrich

  ## Returns
    - {:ok, enriched_killmail} on success
    - {:error, reason} on failure
  """
  def enrich_killmail_data(
        %Killmail{killmail_id: _killmail_id, zkb: %{"hash" => _hash}, esi_data: esi_data} =
          killmail
      )
      when map_size(esi_data) > 0 do
    Logger.info("Enriching killmail with ESI data, system_id=#{esi_data["solar_system_id"]}")

    case get_victim_info(esi_data["victim"]) do
      {:error, :service_unavailable} = error ->
        error

      {:error, _} ->
        {:error, :esi_data_missing}

      {:ok, victim_info} ->
        with {:ok, system_name} <- get_system_name(esi_data["solar_system_id"]),
             {:ok, attackers} <- enrich_attackers(esi_data["attackers"]) do
          enriched_killmail = %{
            killmail
            | victim_name: victim_info.character_name,
              victim_corporation: victim_info.corporation_name,
              victim_corp_ticker: victim_info.corporation_ticker,
              ship_name: victim_info.ship_name,
              system_name: system_name,
              system_id: esi_data["solar_system_id"],
              attackers: attackers
          }

          {:ok, enriched_killmail}
        else
          {:error, :service_unavailable} = error -> error
          {:error, _} -> {:error, :esi_data_missing}
        end
    end
  end

  def enrich_killmail_data(%Killmail{killmail_id: killmail_id, zkb: %{"hash" => hash}} = killmail) do
    case get_killmail_data(killmail_id, hash) do
      {:error, :service_unavailable} = error ->
        error

      {:error, _} ->
        {:error, :esi_data_missing}

      {:ok, esi_data} ->
        case get_victim_info(esi_data["victim"]) do
          {:error, :service_unavailable} = error ->
            error

          {:error, _} ->
            {:error, :esi_data_missing}

          {:ok, victim_info} ->
            with {:ok, system_name} <- get_system_name(esi_data["solar_system_id"]),
                 {:ok, attackers} <- enrich_attackers(esi_data["attackers"]) do
              enriched_killmail = %{
                killmail
                | esi_data: esi_data,
                  victim_name: victim_info.character_name,
                  victim_corporation: victim_info.corporation_name,
                  victim_corp_ticker: victim_info.corporation_ticker,
                  ship_name: victim_info.ship_name,
                  system_name: system_name,
                  system_id: esi_data["solar_system_id"],
                  attackers: attackers
              }

              {:ok, enriched_killmail}
            else
              {:error, :service_unavailable} = error -> error
              {:error, _} -> {:error, :esi_data_missing}
            end
        end
    end
  end

  defp get_killmail_data(killmail_id, hash) do
    case @esi_service.get_killmail(killmail_id, hash) do
      {:ok, esi_data} -> {:ok, esi_data}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, :not_found} -> {:error, :esi_data_missing}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_system_name(nil), do: {:ok, "Unknown System"}

  defp get_system_name(system_id) when is_integer(system_id) or is_binary(system_id) do
    case @esi_service.get_system(system_id, []) do
      {:ok, %{"name" => name}} -> {:ok, name}
      {:error, :not_found} -> {:error, :system_not_found}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_system_name(_), do: {:ok, "Unknown System"}

  defp get_victim_info(victim) do
    with {:ok, character_info} <- get_character_info(victim["character_id"]),
         {:ok, corporation_info} <- get_corporation_info(victim["corporation_id"]),
         {:ok, ship_info} <- get_ship_info(victim["ship_type_id"]) do
      {:ok,
       %{
         character_name: character_info["name"],
         corporation_name: corporation_info["name"],
         corporation_ticker: corporation_info["ticker"],
         alliance_name: nil,
         ship_name: ship_info["name"]
       }}
    else
      {:error, :service_unavailable} = error -> error
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_ship_info(nil), do: {:error, :esi_data_missing}

  defp get_ship_info(ship_type_id) when is_integer(ship_type_id) or is_binary(ship_type_id) do
    case @esi_service.get_type_info(ship_type_id, []) do
      {:ok, %{"name" => name}} -> {:ok, %{"name" => name}}
      {:ok, ship} -> {:ok, ship}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_ship_info(_), do: {:error, :esi_data_missing}

  defp get_character_info(character_id) when is_integer(character_id) do
    case @esi_service.get_character_info(character_id, []) do
      {:ok, info} -> {:ok, info}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_character_info(nil), do: {:error, :esi_data_missing}
  defp get_character_info(_), do: {:error, :esi_data_missing}

  defp get_corporation_info(corporation_id) when is_integer(corporation_id) do
    case @esi_service.get_corporation_info(corporation_id, []) do
      {:ok, info} -> {:ok, info}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_corporation_info(_), do: {:error, :esi_data_missing}

  defp get_alliance_info(alliance_id) when is_integer(alliance_id) do
    case @esi_service.get_alliance_info(alliance_id, []) do
      {:ok, info} -> {:ok, info}
      {:error, :service_unavailable} -> {:error, :service_unavailable}
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  defp get_alliance_info(_), do: {:ok, %{"name" => "Unknown"}}

  defp enrich_attackers(nil), do: {:ok, []}

  defp enrich_attackers(attackers) when is_list(attackers) do
    # Process each attacker and collect results
    results = Enum.map(attackers, &enrich_attacker/1)

    # Check if any errors occurred
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, attacker} -> attacker end)}
      error -> error
    end
  end

  defp enrich_attacker(attacker) do
    with {:ok, character_info} <- get_character_info(attacker["character_id"]),
         {:ok, corporation_info} <- get_corporation_info(attacker["corporation_id"]),
         {:ok, alliance_info} <- get_alliance_info(attacker["alliance_id"]),
         {:ok, ship_info} <- get_ship_info(attacker["ship_type_id"]) do
      {:ok,
       Map.merge(attacker, %{
         "character_name" => character_info["name"],
         "corporation_name" => corporation_info["name"],
         "corporation_ticker" => corporation_info["ticker"],
         "alliance_name" => alliance_info["name"],
         "ship_name" => ship_info["name"]
       })}
    else
      {:error, :service_unavailable} = error -> error
      {:error, _} -> {:error, :esi_data_missing}
    end
  end

  @doc """
  Fetches and formats recent kills for a system.
  Returns a formatted string that's safe to use in Discord.

  ## Parameters
    - system_id: The solar system ID
    - limit: Number of kills to fetch

  ## Returns
    - A string with formatted kill data with links
  """
  def recent_kills_for_system(system_id, limit \\ 3) do
    try do
      # Call ZKill client - response should be already formatted strings with links
      case @zkill_client.get_system_kills(system_id, limit) do
        {:ok, kill_strings} when is_list(kill_strings) and length(kill_strings) > 0 ->
          # Join the pre-formatted strings with newlines
          # The strings should already be formatted as markdown links
          Enum.join(kill_strings, "\n")

        {:ok, []} ->
          "No recent kills found"

        {:error, reason} ->
          Logger.warning("Error getting kills", %{details: inspect(reason)})
          "Error retrieving kill data"

        unexpected ->
          Logger.warning("Unexpected response from ZKillClient", %{details: inspect(unexpected)})
          "Unexpected kill data response"
      end
    rescue
      e ->
        Logger.error("Exception in recent_kills_for_system", %{details: Exception.message(e)})
        "Error retrieving kill data"
    end
  end
end
