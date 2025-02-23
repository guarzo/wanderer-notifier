defmodule ChainKills.ZKill.Service do
  @moduledoc """
  Service for retrieving and enriching killmails from zKillboard + ESI.
  Fetches partial data from zKill, then merges in the full killmail from ESI.
  """

  require Logger
  alias ChainKills.ZKill.Client, as: ZKillClient
  alias ChainKills.ESI.Service, as: ESIService

  def get_enriched_killmail(kill_id) do
    with {:ok, zkill_partial} <- ZKillClient.get_single_killmail(kill_id),
         # Expect a single-element list: [%{"killmail_id" => kid, "zkb" => zkb_map}]
         [%{"killmail_id" => kid, "zkb" => zkb_map}] <- zkill_partial do
      if is_binary(zkb_map["hash"]) do
        hash = zkb_map["hash"]

        case ESIService.get_esi_kill_mail(kid, hash) do
          {:ok, esi_data} ->
            enriched = Map.merge(esi_data, %{"zkb" => zkb_map})
            {:ok, enriched}

          error ->
            Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
            error
        end
      else
        error = {:error, "Invalid or missing hash for killmail #{kill_id}"}
        Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
        error
      end
    else
      error ->
        Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
        error
    end
  end
end
