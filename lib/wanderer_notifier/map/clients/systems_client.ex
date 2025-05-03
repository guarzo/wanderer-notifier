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

  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.Config
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.CachexImpl, as: CacheRepo
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Updates the systems in the cache.

  If cached_systems is provided, it will also identify and notify about new systems.

  ## Parameters
    - cached_systems: Optional list of cached systems for comparison
    - opts: Optional keyword list with options

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil, opts \\ []) do
    suppress_notifications = Keyword.get(opts, :suppress_notifications, false)
    # Get cached systems if none provided
    cached_systems =
      case cached_systems do
        nil ->
          case CacheRepo.get(CacheKeys.map_systems()) do
            {:ok, systems} -> systems
            _ -> []
          end

        value ->
          value
      end

    base_url = Config.base_map_url()
    url = "#{base_url}/api/map/systems?slug=#{Config.map_slug()}"
    headers = get_auth_headers()
    raw_result = HttpClient.get(url, headers)
    # Process the systems request
    case raw_result do
      {:ok, %{body: %{"data" => _} = body}} ->
        AppLogger.api_debug("[SystemsClient] Successfully fetched systems (map body)",
          body_type: typeof(body),
          keys: Map.keys(body)
        )

        process_systems_response(body, cached_systems, suppress_notifications)

      other ->
        AppLogger.api_error("[SystemsClient] Unexpected or failed result from HttpClient.get",
          result: inspect(other)
        )

        {:error, :unexpected_http_result}
    end
  end

  defp process_systems_response(body, cached_systems, suppress_notifications) do
    # If body is a string, decode; if it's a map, use as is
    decode_result =
      cond do
        is_binary(body) ->
          try do
            Jason.decode(body)
          rescue
            e ->
              AppLogger.api_error("[SystemsClient] Exception in Jason.decode",
                error: Exception.message(e),
                body: inspect(body)
              )

              {:error, :decode_exception}
          end

        is_map(body) ->
          {:ok, body}

        true ->
          {:error, :invalid_body_type}
      end

    case decode_result do
      {:ok, parsed_response} ->
        process_and_cache_systems(parsed_response, cached_systems, suppress_notifications)

      {:error, reason} ->
        AppLogger.api_error("[SystemsClient] Failed to process API response: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      AppLogger.api_error("⚠️ Exception in process_systems_response",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        body: inspect(body, limit: 100)
      )

      cached = cached_systems || CacheRepo.get(CacheKeys.map_systems()) || []
      {:ok, cached}
  end

  defp process_and_cache_systems(parsed_response, cached_systems, suppress_notifications) do
    # Extract systems data with fallbacks for different API formats
    systems_data = extract_systems_data(parsed_response)

    systems =
      try do
        Enum.map(systems_data, &MapSystem.new/1)
      rescue
        e ->
          AppLogger.api_error("[SystemsClient] Exception in MapSystem.new/1",
            error: Exception.message(e)
          )

          raise e
      end

    tracked_systems = filter_systems_for_tracking(systems)

    enriched_systems =
      try do
        enrich_tracked_systems(tracked_systems)
      rescue
        e ->
          AppLogger.api_error("[SystemsClient] Exception in enrich_tracked_systems",
            error: Exception.message(e)
          )

          raise e
      end

    # Log all system names and IDs during each update
    system_names = Enum.map(enriched_systems, fn sys ->
      name = Map.get(sys, :name) || Map.get(sys, "name") || "Unknown"
      id = Map.get(sys, :solar_system_id) || Map.get(sys, "solar_system_id") || "Unknown"
      %{id: id, name: name}
    end)
    AppLogger.api_info("[SystemsClient] Systems in this update: #{inspect(system_names)}")

    updated_systems =
      try do
        update_systems_cache(enriched_systems)
      rescue
        e ->
          AppLogger.api_error("[SystemsClient] Exception in update_systems_cache",
            error: Exception.message(e)
          )

          raise e
      end

    verify_systems_cached(updated_systems)

    if suppress_notifications do
      {:ok, [], updated_systems}
    else
      notify_new_systems(enriched_systems, cached_systems)
    end
  end

  # Extract systems data from different response formats
  defp extract_systems_data(parsed_response) do
    result =
      case parsed_response do
        %{"data" => data} when is_list(data) ->
          data

        %{"systems" => systems} when is_list(systems) ->
          systems

        data when is_list(data) ->
          data

        _ ->
          AppLogger.api_error("[SystemsClient] No systems found in response",
            response_type: typeof(parsed_response),
            response: inspect(parsed_response, limit: 100)
          )

          []
      end

    result
  end

  # Filter systems based on configuration
  defp filter_systems_for_tracking(systems) do
    track_kspace_systems = Config.track_kspace_systems?()
    # Filter the systems based on the configuration
    if track_kspace_systems do
      # If tracking K-space systems is enabled, return all systems
      systems
    else
      # Otherwise, filter out K-space systems
      Enum.filter(systems, fn system ->
        # Check if the system is not a K-space system
        not is_kspace_system?(system)
      end)
    end
  end

  # Helper function to determine if a system is a K-space system
  defp is_kspace_system?(system) do
    # Get the system class from the system data
    system_class = Map.get(system, :system_class)
    # Check if the system class indicates a K-space system
    system_class in ["K", "HS", "LS", "NS"]
  end

  # Enrich systems with additional data
  defp enrich_tracked_systems(systems) do
    Enum.map(systems, fn system ->
      static_info =
        if function_exported?(
             WandererNotifier.Map.SystemStaticInfo,
             :get_system_static_info,
             1
           ),
           do:
             WandererNotifier.Map.SystemStaticInfo.get_system_static_info(system.solar_system_id),
           else: %{}

      Map.merge(system, static_info)
    end)
  end

  # Update the systems cache
  defp update_systems_cache(systems) do
    # Cache the systems
    CacheRepo.put(CacheKeys.map_systems(), systems)
    # Return the systems
    systems
  end

  # Verify that systems were cached successfully
  defp verify_systems_cached(systems) do
    # Get the cached systems
    cached_systems = CacheRepo.get(CacheKeys.map_systems())
    # Compare the cached systems with the original systems
    if cached_systems == systems do
      {:ok, systems}
    else
      {:error, :cache_verification_failed}
    end
  end

  # Notify about new systems
  defp notify_new_systems(current_systems, cached_systems) do
    valid_current_systems =
      Enum.filter(current_systems, fn
        %WandererNotifier.Map.MapSystem{solar_system_id: id}
        when (is_integer(id) or is_binary(id)) and id != "" ->
          true

        _bad ->
          false
      end)

    valid_cached_systems =
      Enum.filter(cached_systems || [], fn
        %WandererNotifier.Map.MapSystem{solar_system_id: id}
        when (is_integer(id) or is_binary(id)) and id != "" ->
          true

        _bad ->
          false
      end)

    try do
      current_ids = MapSet.new(valid_current_systems, & &1.solar_system_id)
      cached_ids = MapSet.new(valid_cached_systems, & &1.solar_system_id)
      new_ids = MapSet.difference(current_ids, cached_ids)
      new_systems = Enum.filter(valid_current_systems, &(&1.solar_system_id in new_ids))
      Enum.each(new_systems, &send_new_system_notification/1)
      {:ok, new_systems, valid_current_systems}
    rescue
      e ->
        AppLogger.api_error("[SystemsClient] Error in notify_new_systems",
          error: Exception.message(e)
        )

        raise e
    end
  end

  defp send_new_system_notification(system) do
    try do
      WandererNotifier.Notifiers.Discord.Notifier.send_new_system_notification(system)
    rescue
      e ->
        AppLogger.api_error("[SystemsClient] Exception in send_new_system_notification",
          error: Exception.message(e),
          system: inspect(system)
        )

        raise e
    end
  end

  defp get_auth_headers do
    api_key = Config.map_token()
    [{"Authorization", "Bearer #{api_key}"}]
  end

  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_number(term), do: "number"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_tuple(term), do: "tuple"
  defp typeof(_term), do: "unknown"

  @doc """
  Returns a system for notification testing purposes.
  Returns {:ok, system} or {:error, :no_systems_in_cache}.
  """
  def get_system_for_notification do
    systems =
      case CacheRepo.get(WandererNotifier.Cache.Keys.map_systems()) do
        {:ok, systems} -> systems
        _ -> []
      end

    case systems do
      [system | _] -> {:ok, system}
      _ -> {:error, :no_systems_in_cache}
    end
  end
end
