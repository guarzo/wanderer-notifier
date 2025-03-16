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

  @doc """
  Retrieves recent kills from zKillboard.

  ## Parameters

  - `limit`: The maximum number of kills to retrieve (default: 10)

  ## Returns

  - `{:ok, kills}`: A list of recent kills
  - `{:error, reason}`: If an error occurred
  """
  @spec get_recent_kills(integer()) :: {:ok, list(map())} | {:error, any()}
  def get_recent_kills(limit \\ 10) do
    ZKillClient.get_recent_kills(limit)
  end

  @doc """
  Retrieves kills for a specific system from zKillboard.

  ## Parameters

  - `system_id`: The ID of the system to get kills for
  - `limit`: The maximum number of kills to retrieve (default: 5)

  ## Returns

  - `{:ok, kills}`: A list of kills for the system
  - `{:error, reason}`: If an error occurred
  """
  @spec get_system_kills(any(), integer()) :: {:ok, list(map())} | {:error, any()}
  def get_system_kills(system_id, limit \\ 5) do
    ZKillClient.get_system_kills(system_id, limit)
  end
end
