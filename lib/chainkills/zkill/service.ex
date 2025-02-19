defmodule ChainKills.ZKill.Service do
  @moduledoc """
  Service for retrieving and enriching killmails from zKillboard + ESI.
  """
  require Logger
  alias ChainKills.ZKill.Client, as: ZKillClient
  alias ChainKills.ESI.Service, as: ESIService

  def get_enriched_killmail(kill_id) do
    with {:ok, killmail} <- ZKillClient.get_single_killmail(kill_id),
         %{"ZKB" => %{"hash" => hash}} <- killmail,
         {:ok, enriched} <- ESIService.get_esi_kill_mail(kill_id, hash)
    do
      {:ok, Map.merge(enriched, %{"ZKB" => killmail["ZKB"]})}
    else
      error ->
        Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
        error
    end
  end
end
