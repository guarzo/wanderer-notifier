defmodule WandererNotifier.Map.Clients.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.

  curl -X 'GET' \
  'https://<map url>/api/maps/<map name>/systems' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer <token>' \
  Uses structured data types and consistent parsing to simplify the logic.
  {
  "data": {
    "connections": [
      {
        "id": "25b7e272-a7dd-46cf-bcb6-87a39f95fcaa",
        "type": 0,
        "inserted_at": "2025-05-11T21:15:41.123991Z",
        "updated_at": "2025-05-11T21:15:41.123991Z",
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
        "mass_status": 0,
        "ship_size_type": 2,
        "solar_system_source": 31002573,
        "solar_system_target": 30002034,
        "time_status": 0,
        "wormhole_type": null
      },
      {
        "id": "cc786a43-6026-4a35-8883-ee9e10efd4e6",
        "type": 0,
        "inserted_at": "2025-05-11T21:43:22.794583Z",
        "updated_at": "2025-05-11T21:43:22.794583Z",
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
        "mass_status": 0,
        "ship_size_type": 2,
        "solar_system_source": 31001300,
        "solar_system_target": 31000746,
        "time_status": 0,
        "wormhole_type": null
      },
    ],
    "systems": [
      {
        "id": "95737c62-207f-4e30-b83b-30229fe07459",
        "name": "2",
        "status": 0,
        "tag": "6",
        "visible": true,
        "description": null,
        "labels": "{\"customLabel\":\"\",\"labels\":[]}",
        "inserted_at": "2025-01-02T03:05:37.898713Z",
        "updated_at": "2025-05-11T22:21:31.147024Z",
        "locked": false,
        "solar_system_id": 31000396,
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
        "custom_name": null,
        "position_x": 238,
        "position_y": 1632,
        "temporary_name": "2",
        "original_name": "J151047"
      },
      {
        "id": "d4a42bc4-915c-441b-b899-d7de027d97f3",
        "name": "31A",
        "status": 0,
        "tag": null,
        "visible": true,
        "description": null,
        "labels": "{\"customLabel\":\"\",\"labels\":[]}",
        "inserted_at": "2025-01-11T05:28:20.206505Z",
        "updated_at": "2025-05-11T20:41:01.502548Z",
        "locked": false,
        "solar_system_id": 30002406,
        "map_id": "678c43cf-f71f-4e14-932d-0545465cdff0",
        "custom_name": null,
        "position_x": 714,
        "position_y": 1989,
        "temporary_name": "31A",
        "original_name": "Hedaleolfarber"
      },
    ]
  }
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
    base_url = Config.base_map_url()
    slug = Config.map_slug()
    url = "#{base_url}/api/maps/#{slug}/systems"
    headers = [{"Authorization", "Bearer #{Config.map_token()}"}]
    Logger.api_debug("[SystemsClient] Fetching systems", url: url)
    HttpClient.get(url, headers)
  end

  # 2) Parse HTTP result into a flat list of maps
  defp parse({:ok, %{status_code: 200, body: %{"data" => %{"systems" => systems}}}})
       when is_list(systems) do
    Logger.api_info("[SystemsClient] Found #{length(systems)} systems in the response")
    {:ok, systems}
  end

  # Handle the case where systems is under data directly
  defp parse({:ok, %{status_code: 200, body: %{"data" => systems}}}) when is_list(systems) do
    Logger.api_info("[SystemsClient] Found #{length(systems)} systems in the response data")
    {:ok, systems}
  end

  # Handle truncated responses - if body is a list directly
  defp parse({:ok, %{status_code: 200, body: data}}) when is_list(data) do
    Logger.api_info(
      "[SystemsClient] Response is a direct list instead of nested data structure - handling"
    )

    {:ok, data}
  end

  defp parse({:ok, %{status_code: 200, body: body}}) when is_binary(body) do
    Logger.api_debug("[SystemsClient] Raw JSON body received, attempting to parse",
      preview: String.slice(body, 0, 100)
    )

    case Jason.decode(body) do
      {:ok, %{"data" => %{"systems" => systems}}} when is_list(systems) ->
        Logger.api_info(
          "[SystemsClient] Successfully parsed systems from JSON, found #{length(systems)} systems"
        )

        {:ok, systems}

      {:ok, %{"data" => %{"connections" => connections, "systems" => systems}}}
      when is_list(systems) ->
        Logger.api_info(
          "[SystemsClient] Successfully parsed #{length(systems)} systems and #{length(connections)} connections from JSON"
        )

        {:ok, systems}

      {:ok, %{"data" => %{"connections" => _connections}}} ->
        # This is the new format but we only got connections, not systems
        Logger.api_info("[SystemsClient] Received connections data but no systems")
        # Return previous data from cache to avoid disruption
        case CachexImpl.get(Keys.map_systems()) do
          {:ok, systems} when is_list(systems) and length(systems) > 0 ->
            Logger.api_info("Using #{length(systems)} systems from cache for continuity")
            {:ok, [], systems}

          _ ->
            {:error, :missing_systems_data}
        end

      {:ok, %{"data" => d}} when is_list(d) ->
        {:ok, d}

      {:ok, l} when is_list(l) ->
        {:ok, l}

      {:ok, other} ->
        Logger.api_error("[SystemsClient] Unexpected JSON response format",
          response: inspect(other, pretty: true, limit: 500)
        )

        # Fall back to cache if available
        case CachexImpl.get(Keys.map_systems()) do
          {:ok, systems} when is_list(systems) and length(systems) > 0 ->
            Logger.api_info(
              "Using #{length(systems)} cached systems after invalid response format"
            )

            {:ok, [], systems}

          _ ->
            {:error, :unexpected_format}
        end

      err ->
        Logger.api_error("[SystemsClient] JSON parsing error", error: inspect(err))
        {:error, :json_parse_error}
    end
  end

  defp parse({:ok, %{status_code: 500, body: body}}) do
    Logger.api_error("[SystemsClient] Server error (500) from map API", body: inspect(body))
    # Return previous data from cache to avoid disruption
    case CachexImpl.get(Keys.map_systems()) do
      {:ok, systems} when is_list(systems) and length(systems) > 0 ->
        Logger.api_info("Recovered #{length(systems)} systems from cache after server error")
        # Return empty new systems but reuse cached data
        {:ok, [], systems}

      _ ->
        {:error, :server_error}
    end
  end

  defp parse({:ok, %{status_code: status, body: body}}) do
    Logger.api_error("[SystemsClient] HTTP error from map API",
      status: status,
      body: inspect(body)
    )

    # Try to recover using cache
    case CachexImpl.get(Keys.map_systems()) do
      {:ok, systems} when is_list(systems) and length(systems) > 0 ->
        Logger.api_info("Using #{length(systems)} cached systems after HTTP error")
        {:ok, [], systems}

      _ ->
        {:error, {:http_error, %{status_code: status, body: body}}}
    end
  end

  defp parse(err) do
    Logger.api_error("[SystemsClient] Unexpected HTTP result", result: inspect(err))
    # Try to recover using cache
    case CachexImpl.get(Keys.map_systems()) do
      {:ok, systems} when is_list(systems) and length(systems) > 0 ->
        Logger.api_info("Using #{length(systems)} cached systems after unexpected error")
        {:ok, [], systems}

      _ ->
        {:error, :http_error}
    end
  end

  # 3) Map raw maps into our MapSystem structs
  defp to_structs({:ok, data}) when is_list(data) do
    data
    |> Enum.map(&MapSystem.new/1)
    |> then(&{:ok, &1})
  rescue
    e ->
      Logger.api_error("[SystemsClient] Failed to build structs", error: Exception.message(e))
      # Try to recover using cache
      case CachexImpl.get(Keys.map_systems()) do
        {:ok, systems} when is_list(systems) and length(systems) > 0 ->
          Logger.api_info("Using #{length(systems)} cached systems after struct conversion error")
          {:ok, [], systems}

        _ ->
          {:error, :struct_build_failed}
      end
  end

  # Pass through pre-parsed fallback data from cache
  defp to_structs({:ok, [], systems}) when is_list(systems) do
    # Already processed systems from cache
    {:ok, [], systems}
  end

  defp to_structs(err), do: err

  # 4) Optionally filter out K-space
  defp filter_systems({:ok, filtered_systems, systems})
       when is_list(filtered_systems) and is_list(systems) do
    # Passthrough for the cache recovery case
    {:ok, filtered_systems, systems}
  end

  defp filter_systems({:ok, systems}) when is_list(systems) do
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
  defp detect_and_notify({:ok, filtered_systems, systems}, _opts)
       when is_list(filtered_systems) and is_list(systems) do
    # Passthrough for the cache recovery case
    {:ok, [], systems}
  end

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
        _ -> system
      end

    # Ensure enriched is a %MapSystem{} struct
    final_enriched =
      if is_struct(enriched, MapSystem) do
        enriched
      else
        Logger.api_warn(
          "[SystemsClient] Enriched system is not a struct, converting to %MapSystem{}",
          original: inspect(enriched)
        )

        MapSystem.new(enriched)
      end

    system_id = final_enriched.solar_system_id

    if WandererNotifier.Notifications.Determiner.System.should_notify?(system_id, final_enriched) do
      WandererNotifier.Notifiers.Discord.Notifier.send_new_system_notification(final_enriched)
    end
  rescue
    e ->
      Logger.api_error("[SystemsClient] Notification failed",
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
    Logger.api_error("[SystemsClient] SystemsClient failed", error: Exception.message(error))

    case CachexImpl.get(Keys.map_systems()) do
      {:ok, systems} -> {:ok, [], systems}
      _ -> {:ok, [], []}
    end
  end

  # Cachex returns {:ok, val} or {:error, _}, so normalize
  defp unwrap_cache({:ok, val}), do: {:ok, val}
  defp unwrap_cache(_), do: {:ok, []}
end
