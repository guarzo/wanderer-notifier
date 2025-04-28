defmodule WandererNotifier.ESI.Client do
  @moduledoc """
  Client for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides low-level functions for making requests to ESI endpoints.
  """
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  @base_url "https://esi.evetech.net/latest"

  @doc """
  Fetches a killmail from ESI.
  """
  def get_killmail(kill_id, hash, _opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    _label = "ESI.killmail-#{kill_id}"

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
  Fetches character info from ESI.
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
        # Add character_id to the response
        {:ok, Map.put(body, "character_id", character_id)}

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
  Fetches corporation info from ESI.
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
        # Add corporation_id to the response
        {:ok, Map.put(body, "corporation_id", corporation_id)}

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
  Fetches alliance info from ESI.
  """
  def get_alliance_info(alliance_id, _opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"
    _label = "ESI.alliance-#{alliance_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching alliance info", %{
      alliance_id: alliance_id,
      method: "get_alliance_info"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        # Add alliance_id to the response
        {:ok, Map.put(body, "alliance_id", alliance_id)}

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
  Fetches universe type info (e.g. ship type) from ESI.
  """
  def get_universe_type(ship_type_id, _opts \\ []) do
    url = "#{@base_url}/universe/types/#{ship_type_id}/"
    _label = "ESI.universe_type-#{ship_type_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching universe type", %{
      ship_type_id: ship_type_id,
      method: "get_universe_type"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI universe type error response", %{
          ship_type_id: ship_type_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI universe type failed", %{
          ship_type_id: ship_type_id,
          error: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc """
  Searches for inventory types using the ESI /search/ endpoint.
  Returns a map with "inventory_type" mapping to a list of type IDs.
  """
  def search_inventory_type(query, strict) do
    query_params = %{
      "categories" => "inventory_type",
      "search" => query,
      "strict" => to_string(strict)
    }

    url = "#{@base_url}/search/?#{URI.encode_query(query_params)}"
    _label = "ESI.search-#{query}"

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
  Fetches solar system info from ESI.
  """
  def get_solar_system(system_id, _opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/"
    _label = "ESI.solar_system-#{system_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching solar system", %{
      system_id: system_id,
      method: "get_solar_system"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        AppLogger.api_warn("ESI solar system not found", %{
          system_id: system_id,
          status_code: 404,
          method: "get_solar_system"
        })

        {:error, :not_found}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI solar system error response", %{
          system_id: system_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI failed to fetch solar system", %{
          system_id: system_id,
          error: inspect(reason),
          method: "get_solar_system"
        })

        {:error, reason}
    end
  end

  @doc """
  Gets kills for a specific system.
  """
  def get_system_kills(system_id, limit \\ 50, _opts \\ []) do
    url = "#{@base_url}/universe/system_kills/?datasource=tranquility"
    _label = "ESI.system_kills-#{system_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching system kills", %{
      system_id: system_id,
      method: "get_system_kills"
    })

    case HttpClient.get(url, headers) do
      {:ok, %{status_code: status, body: body}} when status in 200..299 ->
        filtered_kills =
          body
          |> Enum.filter(fn kill -> kill["system_id"] == system_id end)
          |> Enum.take(limit)

        {:ok, filtered_kills}

      {:ok, %{status_code: status}} ->
        AppLogger.api_error("ESI system kills error response", %{
          system_id: system_id,
          status: status
        })

        {:error, {:http_error, status}}

      {:error, reason} ->
        AppLogger.api_error("ESI system kills failed", %{
          system_id: system_id,
          error: inspect(reason),
          method: "get_system_kills"
        })

        {:error, reason}
    end
  end

  # Default HTTP headers for ESI requests
  defp default_headers do
    [
      {"Accept", "application/json"},
      {"User-Agent", @user_agent}
    ]
  end
end
