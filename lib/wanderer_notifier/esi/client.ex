defmodule WandererNotifier.ESI.Client do
  @moduledoc """
  Client for interacting with the EVE Online ESI API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @base_url "https://esi.evetech.net/latest"
  @user_agent "WandererNotifier/1.0"

  @doc """
  Gets killmail information from ESI.
  """
  def get_killmail(kill_id, hash, _opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching killmail", %{
      kill_id: kill_id,
      hash: hash,
      method: "get_killmail"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        AppLogger.api_debug("ESI killmail response", %{
          kill_id: kill_id,
          status: status
        })

        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI killmail error response", %{
          kill_id: kill_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI killmail failed", %{
          kill_id: kill_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets character information from ESI.
  """
  def get_character_info(character_id, _opts \\ []) do
    url = "#{@base_url}/characters/#{character_id}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching character info", %{
      character_id: character_id,
      method: "get_character_info"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI character info error response", %{
          character_id: character_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI character info failed", %{
          character_id: character_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets corporation information from ESI.
  """
  def get_corporation_info(corporation_id, _opts \\ []) do
    url = "#{@base_url}/corporations/#{corporation_id}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching corporation info", %{
      corporation_id: corporation_id,
      method: "get_corporation_info"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI corporation info error response", %{
          corporation_id: corporation_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI corporation info failed", %{
          corporation_id: corporation_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets alliance information from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching alliance info", %{
      alliance_id: alliance_id,
      method: "get_alliance_info"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI alliance info error response", %{
          alliance_id: alliance_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI alliance info failed", %{
          alliance_id: alliance_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets type information from ESI.
  """
  def get_universe_type(type_id, _opts \\ []) do
    url = "#{@base_url}/universe/types/#{type_id}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching type info", %{
      type_id: type_id,
      method: "get_universe_type"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI type info error response", %{
          type_id: type_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI type info failed", %{
          type_id: type_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Searches for inventory types in ESI.
  """
  def search_inventory_type(query, strict \\ false) do
    query_params = %{
      "categories" => "inventory_type",
      "search" => query,
      "strict" => to_string(strict)
    }

    url = "#{@base_url}/search/?#{URI.encode_query(query_params)}"
    headers = default_headers()

    AppLogger.api_debug("ESI searching inventory type", %{
      query: query,
      strict: strict,
      method: "search_inventory_type"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI search error response", %{
          query: query,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI search failed", %{
          query: query,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets solar system information from ESI.
  """
  def get_solar_system(system_id, _opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching solar system", %{
      system_id: system_id,
      method: "get_solar_system"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI solar system error response", %{
          system_id: system_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI solar system failed", %{
          system_id: system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Gets system kill statistics from ESI.
  """
  def get_system_kills(system_id, limit \\ 5) do
    url = "#{@base_url}/universe/system_kills/"
    headers = default_headers()

    AppLogger.api_debug("ESI fetching system kills", %{
      system_id: system_id,
      limit: limit,
      method: "get_system_kills"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI system kills error response", %{
          system_id: system_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI system kills failed", %{
          system_id: system_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  # Private helper functions

  defp default_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent}
    ]
  end
end
