defmodule ChainKills.Map.Systems do
  @moduledoc """
  Retrieves and processes system data from the map API, filtering for wormhole systems.
  Only wormhole systems (where a system’s static info shows a non-empty "statics" list or
  the "type_description" starts with "Class") are returned.
  """

  require Logger
  alias ChainKills.Http.Client, as: HttpClient
  alias ChainKills.Cache.Repository, as: CacheRepo

  @systems_cache_ttl 10_000
  @static_info_cache_ttl 86_400

  def update_systems do
    Logger.info("[update_systems] Starting systems update")
    with {:ok, systems_url} <- build_systems_url(),
         {:ok, body}        <- fetch_get_body(systems_url),
         {:ok, json}        <- decode_json(body),
         {:ok, fresh_systems} <- process_systems(json)
    do
      if fresh_systems == [] do
        Logger.warning("[update_systems] Received empty system list. Retaining existing cache.")
      else
        # Store new wormhole systems under the "map:systems" key
        CacheRepo.set("map:systems", fresh_systems, @systems_cache_ttl)
      end

      {:ok, fresh_systems}
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
      err -> err
    end
  end

  defp fetch_get_body(url) do
    map_token = Application.get_env(:chainkills, :map_token)
    headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []
    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: status}} -> {:error, "Unexpected status: #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json(raw) do
    Jason.decode(raw)
  end

  defp process_systems(%{"data" => systems_data}) when is_list(systems_data) do
    wormhole_systems =
      systems_data
      |> Enum.map(&fetch_wormhole_system/1)
      |> Enum.filter(& &1)
    {:ok, wormhole_systems}
  end

  defp process_systems(_), do: {:ok, []}

  # Refactored to reduce cyclomatic complexity by extracting helpers.
  defp fetch_wormhole_system(item) do
    with system_id when is_binary(system_id) <- extract_system_id(item),
         map_url <- Application.get_env(:chainkills, :map_url),
         static_info_url = "#{map_url}/api/common//system-static-info?id=#{system_id}",
         {:ok, ssi} <- get_or_fetch_system_static_info(static_info_url),
         true <- qualifies_as_wormhole?(ssi)
    do
      %{
        system_id: system_id,
        alias: item["temporary_name"] || item["TemporaryName"]
      }
    else
      _ -> nil
    end
  end

  # Extract the system id from the item.
  defp extract_system_id(item) do
    case item["solar_system_id"] || item["SolarSystemID"] do
      nil -> nil
      id -> to_string(id)
    end
  end

  # Determines if the system qualifies as a wormhole system.
  defp qualifies_as_wormhole?(ssi) do
    type_description = get_in(ssi, ["data", "type_description"]) || ""
    statics = get_in(ssi, ["data", "statics"]) || []
    (length(statics) > 0) or String.starts_with?(type_description, "Class")
  end

  defp get_or_fetch_system_static_info(url) do
    case CacheRepo.get(url) do
      nil -> fetch_and_cache_system_info(url)
      cached -> Jason.decode(cached)
    end
  end

  defp fetch_and_cache_system_info(url) do
    map_token = Application.get_env(:chainkills, :map_token)
    headers = if map_token, do: [{"Authorization", "Bearer " <> map_token}], else: []
    case HttpClient.request("GET", url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        CacheRepo.set(url, body, @static_info_cache_ttl)
        Jason.decode(body)

      {:ok, %{status_code: status}} ->
        {:error, "Unexpected status: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_map_env do
    map_url = Application.get_env(:chainkills, :map_url)
    map_name = Application.get_env(:chainkills, :map_name)

    if map_url in [nil, ""] or map_name in [nil, ""] do
      {:error, "map_url or map_name not configured"}
    else
      {:ok, map_url, map_name}
    end
  end
end
