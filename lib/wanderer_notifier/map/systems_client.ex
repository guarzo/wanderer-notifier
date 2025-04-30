defmodule WandererNotifier.Map.SystemsClient do
  @moduledoc """
  Client for retrieving and processing system data from the map API.
  Uses structured data types and consistent parsing to simplify the logic.
  """
  alias WandererNotifier.HttpClient.Httpoison, as: HttpClient
  alias WandererNotifier.HttpClient.UrlBuilder
  alias WandererNotifier.Map.SystemStaticInfo
  alias WandererNotifier.Config.Features
  alias WandererNotifier.Cache.Keys, as: CacheKeys
  alias WandererNotifier.Cache.Repository, as: CacheRepo
  alias WandererNotifier.Map.MapSystem
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Updates the systems in the cache.

  If cached_systems is provided, it will also identify and notify about new systems.

  ## Parameters
    - cached_systems: Optional list of cached systems for comparison

  ## Returns
    - {:ok, systems} on success
    - {:error, reason} on failure
  """
  def update_systems(cached_systems \\ nil) do
    # Get cached systems if none provided
    cached_systems = cached_systems || CacheRepo.get(CacheKeys.map_systems())

    case UrlBuilder.build_url("map/systems") do
      {:ok, url} ->
        headers = UrlBuilder.get_auth_headers()

        # Process the systems request
        case HttpClient.get(url, headers) do
          {:ok, response} ->
            process_systems_response(response, cached_systems)

          {:error, reason} ->
            AppLogger.api_error("⚠️ Failed to fetch systems", error: inspect(reason))
            {:error, {:http_error, reason}}
        end

      {:error, reason} ->
        AppLogger.api_error("⚠️ Failed to build URL", error: inspect(reason))
        {:error, reason}
    end
  end

  defp process_systems_response(response, cached_systems) do
    # Handle HTTP response locally if ErrorHandler is not available
    case response do
      %{"error" => reason} ->
        AppLogger.api_error("[SystemsClient] Failed to process API response: #{inspect(reason)}")
        {:error, reason}

      parsed_response when is_map(parsed_response) or is_list(parsed_response) ->
        AppLogger.api_debug("[SystemsClient] Successfully parsed response",
          response_keys: if(is_map(parsed_response), do: Map.keys(parsed_response), else: [])
        )

        process_and_cache_systems(parsed_response, cached_systems)

      _ ->
        AppLogger.api_error("[SystemsClient] Unexpected response format: #{inspect(response)}")
        {:error, :unexpected_response_format}
    end
  end

  defp process_and_cache_systems(parsed_response, cached_systems) do
    AppLogger.api_debug("[SystemsClient] Starting process_and_cache_systems",
      response_keys: Map.keys(parsed_response),
      has_cached_systems: not is_nil(cached_systems)
    )

    # Extract systems data with fallbacks for different API formats
    systems_data = extract_systems_data(parsed_response)

    AppLogger.api_debug("[SystemsClient] Extracted systems data",
      count: length(systems_data),
      first_system: List.first(systems_data)
    )

    systems = Enum.map(systems_data, &MapSystem.new/1)

    # Refactored logging using the helper function
    log_processing_step("Created MapSystem structs", systems)

    tracked_systems = filter_systems_for_tracking(systems)

    AppLogger.api_debug("[SystemsClient] Filtered systems for tracking",
      count: length(tracked_systems),
      first_system: List.first(tracked_systems)
    )

    enriched_systems = enrich_tracked_systems(tracked_systems)

    AppLogger.api_debug("[SystemsClient] Enriched systems",
      count: length(enriched_systems),
      first_system: List.first(enriched_systems)
    )

    # Cache the enriched systems
    updated_systems = update_systems_cache(enriched_systems)

    AppLogger.api_debug("[SystemsClient] Updated systems cache",
      count: length(updated_systems)
    )

    # Verify systems were cached successfully
    verify_systems_cached(updated_systems)

    # Check for new systems and notify
    case notify_new_systems(enriched_systems, cached_systems) do
      {:ok, _added_systems} ->
        {:ok, updated_systems}
    end
  rescue
    e ->
      AppLogger.api_error("⚠️ Exception in process_and_cache_systems",
        error: Exception.message(e),
        stacktrace: Exception.format_stacktrace(__STACKTRACE__),
        parsed_response: inspect(parsed_response, limit: 100),
        cached_systems_count: if(is_list(cached_systems), do: length(cached_systems), else: 0)
      )

      cached = cached_systems || CacheRepo.get(CacheKeys.map_systems()) || []
      {:ok, cached}
  end

  # Add the structured logging helper function as a separate function
  defp log_processing_step(step, data) do
    AppLogger.api_debug(
      "[SystemsClient] #{step}",
      count: length(data),
      first_system: List.first(data)
    )
  end

  # Extract systems data from different response formats
  defp extract_systems_data(parsed_response) do
    AppLogger.api_debug("[SystemsClient] Extracting systems data",
      response_type: typeof(parsed_response),
      response_keys: if(is_map(parsed_response), do: Map.keys(parsed_response), else: [])
    )

    result =
      case parsed_response do
        %{"data" => data} when is_list(data) ->
          AppLogger.api_debug("[SystemsClient] Found systems in data field", count: length(data))
          data

        %{"systems" => systems} when is_list(systems) ->
          AppLogger.api_debug("[SystemsClient] Found systems in systems field",
            count: length(systems)
          )

          systems

        data when is_list(data) ->
          AppLogger.api_debug("[SystemsClient] Found systems in root", count: length(data))
          data

        _ ->
          AppLogger.api_error("[SystemsClient] No systems found in response",
            response_type: typeof(parsed_response),
            response: inspect(parsed_response, limit: 100)
          )

          []
      end

    AppLogger.api_debug("[SystemsClient] Extracted systems data result",
      count: length(result),
      first_system: List.first(result)
    )

    result
  end

  # Filter systems based on configuration
  defp filter_systems_for_tracking(systems) do
    # Use the Features module for configuration
    track_kspace_systems = Features.track_kspace_systems?()
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
             WandererNotifier.Api.Map.SystemStaticInfo,
             :get_system_static_info,
             1
           ),
           do: WandererNotifier.Api.Map.SystemStaticInfo.get_system_static_info(system.system_id),
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
    # Get the system IDs from both lists
    current_ids = MapSet.new(current_systems, & &1.system_id)
    cached_ids = MapSet.new(cached_systems || [], & &1.system_id)

    # Find new system IDs
    new_ids = MapSet.difference(current_ids, cached_ids)

    # Get the new systems
    new_systems =
      Enum.filter(current_systems, fn system ->
        system.system_id in new_ids
      end)

    # Notify about new systems if there are any
    if not Enum.empty?(new_systems) do
      AppLogger.api_info("Found new systems", count: length(new_systems))

      # Send notifications for each new system
      Enum.each(new_systems, fn system ->
        notification =
          WandererNotifier.Notifiers.StructuredFormatter.format_system_notification(system)

        discord_format =
          WandererNotifier.Notifiers.StructuredFormatter.to_discord_format(notification)

        WandererNotifier.Notifications.Factory.send_system_notification(discord_format)
      end)

      {:ok, new_systems}
    else
      {:ok, []}
    end
  end

  # Helper function to determine the type of a term
  defp typeof(term) when is_nil(term), do: "nil"
  defp typeof(term) when is_binary(term), do: "string"
  defp typeof(term) when is_boolean(term), do: "boolean"
  defp typeof(term) when is_number(term), do: "number"
  defp typeof(term) when is_map(term), do: "map"
  defp typeof(term) when is_list(term), do: "list"
  defp typeof(term) when is_atom(term), do: "atom"
  defp typeof(_term), do: "unknown"

  @doc """
  Returns a system for notification testing purposes.
  Returns {:ok, system} or {:error, :no_systems_in_cache}.
  """
  def get_system_for_notification do
    systems =
      WandererNotifier.Cache.Repository.get(WandererNotifier.Cache.Keys.map_systems()) || []

    case systems do
      [system | _] -> {:ok, system}
      _ -> {:error, :no_systems_in_cache}
    end
  end
end
