defmodule WandererNotifier.Api.ESI.Client do
  @moduledoc """
  Client for interacting with EVE Online's ESI (Swagger Interface) API.
  Provides low-level functions for making requests to ESI endpoints.
  """
  require Logger
  alias WandererNotifier.Api.Http.Client, as: HttpClient

  @user_agent "my-corp-killbot/1.0 (contact me@example.com)"
  @base_url "https://esi.evetech.net/latest"

  @doc """
  Fetches a killmail from ESI.
  """
  def get_killmail(kill_id, hash) do
    url = "#{@base_url}/killmails/#{kill_id}/#{hash}/"
    label = "ESI.killmail-#{kill_id}"

    headers = default_headers()

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        HttpClient.handle_response(response)

      error ->
        error
    end
  end

  @doc """
  Fetches character info from ESI.
  """
  def get_character_info(eve_id) do
    url = "#{@base_url}/characters/#{eve_id}/"
    label = "ESI.character-#{eve_id}"

    headers = default_headers()

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        case HttpClient.handle_response(response) do
          {:ok, data} -> {:ok, Map.put(data, "eve_id", eve_id)}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Fetches corporation info from ESI.
  """
  def get_corporation_info(eve_id) do
    url = "#{@base_url}/corporations/#{eve_id}/"
    label = "ESI.corporation-#{eve_id}"

    headers = default_headers()

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        case HttpClient.handle_response(response) do
          {:ok, data} -> {:ok, Map.put(data, "eve_id", eve_id)}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Fetches alliance info from ESI.
  """
  def get_alliance_info(eve_id) do
    url = "#{@base_url}/alliances/#{eve_id}/"
    label = "ESI.alliance-#{eve_id}"

    headers = default_headers()

    case HttpClient.get(url, headers, [label: label]) do
      {:ok, _} = response ->
        case HttpClient.handle_response(response) do
          {:ok, data} -> {:ok, Map.put(data, "eve_id", eve_id)}
          error -> error
        end

      error ->
        error
    end
  end

  @doc """
  Fetches universe type info (e.g. ship type) from ESI.
  """
  def get_universe_type(ship_type_id) do
    url = "#{@base_url}/universe/types/#{ship_type_id}/"
    label = "ESI.universe_type-#{ship_type_id}"

    headers = default_headers()

    HttpClient.get(url, headers, [label: label])
    |> HttpClient.handle_response()
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

    Logger.debug("[ESI] Searching inventory_type with query #{query} (strict=#{strict})")

    HttpClient.get(url, headers, [label: label])
    |> HttpClient.handle_response()
  end

  @doc """
  Fetches solar system info from ESI.
  """
  def get_solar_system(system_id) do
    url = "#{@base_url}/universe/systems/#{system_id}/"
    label = "ESI.solar_system-#{system_id}"

    headers = default_headers()

    Logger.debug("[ESI] Fetching solar system #{system_id}")

    HttpClient.get(url, headers, [label: label])
    |> HttpClient.handle_response()
  end

  @doc """
  Fetches region info from ESI.
  """
  def get_region(region_id) do
    url = "#{@base_url}/universe/regions/#{region_id}/"
    label = "ESI.region-#{region_id}"

    headers = default_headers()

    Logger.debug("[ESI] Fetching region #{region_id}")

    HttpClient.get(url, headers, [label: label])
    |> HttpClient.handle_response()
  end

  defp default_headers do
    [
      {"User-Agent", @user_agent},
      {"Accept", "application/json"}
    ]
  end
end
