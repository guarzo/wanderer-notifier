defmodule WandererNotifier.Api.ZKill.Service do
  @moduledoc """
  Service for accessing zKillboard data.
  Provides higher-level functions for retrieving and processing kill data.
  """

  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.ZKill.Client, as: ZKillClient
  alias WandererNotifier.Api.ESI.Service, as: ESIService
  alias WandererNotifier.Data.Killmail

  @type kill_id :: String.t() | integer()
  @type system_id :: String.t() | integer()

  @doc """
  Retrieves an enriched killmail by merging data from zKill and ESI.

  ## Parameters

  - `kill_id`: The ID of the kill to retrieve (string or integer)

  ## Returns

  - `{:ok, Killmail.t()}`: A successfully enriched killmail
  - `{:error, reason}`: If an error occurred
  """
  @spec get_enriched_killmail(kill_id()) :: {:ok, Killmail.t()} | {:error, any()}
  def get_enriched_killmail(kill_id) do
    with {:ok, [partial | _]} <- ZKillClient.get_single_killmail(kill_id),
         %{"killmail_id" => kid, "zkb" => zkb_map} <- partial,
         true <- is_binary(zkb_map["hash"]),
         hash = zkb_map["hash"],
         {:ok, esi_data} <- ESIService.get_esi_kill_mail(kid, hash) do
      enriched = %Killmail{killmail_id: kid, zkb: zkb_map, esi_data: esi_data}
      {:ok, enriched}
    else
      {:error, reason} ->
        AppLogger.api_error("Failed to get enriched killmail for #{kill_id}: #{inspect(reason)}")
        {:error, reason}

      false ->
        reason = "Missing or invalid hash in zKill data"
        AppLogger.api_error("Failed to get enriched killmail for #{kill_id}: #{reason}")
        {:error, reason}

      %{} = incomplete_data ->
        reason = "Incomplete kill data, missing required fields"

        Logger.error(
          "Failed to get enriched killmail for #{kill_id}: #{reason}, data: #{inspect(incomplete_data)}"
        )

        {:error, reason}

      error ->
        reason = "Unexpected error: #{inspect(error)}"
        AppLogger.api_error("Failed to get enriched killmail for #{kill_id}: #{reason}")
        {:error, reason}
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

  - `system_id`: The ID of the system to get kills for (string or integer)
  - `limit`: The maximum number of kills to retrieve (default: 5)

  ## Returns

  - `{:ok, kills}`: A list of kills for the system
  - `{:error, reason}`: If an error occurred
  """
  @spec get_system_kills(system_id(), integer()) :: {:ok, list(map())} | {:error, any()}
  def get_system_kills(system_id, limit \\ 5) do
    ZKillClient.get_system_kills(system_id, limit)
  end
end
