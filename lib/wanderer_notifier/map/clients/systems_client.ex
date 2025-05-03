defmodule WandererNotifier.Map.Clients.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
    "data": [
    {
      "id": "e93be5e8-27ac-46c8-8e06-48c497338710",
      "name": "J123111",
      "status": 0,
      "tag": null,
      "visible": true,
      "description": null,
      "labels": "{\"customLabel\":\"\",\"labels\":[]}",
      "inserted_at": "2025-01-01T17:02:15.911255Z",
      "updated_at": "2025-05-02T00:11:31.721497Z",
      "locked": false,
      "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
      "solar_system_id": 31000133,
      "custom_name": null,
      "position_x": 360,
      "position_y": 0,
      "temporary_name": null,
      "original_name": "J123111"
    },
    {
      "id": "d04017f7-8ee3-4016-965a-f07bd1116fe3",
      "name": "12",
      "status": 0,
      "tag": null,
      "visible": true,
      "description": null,
      "labels": "{\"customLabel\":\"\",\"labels\":[]}",
      "inserted_at": "2025-02-03T05:08:52.973940Z",
      "updated_at": "2025-05-02T16:09:04.730231Z",
      "locked": false,
      "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
      "solar_system_id": 31000611,
      "custom_name": null,
      "position_x": 476,
      "position_y": 1275,
      "temporary_name": "12",
      "original_name": "J115734"
    },
  ]
  }
  """

  # alias the HTTPoison-based implementation under the name HttpClient
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient

  alias WandererNotifier.{
    Config,
    Cache.Keys,
    Cache.CachexImpl,
    Map.MapSystem,
    Logger.Logger
  }

  @doc """
  Fetch, decode, process, notify (unless suppressed), and cache systems.

  Returns:
    - {:ok, new_systems, all_systems}
    - {:error, reason}
  """
  def update_systems(opts \\ []) do
    fetch()
    |> parse()
    |> to_structs()
    |> filter_systems()
    |> detect_and_notify(opts)
    |> cache_and_return()
  rescue
    e -> handle_failure(e)
  end

  # 1) Fetch raw response
  defp fetch do
    url     = "#{Config.base_map_url()}/api/map/systems?slug=#{Config.map_slug()}"
    headers = [{"Authorization", "Bearer #{Config.map_token()}"}]
    HttpClient.get(url, headers)
  end

  # 2) Parse HTTP result into a flat list of maps
  defp parse({:ok, %{body: %{"data" => data}}}),    do: {:ok, data}
  defp parse({:ok, %{body: %{"systems" => data}}}), do: {:ok, data}
  defp parse({:ok, %{body: body}}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => d}} when is_list(d) -> {:ok, d}
      {:ok, l} when is_list(l)              -> {:ok, l}
      err                                   -> err
    end
  end
  defp parse(err) do
    Logger.api_error("Unexpected HTTP result", result: inspect(err))
    {:error, :http_error}
  end

  # 3) Map raw maps into our MapSystem structs
  defp to_structs({:ok, data}) do
    data
    |> Enum.map(&MapSystem.new/1)
    |> then(&{:ok, &1})
  rescue
    e ->
      Logger.api_error("Failed to build structs", error: Exception.message(e))
      {:error, :struct_build_failed}
  end
  defp to_structs(err), do: err

  # 4) Optionally filter out K-space
  defp filter_systems({:ok, systems}) do
    filtered =
      if Config.track_kspace_systems?() do
        systems
      else
        Enum.reject(systems, &kspace?/1)
      end

    {:ok, filtered}
  end
  defp filter_systems(err), do: err

  # 5) Compare against cache, send notifications for new ones (unless suppressed)
  defp detect_and_notify({:ok, systems}, opts) do
    {:ok, cached_systems} = CachexImpl.get(Keys.map_systems()) |> unwrap_cache()

    # build a MapSet of cached IDs
    cached_ids =
      MapSet.new(cached_systems, fn sys ->
        sys.solar_system_id
      end)

    new_systems =
      Enum.reject(systems, fn sys ->
        sys.solar_system_id in cached_ids
      end)

    unless Keyword.get(opts, :suppress_notifications, false) do
      Enum.each(new_systems, &notify/1)
    end

    {:ok, new_systems, systems}
  end
  defp detect_and_notify(err, _), do: err

  # 6) Write to cache and return successful tuple
  defp cache_and_return({:ok, new, all}) do
    CachexImpl.put(Keys.map_systems(), all)
    {:ok, new, all}
  end
  defp cache_and_return(err), do: err

  # Notification helper
  defp notify(system) do
    enriched =
      case WandererNotifier.Map.SystemStaticInfo.enrich_system(system) do
        {:ok, e} -> e
        _        -> system
      end

    WandererNotifier.Notifiers.Discord.Notifier.send_new_system_notification(enriched)
  rescue
    e ->
      Logger.api_error("Notification failed",
        error: Exception.message(e),
        system: inspect(system)
      )
  end

  # Simple K-space detector (works whether system is a struct or map)
  defp kspace?(system) do
    Map.get(system, :system_class) in ["K", "HS", "LS", "NS"]
  end

  # Unified fallback on any crash
  defp handle_failure(error) do
    Logger.api_error("SystemsClient failed", error: Exception.message(error))

    case CachexImpl.get(Keys.map_systems()) do
      {:ok, systems} -> {:ok, [], systems}
      _              -> {:ok, [], []}
    end
  end

  # Cachex returns {:ok, val} or {:error, _}, so normalize
  defp unwrap_cache({:ok, val}), do: {:ok, val}
  defp unwrap_cache(_),        do: {:ok, []}
end
