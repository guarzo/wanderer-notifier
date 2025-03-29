defmodule WandererNotifier.Api.ESI.Client do
  @moduledoc """
  Client for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides low-level functions for making requests to ESI endpoints.
  """
  require Logger
  alias WandererNotifier.Logger, as: AppLogger
  alias WandererNotifier.Api.Http.Client, as: HttpClient
  alias WandererNotifier.Api.Http.ErrorHandler

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  @base_url "https://esi.evetech.net/latest"

  @doc """
  Fetches a killmail from ESI.
  """
  def get_killmail(kill_id, hash) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    label = "ESI.killmail-#{kill_id}"

    headers = default_headers()

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.killmail")
  end

  @doc """
  Fetches character info from ESI.
  """
  def get_character_info(character_id) do
    url = "#{@base_url}/characters/#{character_id}/"
    label = "ESI.character-#{character_id}"

    headers = default_headers()

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.character")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "character_id", character_id)}
      error -> error
    end
  end

  @doc """
  Fetches corporation info from ESI.
  """
  def get_corporation_info(corporation_id) do
    url = "#{@base_url}/corporations/#{corporation_id}/"
    label = "ESI.corporation-#{corporation_id}"

    headers = default_headers()

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.corporation")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "corporation_id", corporation_id)}
      error -> error
    end
  end

  @doc """
  Fetches alliance info from ESI.
  """
  def get_alliance_info(alliance_id) do
    url = "#{@base_url}/alliances/#{alliance_id}/"
    label = "ESI.alliance-#{alliance_id}"

    headers = default_headers()

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.alliance")
    |> case do
      {:ok, data} -> {:ok, Map.put(data, "alliance_id", alliance_id)}
      error -> error
    end
  end

  @doc """
  Fetches universe type info (e.g. ship type) from ESI.
  """
  def get_universe_type(ship_type_id) do
    url = "#{@base_url}/universe/types/#{ship_type_id}/"
    label = "ESI.universe_type-#{ship_type_id}"

    headers = default_headers()

    HttpClient.get(url, headers, label: label)
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

    AppLogger.api_debug("[ESI] Searching inventory_type with query #{query} (strict=#{strict})")

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.search")
  end

  @doc """
  Fetches solar system info from ESI.
  """
  def get_solar_system(system_id) do
    url = "#{@base_url}/universe/systems/#{system_id}/"
    label = "ESI.solar_system-#{system_id}"

    headers = default_headers()

    AppLogger.api_debug("[ESI] Fetching solar system #{system_id}")

    result = HttpClient.get(url, headers, label: label)

    case result do
      {:ok, %{status: 404}} ->
        AppLogger.api_warn("[ESI] Solar system ID #{system_id} not found (404)")
        {:error, :not_found}

      {:error, error} ->
        AppLogger.api_error("[ESI] Failed to fetch solar system #{system_id}: #{inspect(error)}")
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

    AppLogger.api_debug("[ESI] Fetching region #{region_id}")

    HttpClient.get(url, headers, label: label)
    |> ErrorHandler.handle_http_response(domain: :esi, tag: "ESI.region")
  end

  defp default_headers do
    [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]
  end
end
