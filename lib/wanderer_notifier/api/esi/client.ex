defmodule WandererNotifier.Api.ESI.Client do
  @moduledoc """
  Client for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides low-level functions for making requests to ESI endpoints.
  """
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  @base_url "https://esi.evetech.net/latest"

  @doc """
  Fetches a killmail from ESI.
  """
  def get_killmail(kill_id, hash, opts \\ []) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    label = "ESI.killmail-#{kill_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching killmail", %{
      kill_id: kill_id,
      hash: hash,
      method: "get_killmail"
    })

    HttpClient.get(url, headers, Keyword.merge([label: label], opts))
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.killmail")
  end

  @doc """
  Fetches character info from ESI.
  """
  def get_character_info(character_id, opts \\ []) do
    url = "#{@base_url}/characters/#{character_id}/"
    label = "ESI.character-#{character_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching character info", %{
      character_id: character_id,
      method: "get_character_info"
    })

    HttpClient.get(url, headers, Keyword.merge([label: label], opts))
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.character")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "character_id", character_id)}
      error -> error
    end
  end

  @doc """
  Fetches corporation info from ESI.
  """
  def get_corporation_info(corporation_id, opts \\ []) do
    url = "#{@base_url}/corporations/#{corporation_id}/"
    label = "ESI.corporation-#{corporation_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching corporation info", %{
      corporation_id: corporation_id,
      method: "get_corporation_info"
    })

    HttpClient.get(url, headers, Keyword.merge([label: label], opts))
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.corporation")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "corporation_id", corporation_id)}
      error -> error
    end
  end

  @doc """
  Fetches alliance info from ESI.
  """
  def get_alliance_info(alliance_id, opts \\ []) do
    url = "#{@base_url}/alliances/#{alliance_id}/"
    label = "ESI.alliance-#{alliance_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching alliance info", %{
      alliance_id: alliance_id,
      method: "get_alliance_info"
    })

    HttpClient.get(url, headers, Keyword.merge([label: label], opts))
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.alliance")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "alliance_id", alliance_id)}
      error -> error
    end
  end

  @doc """
  Fetches universe type info (e.g. ship type) from ESI.
  """
  def get_universe_type(ship_type_id, opts \\ []) do
    url = "#{@base_url}/universe/types/#{ship_type_id}/"
    label = "ESI.universe_type-#{ship_type_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching universe type", %{
      ship_type_id: ship_type_id,
      method: "get_universe_type"
    })

    HttpClient.get(url, headers, Keyword.merge([label: label], opts))
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.universe_type")
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
    label = "ESI.search-#{query}"

    headers = default_headers()

    AppLogger.api_debug("ESI searching inventory type", %{
      query: query,
      strict: strict,
      method: "search_inventory_type"
    })

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.search")
  end

  @doc """
  Fetches solar system info from ESI.
  """
  def get_solar_system(system_id, opts \\ []) do
    url = "#{@base_url}/universe/systems/#{system_id}/"
    label = "ESI.solar_system-#{system_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching solar system", %{
      system_id: system_id,
      method: "get_solar_system"
    })

    result = HttpClient.get(url, headers, Keyword.merge([label: label], opts))

    case result do
      {:ok, %{status: 404}} ->
        AppLogger.api_warn("ESI solar system not found", %{
          system_id: system_id,
          status_code: 404,
          method: "get_solar_system"
        })

        {:error, :not_found}

      {:error, error} ->
        AppLogger.api_error("ESI failed to fetch solar system", %{
          system_id: system_id,
          error: inspect(error),
          method: "get_solar_system"
        })

        {:error, error}

      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      response ->
        ErrorHandler.handle_http_response(response, domain: :esi, tag: "ESI.solar_system")
    end
  end

  @doc """
  Fetches region info from ESI.
  """
  def get_region(region_id) do
    url = "#{@base_url}/universe/regions/#{region_id}/"
    label = "ESI.region-#{region_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching region", %{
      region_id: region_id,
      method: "get_region"
    })

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.region")
  end

  @doc """
  Fetches constellation info from ESI.
  """
  def get_constellation(constellation_id) do
    url = "#{@base_url}/universe/constellations/#{constellation_id}/"
    label = "ESI.constellation-#{constellation_id}"

    headers = default_headers()

    AppLogger.api_debug("ESI fetching constellation", %{
      constellation_id: constellation_id,
      method: "get_constellation"
    })

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.constellation")
  end

  @doc """
  Gets recent kills for a specific solar system.

  ## Parameters
    - system_id: The ID of the solar system
    - limit: Maximum number of kills to return

  ## Returns
    - {:ok, list} on success
    - {:error, term} on failure
  """
  def get_system_kills(system_id, limit) when is_integer(system_id) and is_integer(limit) do
    # ESI doesn't have a direct endpoint for system kills
    # We'll return an empty list as this is actually handled by ZKill
    AppLogger.api_debug("ESI get_system_kills not implemented", %{
      system_id: system_id,
      limit: limit,
      note: "Functionality handled by ZKill"
    })

    {:ok, []}
  end

  defp default_headers do
    [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]
  end
end
