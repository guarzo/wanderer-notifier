defmodule ChainKills.Map.Systems do
  @moduledoc """
  System-related API calls to the Wanderer map, including static info caching.
  """

  require Logger
  alias ChainKills.Http.Client, as: HttpClient
  alias ChainKills.Cache.Repository, as: CacheRepo

  @static_info_cache_ttl 86_400
  @systems_cache_ttl 300

  @doc """
  Retrieves wormhole systems from the map API, caches them under "map:systems".
  """
  def update_systems do
    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body}        <- fetch_systems_body(systems_url),
         {:ok, json}        <- decode_json(body),
         {:ok, new_systems} <- process_systems(json) do
      CacheRepo.set("map:systems", new_systems, @systems_cache_ttl)
      Logger.info("[update_systems] fetched #{length(new_systems)} wormhole systems")
      {:ok, new_systems}
    else
      {:error, msg} = err ->
        Logger.error("[update_systems] error: #{inspect(msg)}")
        err
    end
  end


  defp build_systems_url do
    case validate_map_env() do
      {:ok, map_url, map_name} ->
        {:ok, "#{map_url}/api/map/systems?slug=#{map_name}"}

      {:error, _} = err ->
        err
    end
  end

  defp fetch_get_body(url, headers) do
    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status_code: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_systems_body(url) do
    map_token = Application.get_env(:chainkills, :map_token)
    headers =
      if map_token do
        [{"Authorization", "Bearer " <> map_token}]
      else
        []
      end

    fetch_get_body(url, headers)
  end

  defp decode_json(raw) do
    case Jason.decode(raw) do
      {:ok, data} -> {:ok, data}
      error -> {:error, error}
    end
  end

  defp process_systems(%{"Data" => systems_data}) when is_list(systems_data) do
    map_url = Application.get_env(:chainkills, :map_url)

    new_systems =
      systems_data
      |> Enum.map(&fetch_wormhole_system(&1, map_url))
      |> Enum.filter(& &1)

    Logger.info("Fetched #{length(systems_data)} systems from map (#{length(new_systems)} are wormholes)")
    {:ok, new_systems}
  end

  defp process_systems(_), do: {:ok, []}

  defp fetch_wormhole_system(item, map_url) do
    solar_system_id = item["SolarSystemID"]
    static_info_url = "#{map_url}/api/common/system-static-info?id=#{solar_system_id}"

    case get_or_fetch_system_static_info(static_info_url) do
      {:ok, ssi} ->
        name = get_in(ssi, ["Data", "SolarSystemName"]) || ""
        if String.starts_with?(name, "J") do
          %{system_id: solar_system_id, alias: item["TemporaryName"]}
        else
          nil
        end

      {:error, err} ->
        Logger.error("Error fetching static info for system #{solar_system_id}: #{inspect(err)}")
        nil
    end
  end

  defp get_or_fetch_system_static_info(url) do
    case CacheRepo.get(url) do
      nil -> fetch_and_cache_system_info(url)
      cached -> decode_cached_body(cached)
    end
  end

  defp fetch_and_cache_system_info(url) do
    case HttpClient.request("GET", url) do
      {:ok, %{status_code: 200, body: body}} ->
        :ok = CacheRepo.set(url, body, @static_info_cache_ttl)
        decode_cached_body(body)

      {:ok, %{status_code: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_cached_body(cached) do
    case Jason.decode(cached) do
      {:ok, ssi} -> {:ok, ssi}
      error -> {:error, error}
    end
  end

  defp validate_map_env do
    map_url  = Application.get_env(:chainkills, :map_url)
    map_name = Application.get_env(:chainkills, :map_name)

    if map_url in [nil, ""] or map_name in [nil, ""] do
      {:error, "map_url or map_name not configured"}
    else
      {:ok, map_url, map_name}
    end
  end
end
