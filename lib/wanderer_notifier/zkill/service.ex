defmodule WandererNotifier.ZKill.Service do
  @moduledoc """
  High-level zKillboard service.
  """

  require Logger
  alias WandererNotifier.ZKill.Client, as: ZKillClient
  alias WandererNotifier.ESI.Service, as: ESIService
  alias WandererNotifier.Killmail

  @doc """
  Retrieves an enriched killmail by merging data from zKill and ESI.
  """
  @spec get_enriched_killmail(any()) :: {:ok, Killmail.t()} | {:error, any()}
  def get_enriched_killmail(kill_id) do
    with {:ok, [partial | _]} <- ZKillClient.get_single_killmail(kill_id),
         %{"killmail_id" => kid, "zkb" => zkb_map} <- partial,
         true <- is_binary(zkb_map["hash"]),
         hash = zkb_map["hash"],
         {:ok, esi_data} <- ESIService.get_esi_kill_mail(kid, hash) do
      enriched = %Killmail{killmail_id: kid, zkb: zkb_map, esi_data: esi_data}
      {:ok, enriched}
    else
      error ->
        Logger.error("Failed to get enriched killmail for #{kill_id}: #{inspect(error)}")
        error
    end
  end
end
