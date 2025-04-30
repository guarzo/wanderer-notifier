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
  def enrich_killmail_data(killmail) when is_struct(killmail, Killmail) do
    with {:ok, victim_info} <- get_character_info(killmail.victim_id),
         {:ok, attacker_info} <- get_character_info(killmail.attacker_id),
         {:ok, ship_info} <- get_ship_info(killmail.ship_type_id) do
      enriched_killmail = %{
        killmail
        | victim_name: victim_info["name"],
          victim_corporation: victim_info["corporation_id"],
          victim_alliance: victim_info["alliance_id"],
          attacker_name: attacker_info["name"],
          attacker_corporation: attacker_info["corporation_id"],
          attacker_alliance: attacker_info["alliance_id"],
          ship_name: ship_info["name"]
      }

      {:ok, enriched_killmail}
    else
      {:error, reason} ->
        AppLogger.api_error("Failed to enrich killmail", %{
          kill_id: killmail.kill_id,
          error: inspect(reason)
        })

        {:error, reason}
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
