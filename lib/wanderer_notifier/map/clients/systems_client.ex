defmodule WandererNotifier.Map.Clients.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  """

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.{Config, Cache}
  alias Cache.{Keys, CachexImpl}
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger

  @type reason :: term()
  @type update_result :: {:ok, [MapSystem.t()], [MapSystem.t()]} | {:error, reason()}

  @doc """
  Fetch, decode, process, and cache systems.

  Returns:
    - `{:ok, new_systems, all_systems}` on success
    - `{:error, reason}` on failure and no cached data
  """
  @spec update_systems(opts :: Keyword.t()) :: update_result()
  def update_systems(opts \\ []) do
    url = systems_url()
    headers = auth_header()

    result =
      with {:ok, %{status_code: 200, body: body}} <- HttpClient.get(url, headers),
           {:ok, decoded} <- decode_body(body),
           systems_list when is_list(systems_list) <- extract_systems(decoded),
           structs <- to_structs(systems_list),
           filtered <- filter_systems(structs) do
        process_new_systems(filtered, opts)
      end

    handle_update_result(result)
  end

  # Result handling functions
  defp handle_update_result({:ok, _new, _all} = result), do: result

  defp handle_update_result({:ok, %{status_code: status, body: body}}),
    do: log_http_error(status, body)

  defp handle_update_result({:error, :no_systems}), do: fallback_to_cached_systems(:no_systems)

  defp handle_update_result({:error, :json_decode_error}) do
    Logger.api_error("SystemsClient JSON decode failed", [])
    fallback_to_cached_systems(:json_decode_error)
  end

  defp handle_update_result({:error, reason}) do
    Logger.api_error("SystemsClient unexpected error", reason: inspect(reason))
    fallback_to_cached_systems(reason)
  end

  defp handle_update_result(_), do: fallback_to_cached_systems(:unexpected_error)

  ### — Helpers for URL & Headers

  defp systems_url do
    "#{Config.base_map_url()}/api/maps/#{Config.map_slug()}/systems"
  end

  defp auth_header do
    [{"Authorization", "Bearer #{Config.map_token()}"}]
  end

  ### — JSON Decoding

  @spec decode_body(body :: String.t() | map()) ::
          {:ok, map()} | {:error, :json_decode_error | :invalid_body}
  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:error, :json_decode_error}
    end
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}
  defp decode_body(_), do: {:error, :invalid_body}

  ### — Extracting the systems list

  @spec extract_systems(data :: map()) :: [map()] | {:error, :no_systems}
  defp extract_systems(%{"data" => %{"systems" => sys}}), do: sys
  defp extract_systems(%{"systems" => sys}), do: sys
  defp extract_systems(_), do: {:error, :no_systems}

  defp to_structs(maps), do: Enum.map(maps, &MapSystem.new/1)

  ### — K-space filtering

  defp filter_systems(systems) do
    if Config.track_kspace_systems?(),
      do: systems,
      else: Enum.reject(systems, &kspace?/1)
  end

  defp kspace?(%MapSystem{system_class: cls}), do: cls in ["K", "HS", "LS", "NS"]
  defp kspace?(map), do: Map.get(map, :system_class) in ["K", "HS", "LS", "NS"]

  ### — Processing & Caching

  @spec process_new_systems([MapSystem.t()], Keyword.t()) :: update_result()
  defp process_new_systems(systems, opts) do
    cached =
      case CachexImpl.get(Keys.map_systems()) do
        {:ok, val} when is_list(val) -> val
        _ -> []
      end

    new_systems = find_new(cached, systems)
    maybe_notify(new_systems, opts)
    :ok = CachexImpl.put(Keys.map_systems(), systems)
    {:ok, new_systems, systems}
  rescue
    e ->
      Logger.api_error("SystemsClient processing error", error: Exception.message(e))
      {:error, :processing_error}
  end

  defp find_new(cached, systems) do
    cached
    |> Enum.map(& &1.solar_system_id)
    |> MapSet.new()
    |> then(fn seen_ids ->
      Enum.reject(systems, &(&1.solar_system_id in seen_ids))
    end)
  end

  defp maybe_notify(new_systems, opts) do
    if !Keyword.get(opts, :suppress_notifications, false) do
      Enum.each(new_systems, &notify/1)
    end
  end

  defp fallback_to_cached_systems(reason) do
    case CachexImpl.get(Keys.map_systems()) do
      {:ok, sys} when is_list(sys) and sys != [] -> {:ok, [], sys}
      _ -> {:error, reason}
    end
  end

  defp log_http_error(status, body) do
    Logger.api_error("SystemsClient HTTP error",
      status: status,
      body_preview: String.slice(to_string(body), 0, 200)
    )

    fallback_to_cached_systems({:http_error, status})
  end

  ### — Notification

  @spec notify(MapSystem.t()) :: :ok
  defp notify(system) do
    system
    |> enrich_system()
    |> ensure_struct()
    |> maybe_send_notification()
  end

  defp enrich_system(system) do
    case WandererNotifier.Map.SystemStaticInfo.enrich_system(system) do
      {:ok, enriched} -> enriched
      _ -> system
    end
  end

  defp ensure_struct(data) do
    if is_struct(data, MapSystem), do: data, else: MapSystem.new(data)
  end

  defp maybe_send_notification(system) do
    if WandererNotifier.Notifications.Determiner.System.should_notify?(
         system.solar_system_id,
         system
       ) do
      WandererNotifier.Notifiers.Discord.Notifier.send_new_system_notification(system)
    end

    :ok
  rescue
    e ->
      Logger.api_error("SystemsClient notification failed",
        error: Exception.message(e),
        system: inspect(system)
      )

      :error
  end
end
