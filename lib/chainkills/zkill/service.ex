defmodule ChainKills.ZKill.Service do
  @moduledoc """
  Service for retrieving and enriching killmails from zKillboard + ESI.
  Fetches partial data from zKill, then merges in the full killmail from ESI.
  """

  require Logger
  alias ChainKills.ZKill.Client, as: ZKillClient
  alias ChainKills.ESI.Service, as: ESIService

  @doc """
  Given a kill_id, fetch partial from zKill's killID endpoint,
  then fetch the real killmail from ESI using the `zkb["hash"]`.
  Returns {:ok, enriched_map} or {:error, reason}.
  """
  def get_enriched_killmail(kill_id) do
    with {:ok, zkill_partial} <- ZKillClient.get_single_killmail(kill_id),
         # Expect a single-element list: [%{ "killmail_id" => ..., "zkb" => %{...}}]
         [%{"killmail_id" => kid, "zkb" => zkb_map}] <- zkill_partial,
         # The "hash" is needed to do the ESI fetch
         hash when is_binary(hash) <- zkb_map["hash"],
         # Now call ESI to get the full killmail details
         {:ok, esi_data} <- ESIService.get_esi_kill_mail(kid, hash)
    do
      # Merge the partial zKill fields ("zkb") into the ESI data
      enriched = Map.merge(esi_data, %{"zkb" => zkb_map})
      {:ok, enriched}
    else
      # If any step fails or data shape doesn't match, we log + return the error
      error ->
        Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
        error
    end
  end
end
