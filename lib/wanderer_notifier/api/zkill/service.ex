defmodule WandererNotifier.Api.ZKill.Service do
  @moduledoc """
  Service module for interacting with the ZKillboard API.
  Provides functions to fetch killmail data and handle caching.
  """

  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Config.Cache
  alias WandererNotifier.Data.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Fetches recent kills from ZKillboard API.

  ## Parameters
    - limit: The number of recent kills to fetch (default: 10)

  ## Returns
    - {:ok, kills} on success where kills is a list of killmail data
    - {:error, reason} on failure
  """
  def get_recent_kills(limit \\ 10) do
    AppLogger.api_debug("Fetching recent kills from ZKill", limit: limit)

    case HttpClient.get("https://zkillboard.com/api/kills/limit/#{limit}/") do
      {:ok, response} ->
        case Jason.decode(response.body) do
          {:ok, kills} when is_list(kills) ->
            AppLogger.api_debug("Successfully fetched recent kills from ZKill",
              count: length(kills)
            )

            {:ok, kills}

          {:error, reason} ->
            AppLogger.api_error("Failed to parse ZKill recent kills response",
              error: inspect(reason)
            )

            {:error, :invalid_json}
        end

      {:error, reason} ->
        AppLogger.api_error("Failed to fetch recent kills from ZKill", error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Fetches kills for a specific system from ZKillboard API.

  ## Parameters
    - system_id: The ID of the system to fetch kills for
    - limit: The number of kills to fetch (default: 10)

  ## Returns
    - {:ok, kills} on success where kills is a list of killmail data
    - {:error, reason} on failure
  """
  def get_system_kills(system_id, limit \\ 10) do
    AppLogger.api_debug("Fetching system kills from ZKill", system_id: system_id, limit: limit)

    case WandererNotifier.Api.ZKill.Client.get_system_kills(system_id, limit) do
      {:ok, kills} when is_list(kills) ->
        AppLogger.api_debug("Successfully fetched system kills from ZKill",
          system_id: system_id,
          count: length(kills)
        )

        {:ok, kills}

      {:error, {:domain_error, :zkill, {:api_error, error_msg}}} = error ->
        AppLogger.api_warn("ZKill API error: #{error_msg}",
          system_id: system_id,
          error: error_msg
        )

        error

      {:error, reason} = error ->
        AppLogger.api_error("Failed to fetch system kills from ZKill",
          system_id: system_id,
          error: inspect(reason)
        )

        error
    end
  end

  @doc """
  Fetches a killmail by its ID, first checking the cache and then falling back to ZKillboard API.

  ## Parameters
    - killmail_id: The ID of the killmail to fetch

  ## Returns
    - {:ok, killmail} on success
    - {:error, reason} on failure
  """
  def get_killmail(killmail_id) do
    AppLogger.api_debug("Fetching killmail", killmail_id: killmail_id)

    case CacheRepo.get(killmail_id) do
      {:ok, killmail} ->
        AppLogger.api_debug("Found killmail in cache", killmail_id: killmail_id)
        {:ok, killmail}

      {:error, :not_found} ->
        fetch_killmail_from_zkill(killmail_id)

      {:error, reason} ->
        AppLogger.api_error("Failed to get killmail from cache",
          killmail_id: killmail_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp fetch_killmail_from_zkill(killmail_id) do
    case HttpClient.get("https://zkillboard.com/api/killID/#{killmail_id}/") do
      {:ok, response} ->
        process_zkill_response(response, killmail_id)

      {:error, reason} ->
        AppLogger.api_error("Failed to get killmail from ZKill",
          killmail_id: killmail_id,
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  defp process_zkill_response(response, killmail_id) do
    case Jason.decode(response.body) do
      {:ok, json_data} ->
        killmail = %{id: killmail_id, data: json_data}
        CacheRepo.set(killmail_id, killmail, Cache.static_info_cache_ttl())

        AppLogger.api_debug("Successfully fetched and cached killmail from ZKill",
          killmail_id: killmail_id
        )

        {:ok, killmail}

      {:error, reason} ->
        AppLogger.api_error("Failed to parse ZKill response",
          killmail_id: killmail_id,
          error: inspect(reason)
        )

        {:error, :invalid_json}
    end
  end
end
